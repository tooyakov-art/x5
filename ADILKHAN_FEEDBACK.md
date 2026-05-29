# Adilkhan Feedback

Source: WhatsApp review notes and screenshots from 2026-05-28 / 2026-05-29.

## Account / Access

- Make Adilkhan account a developer account.
  - Profile found in Supabase public `profiles`:
    - id: `cc0c5db9-a9e5-44a3-8386-8e97d44b465e`
    - name: `Adilkhan`
    - nickname: `adilkhan_marketing`
    - email: `h-a-n-1@mail.ru`
    - role: `specialist`
    - plan: `pro`
    - verified: `true`
  - Local developer UI gate added through `Roles.developerEmails`.

## Branding

- Replace old X5 logo everywhere.
- Use the provided `Xfive marketing` logo assets from:
  - `/Users/tooyakov/Downloads/IMG_3830.PNG`
  - `/Users/tooyakov/Downloads/IMG_3831.PNG`
- Login screen currently shows old `X5` image; replace it with the approved Xfive marketing icon.
- Check whether the app was uploaded to Google Play / App Store with the old logo and update store assets if needed.

## Account Deletion

- Delete account fails with:
  - `update or delete on table "profiles" violates foreign key constraint "generation_history_user_id_fkey" on table "generation_history"`
- Fix `delete_own_account` cleanup order so `generation_history` rows are deleted before `profiles`.
- Re-test delete account from Settings after the database fix.

## Hub

- Fix "Hub" label/heading issue in Hub filters.
- Category filters must change based on the selected specialist type/category.
- Wife/newly registered user appears in Hub to Adilkhan, but does not see herself in Hub.
  - Check `show_in_hub`, `is_public`, `user_role`, country filtering, local current-user filtering, and cache.
- If user registered as non-specialist or as company, they still need a clear way to create/add a specialist profile later.
- "Add portfolio" should not be the only way to create specialist presence.

## Specialist Profile

- Public specialist profile should be styled like the user's own profile.
- Specialist detail screen currently looks wrong in screenshots.
- Do not show the current stats/social/specialist blocks in the crossed-out layout.
- The viewed specialist profile should have the same polished hero/profile layout as `ProfileView`.
- Hub list card for a specialist should be clearer and better styled.

## Portfolio

- Portfolio add flow feels like it "just adds a photo".
- Portfolio must support full management:
  - edit;
  - add;
  - delete;
  - upload;
  - update title/description/case text;
  - manage photo/video content.
- Portfolio form UX needs clearer fields and actions, not only media picker.

## Courses / CourseUP

- Course screens need visual/content update.
- Course detail screenshots show old/incorrect lesson cards and cover layout.
- Course editor/developer mode should allow Adilkhan to edit, add, delete and upload course content.
- Lesson list/play buttons need review.

## Follow-Up

- Prioritize:
  1. Account deletion FK fix.
  2. Adilkhan developer access verification on-device.
  3. Logo replacement.
  4. Hub visibility/current-user bug.
  5. Specialist profile redesign.
  6. Portfolio management flow.
  7. CourseUP editor/content polish.
