#!/usr/bin/env python3
"""Create and configure the X Five consumable credit packs in App Store Connect."""

from __future__ import annotations

import base64
import hashlib
import os
import time
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any


API_ROOT = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.x5studio.app"
BASE_TERRITORY = "KAZ"
REQUEST_ATTEMPTS = 3
TRANSIENT_HTTP_STATUSES = {429, 500, 502, 503, 504}


@dataclass(frozen=True)
class CreditPack:
    product_id: str
    credits: int
    price_kaz: Decimal

    @property
    def internal_name(self) -> str:
        return f"X5 Credits {self.credits:,}"

    @property
    def review_note(self) -> str:
        return (
            f"Consumable credit pack opened from Profile -> Store. "
            f"A successful purchase adds {self.credits} credits once."
        )


CREDIT_PACKS = (
    CreditPack("com.x5studio.app.credits.1000", 1_000, Decimal("1000")),
    CreditPack("com.x5studio.app.credits.2000", 2_000, Decimal("2000")),
    CreditPack("com.x5studio.app.credits.5000", 5_000, Decimal("5000")),
)


def build_iap_create_payload(app_id: str, pack: CreditPack) -> dict[str, Any]:
    return {
        "data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": pack.internal_name,
                "productId": pack.product_id,
                "inAppPurchaseType": "CONSUMABLE",
                "reviewNote": pack.review_note,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    }


def build_availability_payload(iap_id: str) -> dict[str, Any]:
    relationships: dict[str, Any] = {
        "availableTerritories": {
            "data": [{"type": "territories", "id": BASE_TERRITORY}]
        }
    }
    data: dict[str, Any] = {
        "type": "inAppPurchaseAvailabilities",
        "attributes": {"availableInNewTerritories": False},
        "relationships": relationships,
    }
    relationships["inAppPurchase"] = {
        "data": {"type": "inAppPurchases", "id": iap_id}
    }
    return {"data": data}


def review_screenshot_reservation_payload(
    iap_id: str, filename: str, size: int
) -> dict[str, Any]:
    return {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileName": filename, "fileSize": size},
            "relationships": {
                "inAppPurchaseV2": {
                    "data": {"type": "inAppPurchases", "id": iap_id}
                }
            },
        }
    }


def build_price_schedule_payload(iap_id: str, price_point_id: str) -> dict[str, Any]:
    manual_price_id = f"${{manual-price-{iap_id}-0}}"
    return {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {
                    "data": {"type": "inAppPurchases", "id": iap_id}
                },
                "baseTerritory": {
                    "data": {"type": "territories", "id": BASE_TERRITORY}
                },
                "manualPrices": {
                    "data": [
                        {"type": "inAppPurchasePrices", "id": manual_price_id}
                    ]
                },
            },
        },
        "included": [
            {
                "type": "inAppPurchasePrices",
                "id": manual_price_id,
                "attributes": {"startDate": None},
                "relationships": {
                    "inAppPurchaseV2": {
                        "data": {"type": "inAppPurchases", "id": iap_id}
                    },
                    "inAppPurchasePricePoint": {
                        "data": {
                            "type": "inAppPurchasePricePoints",
                            "id": price_point_id,
                        }
                    },
                },
            }
        ],
    }


def localization_payload(
    iap_id: str, locale: str, name: str, description: str
) -> dict[str, Any]:
    return {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {
                "locale": locale,
                "name": name,
                "description": description,
            },
            "relationships": {
                "inAppPurchaseV2": {
                    "data": {"type": "inAppPurchases", "id": iap_id}
                }
            },
        }
    }


