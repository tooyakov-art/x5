#!/usr/bin/env python3
"""Audit and submit the three consumable credit packs with the app version."""

from __future__ import annotations

import argparse
import time
from typing import Any

from asc_configure_credit_store import (
    AppStoreConnect,
    BUNDLE_ID,
    CREDIT_PACKS,
)


SUBMITTABLE_STATE = "READY_TO_SUBMIT"
REVIEWED_STATES = {
    "APPROVED",
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
}
TARGET_VERSION = "1.1.6"
TARGET_BUILD = "189"
EDITABLE_APP_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "READY_FOR_REVIEW",
    "DEVELOPER_REJECTED",
    "REJECTED",
}


def iap_version_payload(iap_id: str) -> dict[str, Any]:
    return {
        "data": {
            "type": "inAppPurchaseVersions",
            "relationships": {
                "inAppPurchase": {
                    "data": {
                        "type": "inAppPurchases",
                        "id": iap_id,
                    }
                }
            },
        }
    }


def review_submission_payload(app_id: str) -> dict[str, Any]:
    return {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}}
            },
        }
    }


def review_item_payload(
    submission_id: str,
    relationship: str,
    resource_type: str,
    resource_id: str,
) -> dict[str, Any]:
    return {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {
                    "data": {
                        "type": "reviewSubmissions",
                        "id": submission_id,
                    }
                },
                relationship: {
                    "data": {
                        "type": resource_type,
                        "id": resource_id,
                    }
                },
            },
        }
    }


def submit_review_payload(submission_id: str) -> dict[str, Any]:
    return {
        "data": {
            "type": "reviewSubmissions",
            "id": submission_id,
            "attributes": {"submitted": True},
        }
    }


def single_ready_submission(
    submissions: list[dict[str, Any]],
) -> dict[str, Any] | None:
    ready = [
        row
        for row in submissions
        if row.get("attributes", {}).get("state") == "READY_FOR_REVIEW"
    ]
    if len(ready) > 1:
        raise RuntimeError(
            f"More than one READY_FOR_REVIEW submission exists: {len(ready)}"
        )
    return ready[0] if ready else None


def should_submit(state: str, *, action: str) -> bool:
    if action == "audit":
        return False
    if state == SUBMITTABLE_STATE:
        return True
    if state in REVIEWED_STATES:
        return False
    raise RuntimeError(
        f"Credit pack cannot be submitted safely from App Store state {state}"
    )


def app_version(
    api: AppStoreConnect, app_id: str
) -> dict[str, Any]:
    versions = api.list_all(
        f"/v1/apps/{app_id}/appStoreVersions?limit=50"
    )
    target = next(
        (
            row
            for row in versions
            if row.get("attributes", {}).get("versionString")
            == TARGET_VERSION
            and row.get("attributes", {}).get("platform") == "IOS"
        ),
        None,
    )
    if not target:
        raise RuntimeError(f"No iOS App Store version {TARGET_VERSION}")
    return target


def verify_target_build(
    api: AppStoreConnect, version_id: str
) -> None:
    attached = api.request(
        "GET", f"/v1/appStoreVersions/{version_id}/build"
    ).get("data")
    if not attached:
        raise RuntimeError("App Store version has no attached build")
    attrs = attached.get("attributes", {})
    print(
        f"Attached build: id={attached['id']} "
        f"version={attrs.get('version')} state={attrs.get('processingState')}"
    )
    if attrs.get("version") != TARGET_BUILD:
        raise RuntimeError(
            f"Attached build is {attrs.get('version')}, expected {TARGET_BUILD}"
        )
    if attrs.get("processingState") != "VALID" or attrs.get("expired"):
        raise RuntimeError(f"Build {TARGET_BUILD} is not valid and current")


def ensure_iap_version(
    api: AppStoreConnect,
    iap_id: str,
) -> dict[str, Any]:
    versions = api.list_all(
        f"/v2/inAppPurchases/{iap_id}/versions?limit=50"
    )
    for version in versions:
        attrs = version.get("attributes", {})
        print(
            f"  existing IAP version id={version['id']} "
            f"state={attrs.get('state')}"
        )
    draft = next(
        (
            row
            for row in versions
            if row.get("attributes", {}).get("state")
            in {
                "PREPARE_FOR_SUBMISSION",
                "READY_FOR_REVIEW",
                "DEVELOPER_REJECTED",
                "REJECTED",
            }
        ),
        None,
    )
    if draft:
        return draft
    created = api.request(
        "POST",
        "/v1/inAppPurchaseVersions",
        expected=(201,),
        payload=iap_version_payload(iap_id),
    )["data"]
    print(
        f"  created IAP version id={created['id']} "
        f"state={created.get('attributes', {}).get('state')}"
    )
    return created


