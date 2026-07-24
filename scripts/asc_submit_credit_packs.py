#!/usr/bin/env python3
"""Audit and submit the three consumable credit packs to App Review."""

from __future__ import annotations

import argparse
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


def submission_payload(iap_id: str) -> dict[str, Any]:
    return {
        "data": {
            "type": "inAppPurchaseSubmissions",
            "relationships": {
                "inAppPurchaseV2": {
                    "data": {
                        "type": "inAppPurchases",
                        "id": iap_id,
                    }
                }
            },
        }
    }


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

    submitted: list[str] = []
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
        if should_submit(state, action=action):
            response = api.request(
                "POST",
                "/v1/inAppPurchaseSubmissions",
                expected=(201,),
                payload=submission_payload(purchase["id"]),
            )
            submission_id = response.get("data", {}).get("id")
            print(
                f"Submitted {pack.product_id} for App Review "
                f"submission={submission_id}"
            )
            submitted.append(pack.product_id)
        elif action == "submit":
            print(f"Skipping {pack.product_id}: already {state}")

    print(f"Credit pack action={action} submitted={len(submitted)}")


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
