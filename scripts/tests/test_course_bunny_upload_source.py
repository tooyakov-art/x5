import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "supabase" / "functions" / "create-course-video-upload"
HANDLER = BACKEND / "handler.mjs"
INDEX = BACKEND / "index.ts"
DOCS = BACKEND / "DEPLOYMENT.md"
UPLOADER = ROOT / "X5" / "Services" / "BunnyStreamResumableVideoUploader.swift"
COURSES = ROOT / "X5" / "Services" / "CoursesService.swift"
XCODE_TESTS = ROOT / "X5Tests" / "BunnyStreamResumableVideoUploaderTests.swift"
PROJECT = ROOT / "project.yml"
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260726233000_course_video_upload_slots.sql"
)
WORKFLOW = ROOT / ".github" / "workflows" / "ios-course-ci.yml"
SOURCES = ROOT / "THIRD_PARTY_SOURCES.md"
RELEASE_METADATA = (
    ROOT / "fastlane" / "metadata" / "en-US" / "release_notes.txt",
    ROOT / "fastlane" / "metadata" / "ru" / "release_notes.txt",
    ROOT / "docs" / "release-notes" / "1.1.6-build-195" / "kk.txt",
    ROOT / "fastlane" / "metadata" / "review_information" / "notes.txt",
)


class CourseBunnyUploadSourceTests(unittest.TestCase):
    def test_backend_has_a_hard_false_release_gate_before_sensitive_work(self):
        handler = HANDLER.read_text(encoding="utf-8")
        index = INDEX.read_text(encoding="utf-8")

        self.assertIn(
            "const BUNNY_COURSE_VIDEO_UPLOAD_RELEASE_ENABLED = false;",
            index,
        )
        self.assertIn(
            "releaseEnabled: BUNNY_COURSE_VIDEO_UPLOAD_RELEASE_ENABLED",
            index,
        )
        self.assertNotIn(
            'Deno.env.get("BUNNY_COURSE_VIDEO_UPLOAD_RELEASE_ENABLED")',
            index,
        )
        gate = handler.index("dependencies?.releaseEnabled !== true")
        authentication = handler.index(
            'request.headers.get("Authorization")'
        )
        claim = handler.index("dependencies.claimUpload(")
        signature = handler.index("const signature = await sha256Hex(")
        self.assertLess(gate, authentication)
        self.assertLess(gate, claim)
        self.assertLess(gate, signature)

        self.assertIn('Deno.env.get("BUNNY_STREAM_LIBRARY_ID")', index)
        self.assertIn('Deno.env.get("BUNNY_STREAM_API_KEY")', index)
        self.assertNotIn("BUNNY_STREAM_API_KEY", COURSES.read_text("utf-8"))
        self.assertNotIn("BUNNY_STREAM_API_KEY", UPLOADER.read_text("utf-8"))

    def test_ios_release_excludes_bunny_and_keeps_existing_supabase_path(self):
        self.assertTrue(
            UPLOADER.exists(),
            "Quarantined Bunny source should remain available for future work",
        )
        uploader = UPLOADER.read_text(encoding="utf-8")
        courses = COURSES.read_text(encoding="utf-8")
        xcode_tests = XCODE_TESTS.read_text(encoding="utf-8")
        project = PROJECT.read_text(encoding="utf-8")
        gate = "X5_ENABLE_BUNNY_COURSE_VIDEO_UPLOAD"

        self.assertNotIn(gate, project)
        self.assertIn(f"#if {gate}", uploader)
        self.assertTrue(uploader.rstrip().endswith("#endif"))
        self.assertGreaterEqual(courses.count(f"#if {gate}"), 4)
        self.assertIn(f"#if {gate}", xcode_tests)
        self.assertTrue(xcode_tests.rstrip().endswith("#endif"))
        self.assert_gate_scoped(
            courses,
            gate,
            (
                "bunnyStreamVideoUploader",
                "CourseLessonVideoUploadRoute",
                "BunnyStreamVideoUploadError",
                "bunnyLessonResourceID",
            ),
        )
        self.assertIn("import TUSKit", uploader)
        self.assertIn("CourseLessonVideoUploadRoute.shouldUseBunny", courses)
        self.assertGreaterEqual(
            courses.count("bunnyStreamVideoUploader.upload("),
            2,
        )
        self.assertGreaterEqual(courses.count("sourceFileURL: fileURL"), 2)
        self.assertIn("purpose: .courseSubmission", courses)
        self.assertIn("purpose: .lessonVideo", courses)
        self.assertGreaterEqual(
            courses.count("resumableVideoUploader.upload("),
            2,
        )
        self.assertGreaterEqual(courses.count("videoUploadPreparer.prepare("), 2)
        self.assertIn("CourseVideoUploadPolicy.directUploadLimitBytes", uploader)
        self.assertIn("persistGeneratedHeaders: false", uploader)

    def test_rpc_and_docs_stay_quarantined_but_sources_remain_in_ci(self):
        self.assertTrue(DOCS.exists(), "Bunny quarantine guide must exist")
        workflow = WORKFLOW.read_text(encoding="utf-8")
        docs = DOCS.read_text(encoding="utf-8")
        sources = SOURCES.read_text(encoding="utf-8")
        migration = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("supabase/functions/create-course-video-upload/**", workflow)
        self.assertIn(
            "supabase/functions/create-course-video-upload/index.ts",
            workflow,
        )
        self.assertIn(
            "supabase/functions/create-course-video-upload/*.test.mjs",
            workflow,
        )
        self.assertIn("Release quarantine", docs)
        self.assertIn("must not be deployed or enabled", docs)
        self.assertIn("not configured", docs)
        self.assertIn("BUNNY_STREAM_API_KEY", docs)
        self.assertIn("quarantined", sources.lower())
        self.assertIn("https://docs.bunny.net/stream/tus-resumable-uploads", sources)
        self.assertIn("TUSKit", sources)
        self.assertNotIn(") to authenticated;", migration.lower())
        self.assertIn("from anon, authenticated;", migration.lower())

    def test_release_metadata_does_not_claim_quarantined_uploads(self):
        metadata = "\n".join(
            path.read_text(encoding="utf-8") for path in RELEASE_METADATA
        )

        for false_claim in (
            "Large course and submission videos",
            "Large lesson/submission videos",
            "Большие видео уроков и заявок",
            "үлкен видеолары",
            "1 GiB",
            "47,000,000",
            "Bunny",
        ):
            self.assertNotIn(false_claim, metadata)

    def assert_gate_scoped(self, source, gate, tokens):
        depth = 0
        for line_number, line in enumerate(source.splitlines(), start=1):
            stripped = line.strip()
            if stripped == f"#if {gate}":
                depth += 1
                continue
            if stripped == "#endif" and depth:
                depth -= 1
                continue
            if any(token in line for token in tokens):
                self.assertGreater(
                    depth,
                    0,
                    f"Bunny reference is outside compile gate at line "
                    f"{line_number}: {line.strip()}",
                )
        self.assertEqual(depth, 0, "unbalanced Bunny compile gate")


if __name__ == "__main__":
    unittest.main()
