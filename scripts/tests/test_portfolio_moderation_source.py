from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
EDGE_FUNCTION = ROOT / "supabase" / "functions" / "moderate-portfolio" / "index.ts"
MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260724123000_portfolio_automatic_moderation_queue.sql"
)
CAS_HARDENING_MIGRATION = (
    ROOT
    / "supabase"
    / "migrations"
    / "20260724134000_harden_portfolio_moderation_cas.sql"
)
PORTFOLIO_SERVICE = ROOT / "X5" / "Services" / "PortfolioService.swift"
PORTFOLIO_VIEW = ROOT / "X5" / "Views" / "PortfolioView.swift"
MODERATION_VIEW = ROOT / "X5" / "Views" / "PortfolioModerationQueueView.swift"
MODERATION_SERVICE = (
    ROOT / "X5" / "Services" / "PortfolioModerationQueueService.swift"
)
SETTINGS_VIEW = ROOT / "X5" / "Views" / "SettingsView.swift"


class PortfolioModerationSourceTests(unittest.TestCase):
    def test_edge_function_uses_server_developer_gate_for_manual_actions(self):
        source = EDGE_FUNCTION.read_text(encoding="utf-8")

        self.assertIn('"approve" | "reject" | "retry"', source)
        self.assertIn('.rpc("is_x5_developer")', source)
        self.assertIn('if (requiresDeveloper && !isDeveloper)', source)
        self.assertIn('return json({ error: "forbidden" }, 403)', source)
        self.assertNotIn("f3eea23f-0aeb-405b-ab35-2c53173b7a8f", source)
        self.assertNotIn("eee55a08-18d1-46e3-a303-1411d1bb9333", source)

    def test_edge_function_auto_approves_safe_content_and_queues_failures(self):
        source = EDGE_FUNCTION.read_text(encoding="utf-8")

        self.assertIn('status: "approved"', source)
        self.assertIn('status: "rejected"', source)
        self.assertIn('status: "manual_review"', source)
        self.assertIn('reason: "video_requires_developer_review"', source)
        self.assertIn('reason: "moderation_response_invalid"', source)

    def test_video_is_never_auto_approved_from_a_client_thumbnail(self):
        source = EDGE_FUNCTION.read_text(encoding="utf-8")
        video_guard = source.index('if (item.type === "video")')
        provider_call = source.index("fetch(OPENAI_MODERATION_URL")

        self.assertLess(video_guard, provider_call)
        self.assertIn(
            'result: { reason: "video_requires_developer_review" }', source
        )

    def test_edge_function_uses_revision_compare_and_swap(self):
        source = EDGE_FUNCTION.read_text(encoding="utf-8")
        queue_service = MODERATION_SERVICE.read_text(encoding="utf-8")
        hardening = CAS_HARDENING_MIGRATION.read_text(encoding="utf-8")

        self.assertIn("moderation_revision?: number;", source)
        self.assertIn("moderation_revision: number;", source)
        self.assertIn(
            "requestedRevision !== item.moderation_revision", source
        )
        self.assertIn("if (requestedRevision == null)", source)
        self.assertIn('.eq("moderation_revision", item.moderation_revision)', source)
        self.assertIn('.eq("moderation_status", item.moderation_status)', source)
        self.assertIn('item.moderation_status !== "pending"', source)
        self.assertIn('error: "stale_item"', source)
        self.assertIn("}, 409)", source)
        self.assertIn(
            "new.moderation_revision := old.moderation_revision + 1", hardening
        )
        self.assertIn('case moderationRevision = "moderation_revision"', queue_service)
        self.assertIn("moderationRevision: Int64?", queue_service)

    def test_rejected_media_is_removed_from_public_portfolio_storage(self):
        source = EDGE_FUNCTION.read_text(encoding="utf-8")

        self.assertIn('decision.status === "rejected"', source)
        self.assertIn('.storage.from("portfolio")', source)
        self.assertIn(".remove(objectPaths)", source)
        self.assertIn("item.media_url", source)
        self.assertIn("item.thumbnail_url", source)
        self.assertIn("portfolioObjectPath(value, item.user_id)", source)
        self.assertIn("segments[0] !== expectedOwnerId", source)
        self.assertIn("resolvedPaths.some((value) => value == null)", source)
        self.assertIn("parsed.username || parsed.password", source)
        self.assertIn("parsed.search || parsed.hash", source)
        self.assertIn('!parsed.pathname.startsWith(marker)', source)
        self.assertIn('segment === "." || segment === ".."', source)

    def test_unapproved_queue_never_loads_untrusted_media_urls(self):
        edge = EDGE_FUNCTION.read_text(encoding="utf-8")
        queue = MODERATION_VIEW.read_text(encoding="utf-8")

        self.assertIn("hasInvalidPortfolioMediaURL(item)", edge)
        self.assertIn("trustedPortfolioImageURL(item)", queue)
        self.assertIn("trustedPortfolioMediaURL(item.mediaUrl, ownerId: item.userId)", queue)
        self.assertIn("components.query == nil", queue)
        self.assertIn("components.fragment == nil", queue)
        self.assertIn('"/storage/v1/object/public/portfolio/"', queue)

    def test_new_moderation_sources_do_not_contain_mojibake(self):
        sources = [
            EDGE_FUNCTION,
            MODERATION_VIEW,
            MODERATION_SERVICE,
        ]
        signatures = ("РќР", "РћР", "РџС", "Р”Р", "Р‘Р", "вЂ")

        for path in sources:
            source = path.read_text(encoding="utf-8")
            for signature in signatures:
                self.assertNotIn(signature, source, f"{path.name}: {signature}")

    def test_video_thumbnail_is_uploaded_before_moderation(self):
        service = PORTFOLIO_SERVICE.read_text(encoding="utf-8")
        view = PORTFOLIO_VIEW.read_text(encoding="utf-8")

        self.assertIn("thumbnailData: Data?", service)
        self.assertIn("thumbnailURL = await uploadPortfolioMedia", service)
        self.assertLess(
            service.index("thumbnailURL = await uploadPortfolioMedia"),
            service.index("let moderated = await moderate"),
        )
        self.assertIn("import AVFoundation", view)
        self.assertIn("@State private var videoThumbnailData: Data?", view)
        self.assertIn("makeVideoThumbnail", view)
        self.assertIn("let thumbnail = await makeVideoThumbnail", view)
        self.assertIn("videoThumbnailData = thumbnail", view)
        self.assertIn("thumbnailData: thumbnailData", view)
        self.assertIn("videoThumbnailData,", view)
        self.assertIn("@State private var preparingMedia = false", view)
        self.assertIn(".disabled(saving || preparingMedia || mediaData == nil)", view)
        self.assertIn("let thumbnailFractions:", view)
        self.assertGreaterEqual(view.count("generator.copyCGImage"), 1)

    def test_approved_storage_objects_are_immutable_and_moderation_is_revision_bound(self):
        service = PORTFOLIO_SERVICE.read_text(encoding="utf-8")
        edge = EDGE_FUNCTION.read_text(encoding="utf-8")
        migration = MIGRATION.read_text(encoding="utf-8")

        self.assertNotIn('upload.setValue("true", forHTTPHeaderField: "x-upsert")', service)
        self.assertIn('upload.setValue("false", forHTTPHeaderField: "x-upsert")', service)
        self.assertIn("moderation_revision bigint not null default 1", migration)
        self.assertIn("new.moderation_revision := old.moderation_revision + 1", migration)
        self.assertIn("moderation_revision: number", edge)
        self.assertIn(".eq(\"moderation_revision\", item.moderation_revision)", edge)
        self.assertIn('return json({ error: "stale_item" }, 409)', edge)

    def test_developer_queue_is_reachable_only_for_local_developer_ids(self):
        settings = SETTINGS_VIEW.read_text(encoding="utf-8")
        queue = MODERATION_VIEW.read_text(encoding="utf-8")

        self.assertIn(
            "Roles.isDeveloper(email: auth.userEmail, userId: auth.userId)", settings
        )
        self.assertIn("PortfolioModerationQueueView()", settings)
        self.assertIn('run("approve"', queue)
        self.assertIn('run("reject"', queue)
        self.assertIn('run("retry"', queue)

    def test_developer_can_read_description_and_play_original_video(self):
        queue = MODERATION_VIEW.read_text(encoding="utf-8")

        self.assertIn("item.description", queue)
        self.assertIn("PortfolioModerationPreviewView", queue)
        self.assertIn("VideoPlayer(player:", queue)
        self.assertIn("item.mediaUrl", queue)

    def test_database_exposes_queue_to_developers_and_storage_updates_to_owner(self):
        source = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("public.is_x5_developer()", source)
        self.assertIn(
            "moderation_status in ('pending', 'manual_review', 'failed')", source
        )
        self.assertIn("moderation_revision bigint not null default 1", source)
        self.assertIn("old.moderation_revision + 1", source)
        self.assertIn("owner_id = (select auth.uid())::text", source)
        self.assertIn("storage.foldername(name)", source)
        self.assertIn(
            'drop policy if exists "portfolio_auth_insert" on storage.objects',
            source,
        )
        self.assertIn(
            'drop policy if exists "portfolio_auth_update" on storage.objects',
            source,
        )
        self.assertIn(
            'drop policy if exists "portfolio_auth_delete" on storage.objects',
            source,
        )

        update_policy = source.split(
            'create policy "x5 storage authenticated update"', 1
        )[1].split(";", 1)[0]
        delete_policy = source.split(
            'create policy "x5 storage authenticated delete own"', 1
        )[1].split(";", 1)[0]
        self.assertNotIn("'portfolio'", update_policy)
        self.assertNotIn("'portfolio'", delete_policy)

    def test_portfolio_uploads_are_immutable_and_media_prep_is_race_safe(self):
        service = PORTFOLIO_SERVICE.read_text(encoding="utf-8")
        view = PORTFOLIO_VIEW.read_text(encoding="utf-8")

        self.assertIn('upload.setValue("false", forHTTPHeaderField: "x-upsert")', service)
        self.assertIn("@State private var preparingMedia", view)
        self.assertIn("@State private var mediaPreparationGeneration", view)
        self.assertIn(
            ".disabled(saving || preparingMedia || mediaData == nil)", view
        )
        self.assertIn(
            "guard generation == mediaPreparationGeneration else { return }", view
        )

        load_media = view.split("private func loadMedia", 1)[1]
        self.assertLess(
            load_media.index("let thumbnail = await makeVideoThumbnail"),
            load_media.index("mediaData = data"),
        )
        source = MIGRATION.read_text(encoding="utf-8")
        self.assertIn(
            'drop policy if exists "x5 storage authenticated write"', source
        )
        self.assertIn(
            "bucket_id = any (array['chat-media', 'avatars'])", source
        )
        self.assertIn("owner_id = (select auth.uid())::text", source)


if __name__ == "__main__":
    unittest.main()
