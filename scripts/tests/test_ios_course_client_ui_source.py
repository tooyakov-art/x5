from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class IOSCourseClientUISourceTests(unittest.TestCase):
    def test_native_video_picker_keeps_collection_navigation_inside_picker(self):
        picker = (
            ROOT / "X5" / "Views" / "Helpers" / "GalleryVideoPicker.swift"
        ).read_text(encoding="utf-8")
        editor = (ROOT / "X5" / "Views" / "CourseEditorView.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn("PHPickerViewController", picker)
        self.assertIn("PHPickerConfiguration(photoLibrary: .shared())", picker)
        self.assertIn("configuration.filter = .videos", picker)
        self.assertIn("didFinishPicking results", picker)
        self.assertIn("CourseVideoStaging.stage(", picker)
        self.assertIn("temporary URL for the lifetime", picker)
        self.assertIn("GalleryVideoPicker(", editor)
        self.assertNotIn("PhotosPicker(selection: $videoItem, matching: .videos)", editor)

    def test_courseup_header_and_every_real_course_have_developer_editor_action(self):
        courses = (ROOT / "X5" / "Views" / "CoursesView.swift").read_text(
            encoding="utf-8"
        )
        roles = (ROOT / "X5" / "Services" / "Roles.swift").read_text(
            encoding="utf-8"
        )

        self.assertIn('Text("CourseUP")', courses)
        self.assertNotIn('Text("Академия")', courses)
        self.assertIn("let isEditableCourse = service.courses.contains", courses)
        self.assertIn("if isDev && isEditableCourse", courses)
        self.assertIn("editorTarget = .edit(course)", courses)
        self.assertEqual(roles.count('"f3eea23f-0aeb-405b-ab35-2c53173b7a8f"'), 1)
        self.assertEqual(roles.count('"eee55a08-18d1-46e3-a303-1411d1bb9333"'), 1)


if __name__ == "__main__":
    unittest.main()
