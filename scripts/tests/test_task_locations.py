from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class TaskLocationContractTests(unittest.TestCase):
    def test_create_task_requires_country_and_city(self):
        view = (ROOT / "X5/Views/Hub/CreateTaskView.swift").read_text(encoding="utf-8")
        self.assertIn("CISLocations.countries", view)
        self.assertIn("CISLocations.search(country: countryCode, query: city)", view)
        self.assertIn("countryCode: countryCode", view)
        self.assertIn("city: city.trimmingCharacters", view)

    def test_task_model_and_request_include_location(self):
        service = (ROOT / "X5/Services/HubService.swift").read_text(encoding="utf-8")
        self.assertIn('case countryCode = "country_code"', service)
        self.assertIn('"country_code": countryCode', service)
        self.assertIn('"city": city', service)

    def test_task_detail_displays_city(self):
        detail = (ROOT / "X5/Views/Hub/TaskDetailView.swift").read_text(encoding="utf-8")
        self.assertIn('CISLocations.countryName(for:)', detail)
        self.assertIn('systemImage: "mappin.and.ellipse"', detail)

    def test_migration_keeps_legacy_tasks_valid(self):
        sql = (ROOT / "supabase/migrations/20260813090000_task_locations.sql").read_text(encoding="utf-8")
        self.assertIn("add column if not exists country_code text", sql)
        self.assertIn("country_code is null", sql)
        self.assertIn("city is null", sql)


if __name__ == "__main__":
    unittest.main()