def cancel_waiting_app_review(
    api: AppStoreConnect,
    app_id: str,
    version_id: str,
) -> None:
    version_state = app_version(api, app_id).get("attributes", {}).get(
        "appStoreState"
    )
    print(f"App version state before combined review: {version_state}")
    if version_state in EDITABLE_APP_STATES:
        return
    if version_state == "IN_REVIEW":
        raise RuntimeError(
            "App version moved to IN_REVIEW; refusing to cancel it automatically"
        )
    if version_state != "WAITING_FOR_REVIEW":
        raise RuntimeError(
            f"App version cannot be safely resubmitted from {version_state}"
        )

    review_payload = api.request(
        "GET",
        f"/v1/reviewSubmissions?filter[app]={app_id}"
        "&filter[platform]=IOS&include=items",
    )
    waiting = [
        row
        for row in review_payload.get("data", [])
        if row.get("attributes", {}).get("state") == "WAITING_FOR_REVIEW"
    ]
    if len(waiting) != 1:
        raise RuntimeError(
            f"Expected one WAITING_FOR_REVIEW submission, found {len(waiting)}"
        )
    submission_id = waiting[0]["id"]
    print(f"Cancelling app-only review submission {submission_id}")
    api.request(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        payload={
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"canceled": True},
            }
        },
    )

    for attempt in range(1, 31):
        state = app_version(api, app_id).get("attributes", {}).get(
            "appStoreState"
        )
        print(f"App version state after cancel {attempt}/30: {state}")
        if state in EDITABLE_APP_STATES:
            return
        if state == "IN_REVIEW":
            raise RuntimeError(
                "App version moved to IN_REVIEW during cancellation"
            )
        time.sleep(2)
    raise RuntimeError("App version did not become editable after cancellation")


def create_combined_review(
    api: AppStoreConnect,
    app_id: str,
    app_version_id: str,
    iap_versions: list[dict[str, Any]],
) -> str:
    existing = api.request(
        "GET",
        f"/v1/reviewSubmissions?filter[app]={app_id}"
        "&filter[platform]=IOS",
    ).get("data", [])
    submission = single_ready_submission(existing)
    if submission:
        print(f"Reusing READY ReviewSubmission {submission['id']}")
    else:
        submission = api.request(
            "POST",
            "/v1/reviewSubmissions",
            expected=(201,),
            payload=review_submission_payload(app_id),
        )["data"]
        print(f"Created combined ReviewSubmission {submission['id']}")
    submission_id = submission["id"]

    api.request(
        "POST",
        "/v1/reviewSubmissionItems",
        expected=(201,),
        payload=review_item_payload(
            submission_id,
            "appStoreVersion",
            "appStoreVersions",
            app_version_id,
        ),
    )
    print(f"Attached App Store version {TARGET_VERSION} build {TARGET_BUILD}")

    for version in iap_versions:
        api.request(
            "POST",
            "/v1/reviewSubmissionItems",
            expected=(201,),
            payload=review_item_payload(
                submission_id,
                "inAppPurchaseVersion",
                "inAppPurchaseVersions",
                version["id"],
            ),
        )
        print(f"Attached IAP version {version['id']}")

    submitted = api.request(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        payload=submit_review_payload(submission_id),
    )["data"]
    final_state = submitted.get("attributes", {}).get("state")
    print(f"Submitted combined review state={final_state}")
    if final_state not in {"WAITING_FOR_REVIEW", "IN_REVIEW"}:
        raise RuntimeError(f"Unexpected combined review state {final_state}")
    return submission_id


def run(action: str) -> None:
    api = AppStoreConnect()
    apps = api.request("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}").get(
        "data", []
    )
    if not apps:
        raise RuntimeError(f"No App Store Connect app found for {BUNDLE_ID}")
    app_id = apps[0]["id"]
    purchases = api.list_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200")
    by_product_id = {
        item.get("attributes", {}).get("productId"): item for item in purchases
    }

    missing = [
        pack.product_id
        for pack in CREDIT_PACKS
        if pack.product_id not in by_product_id
    ]
    if missing:
        raise RuntimeError(f"Missing credit packs: {', '.join(missing)}")

    products_for_review: list[dict[str, Any]] = []
    for pack in CREDIT_PACKS:
        purchase = by_product_id[pack.product_id]
        attributes = purchase.get("attributes", {})
        state = str(attributes.get("state") or "")
        purchase_type = attributes.get("inAppPurchaseType")
        print(
            f"Credit pack {pack.product_id}: id={purchase['id']} "
            f"type={purchase_type} state={state}"
        )
        if purchase_type != "CONSUMABLE":
            raise RuntimeError(f"{pack.product_id} is not CONSUMABLE")
        existing_versions = api.list_all(
            f"/v2/inAppPurchases/{purchase['id']}/versions?limit=50"
        )
        for version in existing_versions:
            print(
                f"  IAP version {version['id']} "
                f"state={version.get('attributes', {}).get('state')}"
            )
        if action == "submit" and should_submit(state, action=action):
            products_for_review.append(purchase)
        elif action == "submit":
            print(f"Skipping {pack.product_id}: already {state}")

    if action == "audit":
        print("Credit pack action=audit submitted=0")
        return
    if not products_for_review:
        print("All credit packs are already reviewed or in review")
        return

    target_version = app_version(api, app_id)
    target_version_id = target_version["id"]
    verify_target_build(api, target_version_id)
    iap_versions = [
        ensure_iap_version(api, purchase["id"])
        for purchase in products_for_review
    ]
    cancel_waiting_app_review(
        api,
        app_id,
        target_version_id,
    )
    submission_id = create_combined_review(
        api,
        app_id,
        target_version_id,
        iap_versions,
    )
    print(
        f"Credit pack action=submit combined_submission={submission_id} "
        f"iap_versions={len(iap_versions)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--action",
        choices=("audit", "submit"),
        default="audit",
    )
    args = parser.parse_args()
    run(args.action)


if __name__ == "__main__":
    main()
