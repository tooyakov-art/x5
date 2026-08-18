"""Set App Store version 1.1.6 to automatic release after Apple approval."""

from __future__ import annotations

import base64
import os
import time
from typing import Protocol


EXPECTED_VERSION = "1.1.6"
EXPECTED_BUILD = "227"
EXPECTED_STATE = "WAITING_FOR_REVIEW"
TARGET_RELEASE_TYPE = "AFTER_APPROVAL"


class ReleaseTypeClient(Protocol):
    def find_app_id(self, bundle_id: str) -> str: ...

    def list_versions(self, app_id: str) -> list[dict]: ...

    def get_attached_build(self, version_id: str) -> dict: ...

    def update_release_type(self, version_id: str, release_type: str) -> None: ...

    def get_version(self, version_id: str) -> dict: ...


def set_after_approval(
    client: ReleaseTypeClient,
    *,
    bundle_id: str,
    version_string: str,
    build_number: str,
) -> dict[str, str]:
    """PATCH only releaseType after strict version, build and state guards."""

    if version_string != EXPECTED_VERSION:
        raise ValueError(
            f"Refusing version {version_string}; expected {EXPECTED_VERSION}"
        )
    if build_number != EXPECTED_BUILD:
        raise ValueError(f"Refusing build {build_number}; expected {EXPECTED_BUILD}")

    app_id = client.find_app_id(bundle_id)
    matching = [
        row
        for row in client.list_versions(app_id)
        if row.get("attributes", {}).get("versionString") == version_string
        and row.get("attributes", {}).get("platform") == "IOS"
    ]
    if len(matching) != 1:
        raise ValueError(
            f"Expected exactly one iOS version {version_string}, found {len(matching)}"
        )

    version = matching[0]
    version_id = version["id"]
    before = version.get("attributes", {})
    if before.get("appStoreState") != EXPECTED_STATE:
        raise ValueError(
            f"Refusing state {before.get('appStoreState')}; expected {EXPECTED_STATE}"
        )
    if before.get("releaseType") not in {"MANUAL", TARGET_RELEASE_TYPE}:
        raise ValueError(f"Refusing releaseType {before.get('releaseType')}")

    build = client.get_attached_build(version_id)
    build_attrs = build.get("attributes", {}) if build else {}
    if (
        build_attrs.get("version") != build_number
        or build_attrs.get("processingState") != "VALID"
        or build_attrs.get("expired")
    ):
        raise ValueError(
            f"Attached build is not the expected valid build {build_number}: {build_attrs}"
        )

    if before.get("releaseType") != TARGET_RELEASE_TYPE:
        client.update_release_type(version_id, TARGET_RELEASE_TYPE)

    # Mandatory fresh GET: the review state must remain unchanged.
    confirmed = client.get_version(version_id)
    attrs = confirmed.get("attributes", {})
    if attrs.get("versionString") != version_string:
        raise RuntimeError("Version changed during releaseType PATCH")
    if attrs.get("appStoreState") != EXPECTED_STATE:
        raise RuntimeError(
            f"Review state changed unexpectedly: {attrs.get('appStoreState')}"
        )
    if attrs.get("releaseType") != TARGET_RELEASE_TYPE:
        raise RuntimeError(
            f"releaseType was not confirmed: {attrs.get('releaseType')}"
        )

    return {
        "versionString": attrs["versionString"],
        "appStoreState": attrs["appStoreState"],
        "releaseType": attrs["releaseType"],
        "build": build_number,
    }


class AppStoreConnectClient:
    BASE_URL = "https://api.appstoreconnect.apple.com/v1"

    def __init__(self, token: str):
        import requests

        self._requests = requests
        self._headers = {"Authorization": f"Bearer {token}"}

    @classmethod
    def from_env(cls) -> "AppStoreConnectClient":
        import jwt

        token = jwt.encode(
            {
                "iss": os.environ["ASC_API_ISSUER_ID"],
                "iat": int(time.time()),
                "exp": int(time.time()) + 600,
                "aud": "appstoreconnect-v1",
            },
            base64.b64decode(os.environ["ASC_API_KEY_BASE64"]),
            algorithm="ES256",
            headers={"kid": os.environ["ASC_API_KEY_ID"], "typ": "JWT"},
        )
        return cls(token)

    def _get_all(self, path: str, params: dict | None = None) -> list[dict]:
        rows: list[dict] = []
        url = f"{self.BASE_URL}{path}"
        next_params = params
        while url:
            response = self._requests.get(
                url,
                headers=self._headers,
                params=next_params,
                timeout=60,
            )
            response.raise_for_status()
            payload = response.json()
            rows.extend(payload.get("data", []))
            url = payload.get("links", {}).get("next")
            next_params = None
        return rows

    def find_app_id(self, bundle_id: str) -> str:
        apps = self._get_all("/apps", {"filter[bundleId]": bundle_id})
        if len(apps) != 1:
            raise ValueError(f"Expected one app for {bundle_id}, found {len(apps)}")
        return apps[0]["id"]

    def list_versions(self, app_id: str) -> list[dict]:
        return self._get_all(f"/apps/{app_id}/appStoreVersions", {"limit": 50})

    def get_attached_build(self, version_id: str) -> dict:
        response = self._requests.get(
            f"{self.BASE_URL}/appStoreVersions/{version_id}/build",
            headers=self._headers,
            timeout=60,
        )
        response.raise_for_status()
        return response.json().get("data")

    def update_release_type(self, version_id: str, release_type: str) -> None:
        response = self._requests.patch(
            f"{self.BASE_URL}/appStoreVersions/{version_id}",
            headers={**self._headers, "Content-Type": "application/json"},
            json={
                "data": {
                    "type": "appStoreVersions",
                    "id": version_id,
                    "attributes": {"releaseType": release_type},
                }
            },
            timeout=60,
        )
        if response.status_code != 200:
            raise RuntimeError(
                f"releaseType PATCH failed: HTTP {response.status_code} "
                f"{response.text[:1000]}"
            )

    def get_version(self, version_id: str) -> dict:
        response = self._requests.get(
            f"{self.BASE_URL}/appStoreVersions/{version_id}",
            headers=self._headers,
            timeout=60,
        )
        response.raise_for_status()
        return response.json()["data"]


def main() -> int:
    result = set_after_approval(
        AppStoreConnectClient.from_env(),
        bundle_id="com.x5studio.app",
        version_string=EXPECTED_VERSION,
        build_number=EXPECTED_BUILD,
    )
    print(
        "AFTER_APPROVAL_CONFIRMED "
        f"version={result['versionString']} build={result['build']} "
        f"state={result['appStoreState']} releaseType={result['releaseType']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
