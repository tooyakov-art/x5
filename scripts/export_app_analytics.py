#!/usr/bin/env python3
"""Export privacy-safe aggregate X5 analytics for the public dashboard."""

from __future__ import annotations

import argparse
import base64
import csv
import gzip
import io
import json
import os
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import jwt
import requests


ASC_BASE = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.x5studio.app"
ACCESS_TYPES = ("ONE_TIME_SNAPSHOT", "ONGOING")
REPORT_KINDS = {
    "downloads": ("app downloads",),
    "installs": ("installation and deletion",),
    "sessions": ("app sessions",),
    "crashes": ("app crashes",),
    "commerce": ("commerce",),
}
VALUE_COLUMNS = {
    "downloads": ("Counts", "Count", "Downloads", "Units", "Value"),
    "installs": ("Counts", "Count", "Installs", "Units", "Value"),
    "sessions": ("Sessions", "Counts", "Count", "Value"),
    "crashes": ("Crashes", "Counts", "Count", "Value"),
    "commerce": ("Units", "Quantity", "Counts", "Count", "Value"),
}
DATE_COLUMNS = ("Date", "date", "Begin Date", "Start Date")
COUNTRY_COLUMNS = ("Territory", "Country", "Storefront", "Country Code")
CURRENCY_COLUMNS = ("Currency", "Customer Currency", "Developer Proceeds Currency")
REVENUE_COLUMNS = ("Developer Proceeds", "Proceeds", "Customer Sales", "Sales")


class AppleAPIError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="analytics-data/latest.json")
    parser.add_argument("--bundle-id", default=BUNDLE_ID)
    parser.add_argument("--max-days", type=int, default=90)
    return parser.parse_args()


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise AppleAPIError(f"missing environment variable: {name}")
    return value


def apple_token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": required_env("ASC_API_ISSUER_ID"), "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        base64.b64decode(required_env("ASC_API_KEY_BASE64")),
        algorithm="ES256",
        headers={"kid": required_env("ASC_API_KEY_ID"), "typ": "JWT"},
    )


