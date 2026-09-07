"""Guard decorative profile covers; native acceptance proves actual Store taps."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ProfileCoverHitTestingSourceTests(unittest.TestCase):
    def test_own_and_public_base_covers_do_not_intercept_controls(self):
        for relative, component in (
            ("X5/Views/ProfileView.swift", "ProfileCoverPhoto"),
            ("X5/Views/Hub/UserProfileView.swift", "CoverPhoto"),
        ):
            with self.subTest(profile=relative):
                source = (ROOT / relative).read_text(encoding="utf-8")
                cover = re.search(
                    rf"{component}\(urlString:.*?(?=\n\s*LinearGradient\()",
                    source,
                    re.S,
                )
                self.assertIsNotNone(cover)
                self.assertIn(".clipped()", cover.group())
                self.assertIn(".allowsHitTesting(false)", cover.group())


if __name__ == "__main__":
    unittest.main()
