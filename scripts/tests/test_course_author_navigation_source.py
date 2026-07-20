from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
COURSES_VIEW = ROOT / "X5" / "Views" / "CoursesView.swift"


class CourseAuthorNavigationSourceTests(unittest.TestCase):
    def test_course_detail_author_opens_public_profile_by_author_id(self):
        source = COURSES_VIEW.read_text(encoding="utf-8")
        detail_source = source.split("struct CourseDetailView: View", 1)[1]
        detail_source = detail_source.split("private struct StatBubble", 1)[0]

        self.assertIn("let authorId: String?", source)
        self.assertIn("NavigationLink", source)
        self.assertIn("UserProfileView(userId: authorId, fallback: nil)", source)
        self.assertIn(
            "CourseAuthorLine(authorName: course.authorName, authorId: course.authorId)",
            detail_source,
        )
        self.assertNotIn(
            "CourseAuthorLine(authorName: course.authorName, authorId: course.authorId)",
            source.split("struct CourseDetailView: View", 1)[0],
        )


if __name__ == "__main__":
    unittest.main()