class AppStoreConnect:
    def __init__(self) -> None:
        import jwt
        import requests

        self.requests = requests
        token = jwt.encode(
            {
                "iss": os.environ["ASC_API_ISSUER_ID"],
                "iat": int(time.time()),
                "exp": int(time.time()) + 10 * 60,
                "aud": "appstoreconnect-v1",
            },
            base64.b64decode(os.environ["ASC_API_KEY_BASE64"]),
            algorithm="ES256",
            headers={"kid": os.environ["ASC_API_KEY_ID"], "typ": "JWT"},
        )
        self.headers = {"Authorization": f"Bearer {token}"}

    def request(
        self,
        method: str,
        path: str,
        *,
        expected: tuple[int, ...] = (200,),
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        url = path if path.startswith("http") else f"{API_ROOT}{path}"
        response = None
        for attempt in range(REQUEST_ATTEMPTS):
            try:
                response = self.requests.request(
                    method,
                    url,
                    headers={
                        **self.headers,
                        **({"Content-Type": "application/json"} if payload else {}),
                    },
                    json=payload,
                    timeout=60,
                )
            except self.requests.exceptions.RequestException as error:
                if attempt + 1 >= REQUEST_ATTEMPTS:
                    raise RuntimeError(
                        f"{method} {url} failed after {REQUEST_ATTEMPTS} attempts: "
                        f"{type(error).__name__}"
                    ) from error
                time.sleep(2**attempt)
                continue

            if (
                response.status_code in TRANSIENT_HTTP_STATUSES
                and attempt + 1 < REQUEST_ATTEMPTS
            ):
                time.sleep(2**attempt)
                continue
            break

        if response is None:
            raise RuntimeError(f"{method} {url} returned no response")
        if response.status_code not in expected:
            raise RuntimeError(
                f"{method} {response.url} -> HTTP {response.status_code}: "
                f"{response.text[:2000]}"
            )
        return response.json() if response.text else {}

    def list_all(self, path: str) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        next_path: str | None = path
        while next_path:
            page = self.request("GET", next_path)
            rows.extend(page.get("data", []))
            next_path = page.get("links", {}).get("next")
        return rows


def exact_price_point(
    api: AppStoreConnect, iap_id: str, target: Decimal
) -> dict[str, Any]:
    points = api.list_all(
        f"/v2/inAppPurchases/{iap_id}/pricePoints"
        f"?filter[territory]={BASE_TERRITORY}&include=territory&limit=200"
    )
    exact = [
        point
        for point in points
        if Decimal(str(point.get("attributes", {}).get("customerPrice"))) == target
    ]
    if not exact:
        available = ", ".join(
            str(point.get("attributes", {}).get("customerPrice"))
            for point in points[:20]
        )
        raise RuntimeError(
            f"No exact {BASE_TERRITORY} price point {target}; first values: {available}"
        )
    return exact[0]


def ensure_localization(
    api: AppStoreConnect,
    iap_id: str,
    existing: list[dict[str, Any]],
    locale: str,
    name: str,
    description: str,
) -> None:
    current = next(
        (item for item in existing if item.get("attributes", {}).get("locale") == locale),
        None,
    )
    if current:
        attributes = current.get("attributes", {})
        if attributes.get("state") == "ACTIVE":
            # Apple freezes an approved localization. Re-sending an identical
            # PATCH still returns 409, so keep the active metadata and continue
            # auditing the immutable price schedule.
            print(f"Keeping active {locale} localization for {iap_id}")
            return
        api.request(
            "PATCH",
            f"/v1/inAppPurchaseLocalizations/{current['id']}",
            payload={
                "data": {
                    "type": "inAppPurchaseLocalizations",
                    "id": current["id"],
                    "attributes": {"name": name, "description": description},
                }
            },
        )
        print(f"Updated {locale} localization for {iap_id}")
        return
    api.request(
        "POST",
        "/v1/inAppPurchaseLocalizations",
        expected=(201,),
        payload=localization_payload(iap_id, locale, name, description),
    )
    print(f"Created {locale} localization for {iap_id}")


def ensure_availability(api: AppStoreConnect, iap_id: str) -> None:
    try:
        response = api.request(
            "GET",
            f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability"
            "?include=availableTerritories&limit[availableTerritories]=50",
        )
    except RuntimeError as error:
        if "HTTP 404" not in str(error):
            raise
        response = {}

    current = response.get("data")

    if current:
        territories = {
            item.get("id")
            for item in response.get("included", [])
            if item.get("type") == "territories"
        }
        available_in_new = current.get("attributes", {}).get(
            "availableInNewTerritories"
        )
        if territories == {BASE_TERRITORY} and available_in_new is False:
            print(f"Keeping existing {BASE_TERRITORY} availability for {iap_id}")
            return
        raise RuntimeError(
            f"{iap_id} already has availability {sorted(territories)} "
            f"(availableInNewTerritories={available_in_new}); App Store Connect "
            "availability cannot be updated through the API, so correct it manually"
        )

    api.request(
        "POST",
        "/v1/inAppPurchaseAvailabilities",
        expected=(201,),
        payload=build_availability_payload(iap_id),
    )
    print(f"Created {BASE_TERRITORY} availability for {iap_id}")


def ensure_review_screenshot(
    api: AppStoreConnect, iap_id: str, screenshot_path: Path
) -> None:
    try:
        existing = api.request(
            "GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot"
        ).get("data")
    except RuntimeError as error:
        if "HTTP 404" not in str(error):
            raise
        existing = None

    if existing:
        delivery = existing.get("attributes", {}).get("assetDeliveryState")
        state = delivery.get("state") if isinstance(delivery, dict) else delivery
        if state in {"COMPLETE", "UPLOADED"}:
            print(f"Keeping uploaded review screenshot for {iap_id} ({state})")
            return
        api.request(
            "DELETE",
            f"/v1/inAppPurchaseAppStoreReviewScreenshots/{existing['id']}",
            expected=(204,),
        )
        print(f"Removed incomplete review screenshot for {iap_id} ({state})")

    if not screenshot_path.is_file():
        raise RuntimeError(f"Review screenshot not found: {screenshot_path}")

    screenshot = screenshot_path.read_bytes()
    checksum = hashlib.md5(screenshot).hexdigest()
    reservation = api.request(
        "POST",
        "/v1/inAppPurchaseAppStoreReviewScreenshots",
        expected=(201,),
        payload=review_screenshot_reservation_payload(
            iap_id, screenshot_path.name, len(screenshot)
        ),
    )["data"]
    asset_id = reservation["id"]
    for operation in reservation.get("attributes", {}).get("uploadOperations", []):
        offset = operation["offset"]
        chunk = screenshot[offset : offset + operation["length"]]
        upload_headers = {
            header["name"]: header["value"]
            for header in operation.get("requestHeaders", [])
        }
        upload = api.requests.request(
            operation["method"],
            operation["url"],
            headers=upload_headers,
            data=chunk,
            timeout=60,
        )
        if upload.status_code >= 300:
            raise RuntimeError(
                f"Review screenshot upload failed -> HTTP {upload.status_code}: "
                f"{upload.text[:1000]}"
            )

    api.request(
        "PATCH",
        f"/v1/inAppPurchaseAppStoreReviewScreenshots/{asset_id}",
        payload={
            "data": {
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "id": asset_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": checksum,
                },
            }
        },
    )
    api.request("GET", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{asset_id}")
    print(f"Uploaded review screenshot for {iap_id} -> {asset_id}")


def ensure_initial_price(
    api: AppStoreConnect, iap_id: str, target: Decimal
) -> None:
    desired_point = exact_price_point(api, iap_id, target)
    desired_id = desired_point["id"]
    try:
        current_prices = api.request(
            "GET",
            f"/v1/inAppPurchasePriceSchedules/{iap_id}/manualPrices"
            f"?filter[territory]={BASE_TERRITORY}"
            "&include=inAppPurchasePricePoint&limit=50",
        ).get("data", [])
    except RuntimeError as error:
        if "HTTP 404" not in str(error):
            raise
        current_prices = []

    current_point_ids = {
        item.get("relationships", {})
        .get("inAppPurchasePricePoint", {})
        .get("data", {})
        .get("id")
        for item in current_prices
    }
    if desired_id in current_point_ids:
        print(f"Keeping existing {target} KZT price for {iap_id}")
        return
    if current_prices:
        raise RuntimeError(
            f"{iap_id} already has a different {BASE_TERRITORY} price schedule; "
            "refusing to replace it implicitly"
        )
    api.request(
        "POST",
        "/v1/inAppPurchasePriceSchedules",
        expected=(201,),
        payload=build_price_schedule_payload(iap_id, desired_id),
    )
    print(f"Created {target} KZT price for {iap_id}")


def configure() -> None:
    api = AppStoreConnect()
    screenshot_path = Path(os.environ["SCREENSHOT_PATH"])
    apps = api.request("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}").get("data", [])
    if not apps:
        raise RuntimeError(f"No App Store Connect app found for {BUNDLE_ID}")
    app_id = apps[0]["id"]
    purchases = api.list_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200")
    by_product_id = {
        item.get("attributes", {}).get("productId"): item for item in purchases
    }

    for pack in CREDIT_PACKS:
        purchase = by_product_id.get(pack.product_id)
        if purchase:
            iap_id = purchase["id"]
            if purchase.get("attributes", {}).get("inAppPurchaseType") != "CONSUMABLE":
                raise RuntimeError(f"{pack.product_id} exists but is not CONSUMABLE")
            api.request(
                "PATCH",
                f"/v2/inAppPurchases/{iap_id}",
                payload={
                    "data": {
                        "type": "inAppPurchases",
                        "id": iap_id,
                        "attributes": {
                            "name": pack.internal_name,
                            "reviewNote": pack.review_note,
                        },
                    }
                },
            )
            print(f"Updated {pack.product_id} -> {iap_id}")
        else:
            purchase = api.request(
                "POST",
                "/v2/inAppPurchases",
                expected=(201,),
                payload=build_iap_create_payload(app_id, pack),
            )["data"]
            iap_id = purchase["id"]
            print(f"Created {pack.product_id} -> {iap_id}")

        localizations = api.list_all(
            f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations?limit=200"
        )
        ensure_localization(
            api,
            iap_id,
            localizations,
            "en-US",
            f"{pack.credits:,} X5 Credits",
            f"Adds {pack.credits:,} credits to your X5 balance once.",
        )
        ensure_localization(
            api,
            iap_id,
            localizations,
            "ru",
            f"{pack.credits:,} кредитов X5".replace(",", " "),
            f"Разово добавляет {pack.credits:,} кредитов на баланс.".replace(",", " "),
        )
        ensure_availability(api, iap_id)
        ensure_initial_price(api, iap_id, pack.price_kaz)
        ensure_review_screenshot(api, iap_id, screenshot_path)

    print("Configured App Store credit packs:")
    for pack in CREDIT_PACKS:
        print(f"  {pack.product_id}: +{pack.credits} credits, {pack.price_kaz} KZT")


if __name__ == "__main__":
    configure()
