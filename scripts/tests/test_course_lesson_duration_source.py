from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
COURSE_EDITOR = ROOT / "X5" / "Views" / "CourseEditorView.swift"


class CourseLessonDurationSourceTests(unittest.TestCase):
    def test_lesson_editor_hides_manual_duration_but_preserves_saved_value(self):
        source = COURSE_EDITOR.read_text(encoding="utf-8")
        sheet = source.split("private struct LessonEditorSheet: View", 1)[1]

        self.assertNotIn(
            'TextField("Длительность, например 12:30"',
            sheet,
        )
        self.assertIn("_duration = State(initialValue: lesson.duration)", sheet)
        self.assertIn("duration: duration.x5Trimmed", sheet)


if __name__ == "__main__":
    unittest.main()
