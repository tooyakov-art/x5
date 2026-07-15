import importlib.util
import inspect
import pathlib
import sys
import unittest
from decimal import Decimal


SCRIPT = pathlib.Path(__file__).parents[1] / "asc_configure_credit_store.py"
SPEC = importlib.util.spec_from_file_location("asc_credit_store", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CreditStoreConfigurationTests(unittest.TestCase):
    def test_catalog_has_exactly_three_consumable_credit_packs(self):
        self.assertEqual(
            [pack.product_id for pack in MODULE.CREDIT_PACKS],
            [
                "com.x5studio.app.credits.1000",
                "com.x5studio.app.credits.2000",
                "com.x5studio.app.credits.5000",
            ],
        )
        self.assertEqual(
            [(pack.credits, pack.price_kaz) for pack in MODULE.CREDIT_PACKS],
            [
                (1_000, Decimal("1000")),
                (2_000, Decimal("2000")),
                (5_000, Decimal("5000")),
            ],
        )

    def test_create_payload_marks_pack_as_consumable(self):
        payload = MODULE.build_iap_create_payload("app-1", MODULE.CREDIT_PACKS[0])
        data = payload["data"]
        self.assertEqual(data["type"], "inAppPurchases")
        self.assertEqual(data["attributes"]["inAppPurchaseType"], "CONSUMABLE")
        self.assertNotIn("availableInAllTerritories", data["attributes"])
        self.assertEqual(data["relationships"]["app"]["data"]["id"], "app-1")

    def test_availability_payload_can_create_or_update_kaz_only(self):
        create_payload = MODULE.build_availability_payload("iap-1")
        create_data = create_payload["data"]
        self.assertNotIn("id", create_data)
        self.assertEqual(
            create_data["relationships"]["availableTerritories"]["data"],
            [{"type": "territories", "id": "KAZ"}],
        )

        update_payload = MODULE.build_availability_payload("iap-1", "availability-1")
        self.assertEqual(update_payload["data"]["id"], "availability-1")

    def test_price_schedule_uses_kaz_base_and_selected_price_point(self):
        payload = MODULE.build_price_schedule_payload("iap-1", "point-1000")
        relationships = payload["data"]["relationships"]
        self.assertEqual(relationships["baseTerritory"]["data"]["id"], "KAZ")
        included = payload["included"][0]
        self.assertIsNone(included["attributes"]["startDate"])
        self.assertEqual(
            included["relationships"]["inAppPurchasePricePoint"]["data"]["id"],
            "point-1000",
        )

    def test_localizations_are_listed_through_the_v2_purchase_relationship(self):
        source = inspect.getsource(MODULE.configure)
        self.assertIn(
            "/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations?limit=200",
            source,
        )


if __name__ == "__main__":
    unittest.main()