class AppleClient:
    def __init__(self, token: str) -> None:
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Bearer {token}", "Content-Type": "application/json"})

    def request(self, method: str, url: str, *, params=None, payload=None, allowed=()) -> requests.Response:
        response = self.session.request(method, url, params=params, json=payload, timeout=90)
        if response.status_code >= 400 and response.status_code not in set(allowed):
            raise AppleAPIError(
                f"Apple API {method} {url.replace(ASC_BASE, '')} returned "
                f"{response.status_code}: {response.text[:300]}"
            )
        return response

    def get_all(self, url: str, params: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        next_url: str | None = url
        query = dict(params or {})
        query.setdefault("limit", 200)
        while next_url:
            body = self.request("GET", next_url, params=query).json()
            rows.extend(body.get("data", []))
            next_url = body.get("links", {}).get("next")
            query = {}
        return rows


def find_app(client: AppleClient, bundle_id: str) -> dict[str, Any]:
    rows = client.request(
        "GET", f"{ASC_BASE}/apps", params={"filter[bundleId]": bundle_id, "limit": 10}
    ).json().get("data", [])
    if len(rows) != 1:
        raise AppleAPIError(f"expected one app for {bundle_id}, got {len(rows)}")
    return rows[0]


def ensure_report_request(client: AppleClient, app_id: str, access_type: str) -> tuple[str | None, bool]:
    url = f"{ASC_BASE}/apps/{app_id}/analyticsReportRequests"
    rows = client.get_all(url, {"filter[accessType]": access_type})
    if rows:
        return rows[0]["id"], False
    payload = {
        "data": {
            "type": "analyticsReportRequests",
            "attributes": {"accessType": access_type},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    response = client.request(
        "POST", f"{ASC_BASE}/analyticsReportRequests", payload=payload, allowed=(409,)
    )
    if response.status_code == 201:
        return response.json().get("data", {}).get("id"), True
    rows = client.get_all(url, {"filter[accessType]": access_type})
    return (rows[0]["id"] if rows else None), False


def report_kind(name: str) -> str | None:
    lowered = name.casefold()
    for kind, needles in REPORT_KINDS.items():
        if all(needle in lowered for needle in needles):
            return kind
    return None


def first_present(row: dict[str, str], names: Iterable[str]) -> str | None:
    for name in names:
        value = row.get(name)
        if value not in (None, ""):
            return value
    return None


def parse_number(raw: str | None) -> float | None:
    if raw in (None, ""):
        return None
    value = str(raw).strip().replace("\u00a0", "").replace(" ", "")
    if value.count(",") == 1 and "." not in value:
        left, right = value.split(",")
        value = f"{left}.{right}" if len(right) <= 2 else left + right
    else:
        value = value.replace(",", "")
    try:
        return float(value)
    except ValueError:
        return None


def segment_rows(client: AppleClient, url: str) -> list[dict[str, str]]:
    response = client.session.get(url, timeout=120)
    if response.status_code >= 400:
        raise AppleAPIError(f"analytics segment returned {response.status_code}")
    raw = gzip.decompress(response.content) if response.content[:2] == b"\x1f\x8b" else response.content
    text = raw.decode("utf-8", errors="replace")
    first_line = text.splitlines()[0] if text else ""
    return list(csv.DictReader(io.StringIO(text), delimiter="\t" if "\t" in first_line else ","))


def collect_report_rows(client: AppleClient, report_id: str) -> list[dict[str, str]]:
    instances = client.get_all(
        f"{ASC_BASE}/analyticsReports/{report_id}/instances", {"filter[granularity]": "DAILY"}
    )
    instances.sort(key=lambda row: row.get("attributes", {}).get("processingDate", ""), reverse=True)
    rows: list[dict[str, str]] = []
    for instance in instances[:120]:
        for segment in client.get_all(f"{ASC_BASE}/analyticsReportInstances/{instance['id']}/segments"):
            url = segment.get("attributes", {}).get("url")
            if url:
                rows.extend(segment_rows(client, url))
    return rows


def collect_analytics(client: AppleClient, app_id: str, max_days: int) -> tuple[dict[str, Any], list[str], list[str]]:
    sources: list[tuple[str, str]] = []
    created: list[str] = []
    errors: list[str] = []
    for access_type in ACCESS_TYPES:
        try:
            request_id, was_created = ensure_report_request(client, app_id, access_type)
            if request_id:
                sources.append((access_type, request_id))
            if was_created:
                created.append(access_type)
        except AppleAPIError as exc:
            errors.append(f"{access_type}:{exc}")

    source_daily: dict[str, dict[str, dict[str, float]]] = {}
    source_countries: dict[str, dict[str, float]] = {}
    source_revenue: dict[str, dict[str, float]] = {}
    for access_type, request_id in sources:
        daily: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
        countries: dict[str, float] = defaultdict(float)
        revenue: dict[str, float] = defaultdict(float)
        try:
            reports = client.get_all(f"{ASC_BASE}/analyticsReportRequests/{request_id}/reports")
            for report in reports:
                name = str(report.get("attributes", {}).get("name") or "")
                kind = report_kind(name)
                if not kind:
                    continue
                try:
                    rows = collect_report_rows(client, report["id"])
                except AppleAPIError as exc:
                    errors.append(f"segment:{name}:{exc}")
                    continue
                for row in rows:
                    raw_date = first_present(row, DATE_COLUMNS)
                    day = raw_date[:10] if raw_date and len(raw_date) >= 10 else None
                    if not day:
                        continue
                    value = parse_number(first_present(row, VALUE_COLUMNS[kind]))
                    if value is not None:
                        metric = "purchases" if kind == "commerce" else kind
                        daily[day][metric] += value
                        if kind == "downloads":
                            country = first_present(row, COUNTRY_COLUMNS)
                            if country:
                                countries[country] += value
                    if kind == "commerce":
                        proceeds = parse_number(first_present(row, REVENUE_COLUMNS))
                        if proceeds is not None:
                            revenue[first_present(row, CURRENCY_COLUMNS) or "USD"] += proceeds
        except AppleAPIError as exc:
            errors.append(f"reports:{access_type}:{exc}")
        source_daily[access_type] = daily
        source_countries[access_type] = countries
        source_revenue[access_type] = revenue

    merged_daily: dict[str, dict[str, float]] = {}
    for access_type in ACCESS_TYPES:
        for day, values in source_daily.get(access_type, {}).items():
            merged_daily[day] = dict(values)
    days = sorted(merged_daily)[-max_days:]
    trend = [
        {
            "date": day,
            "downloads": round(merged_daily[day].get("downloads", 0)),
            "installs": round(merged_daily[day].get("installs", 0)),
            "purchases": round(merged_daily[day].get("purchases", 0)),
            "sessions": round(merged_daily[day].get("sessions", 0)),
        }
        for day in days
    ]
    country_totals: dict[str, float] = {}
    revenue_totals: dict[str, float] = {}
    for access_type in ACCESS_TYPES:
        if source_countries.get(access_type):
            country_totals = dict(source_countries[access_type])
        if source_revenue.get(access_type):
            revenue_totals = dict(source_revenue[access_type])
    download_total = sum(country_totals.values())
    countries = [
        {
            "country": country,
            "downloads": round(value),
            "share": round(value / download_total * 100, 2) if download_total else 0,
        }
        for country, value in sorted(country_totals.items(), key=lambda item: item[1], reverse=True)
    ]
    currency = "USD" if "USD" in revenue_totals else (max(revenue_totals, key=revenue_totals.get) if revenue_totals else "USD")
    totals = {
        key: round(sum(row.get(key, 0) for row in trend), 2)
        for key in ("downloads", "installs", "purchases", "sessions")
    }
    return (
        {
            "trend": trend,
            "countries": countries,
            "totals": totals,
            "revenue": round(revenue_totals.get(currency, 0), 2),
            "currency": currency,
            "hasData": bool(trend),
        },
        created,
        errors,
    )


def collect_builds(client: AppleClient, app_id: str) -> list[dict[str, Any]]:
    body = client.request(
        "GET",
        f"{ASC_BASE}/builds",
        params={
            "filter[app]": app_id,
            "filter[preReleaseVersion.platform]": "IOS",
            "include": "preReleaseVersion",
            "sort": "-uploadedDate",
            "limit": 10,
        },
    ).json()
    prereleases = {
        row["id"]: row.get("attributes", {}).get("version")
        for row in body.get("included", [])
        if row.get("type") == "preReleaseVersions"
    }
    builds = []
    for index, row in enumerate(body.get("data", [])):
        attrs = row.get("attributes", {})
        pre_id = row.get("relationships", {}).get("preReleaseVersion", {}).get("data", {}).get("id")
        status = attrs.get("processingState") or "UNKNOWN"
        if index == 0:
            detail = client.request("GET", f"{ASC_BASE}/builds/{row['id']}/buildBetaDetail", allowed=(404,))
            if detail.status_code == 200:
                status = detail.json().get("data", {}).get("attributes", {}).get("internalBuildState") or status
        builds.append(
            {
                "platform": "iOS",
                "version": prereleases.get(pre_id),
                "build": attrs.get("version"),
                "status": status,
                "processingState": attrs.get("processingState"),
                "uploadedDate": attrs.get("uploadedDate"),
            }
        )
    return builds


def unavailable_metric(status: str) -> dict[str, Any]:
    return {"value": None, "status": status}


def base_snapshot() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "sync": {
            "status": "preparing",
            "message": "Apple готовит исторические отчёты",
            "detail": "Первая выгрузка Analytics Reports может занять 24–48 часов.",
        },
        "overview": {
            "downloads": unavailable_metric("preparing"),
            "installs": unavailable_metric("preparing"),
            "purchases": unavailable_metric("preparing"),
            "revenue": {"value": None, "currency": "USD", "status": "preparing"},
            "activeSubscriptions": unavailable_metric("not_connected"),
            "refunds": unavailable_metric("not_connected"),
        },
        "platforms": [
            {"id": "ios", "name": "iOS", "installs": None, "status": "preparing"},
            {"id": "android", "name": "Android", "installs": None, "status": "not_connected"},
        ],
        "trend": [],
        "countries": [],
        "builds": [],
        "sources": {
            "apple": {"status": "preparing", "detail": "Analytics Reports"},
            "google": {"status": "not_connected", "detail": "Нужны Play service account и GCS report bucket"},
            "payments": {"status": "not_connected", "detail": "Нужен серверный доступ к агрегатам Supabase"},
        },
    }


def make_snapshot(bundle_id: str, max_days: int) -> dict[str, Any]:
    snapshot = base_snapshot()
    try:
        client = AppleClient(apple_token())
        app = find_app(client, bundle_id)
        snapshot["builds"] = collect_builds(client, app["id"])
        analytics, created, errors = collect_analytics(client, app["id"], max_days)
        if analytics["hasData"]:
            totals = analytics["totals"]
            snapshot["overview"].update(
                {
                    "downloads": {"value": totals["downloads"], "status": "ready"},
                    "installs": {"value": totals["installs"], "status": "ready"},
                    "purchases": {"value": totals["purchases"], "status": "ready"},
                    "revenue": {"value": analytics["revenue"], "currency": analytics["currency"], "status": "ready"},
                }
            )
            snapshot["platforms"][0].update({"installs": totals["installs"], "status": "ready"})
            snapshot["trend"] = analytics["trend"]
            snapshot["countries"] = analytics["countries"]
            snapshot["sync"] = {"status": "ready", "message": "Данные Apple обновлены", "detail": f"Период: последние {max_days} дней."}
            snapshot["sources"]["apple"] = {"status": "connected", "detail": "App Store Connect Analytics Reports"}
        else:
            detail = "Исторический snapshot запрошен; Apple формирует сегменты."
            if created:
                detail = f"Созданы отчёты: {', '.join(created)}. Apple формирует историю."
            snapshot["sync"]["detail"] = detail
            snapshot["sources"]["apple"]["detail"] = detail
        if errors:
            snapshot["sources"]["apple"]["warnings"] = [
                "Некоторые отчёты Apple пока недоступны; синхронизация повторится автоматически."
            ]
    except Exception:
        # Keep deploys usable without publishing API response bodies or secrets.
        detail = "Apple API временно недоступен; синхронизация повторится автоматически."
        snapshot["sync"] = {"status": "preparing", "message": "Apple Analytics временно недоступен", "detail": detail}
        snapshot["sources"]["apple"] = {"status": "preparing", "detail": detail}
    return snapshot


def main() -> int:
    args = parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    snapshot = make_snapshot(args.bundle_id, args.max_days)
    output.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "sync": snapshot["sync"]["status"], "builds": len(snapshot["builds"]), "trendDays": len(snapshot["trend"])}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
