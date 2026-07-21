from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
COURSE_EDITOR = ROOT / "X5" / "Views" / "CourseEditorView.swift"
COURSES_VIEW = ROOT / "X5" / "Views" / "CoursesView.swift"


class CourseVideoGalleryPickerSourceTests(unittest.TestCase):
    def test_lesson_video_picker_opens_photo_library_instead_of_files(self):
        source = COURSE_EDITOR.read_text(encoding="utf-8")

        self.assertIn("@State private var videoItem: PhotosPickerItem?", source)
        self.assertIn(
            "PhotosPicker(selection: $videoItem, matching: .videos)", source
        )
        self.assertIn('return "Выбрать видео из галереи"', source)
        self.assertNotIn(".fileImporter(", source)

    def test_submission_video_picker_opens_photo_library_instead_of_files(self):
        source = COURSES_VIEW.read_text(encoding="utf-8")

        self.assertIn("import PhotosUI", source)
        self.assertIn("@State private var videoItem: PhotosPickerItem?", source)
        self.assertIn(
            "PhotosPicker(selection: $videoItem, matching: .videos)", source
        )
        self.assertIn('"Выбрать видео из галереи"', source)
        self.assertNotIn(".fileImporter(", source)


if __name__ == "__main__":
    unittest.main()
