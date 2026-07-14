begin;

select set_config('x5.test_developer_course_id', gen_random_uuid()::text, true);
select set_config('x5.test_developer_submission_id', gen_random_uuid()::text, true);
select set_config('x5.test_developer_config_key', '__developer_access_' || gen_random_uuid()::text, true);

insert into public.courses (
  id,
  author_id,
  title,
  description,
  is_public
) values (
  current_setting('x5.test_developer_course_id')::uuid,
  '9ae99a45-91ac-486a-b7ec-e6614b7bc257'::uuid,
  'Developer access regression course',
  'Rolled back after the authorization check',
  true
);

insert into public.course_submissions (
  id,
  author_id,
  title,
  description,
  status
) values (
  current_setting('x5.test_developer_submission_id')::uuid,
  '00000000-0000-4000-8000-000000000077',
  'Developer access regression submission',
  'Rolled back after the authorization check',
  'pending'
);

insert into public.system_config (key, value)
values (
  current_setting('x5.test_developer_config_key'),
  '{"enabled":false}'::jsonb
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'f3eea23f-0aeb-405b-ab35-2c53173b7a8f',
    'email', 'changed-owner-email@example.com',
    'role', 'authenticated'
  )::text,
  true
);

do $owner_account$
declare
  v_rows integer;
begin
  if not public.is_x5_developer() or not public.x5_is_developer() then
    raise exception 'owner_account_lost_developer_access';
  end if;

  update public.courses
     set description = 'Updated by owner account'
   where id = current_setting('x5.test_developer_course_id')::uuid;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'owner_account_cannot_update_courses';
  end if;

  update public.system_config
     set value = '{"enabled":true}'::jsonb
   where key = current_setting('x5.test_developer_config_key');
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'owner_account_cannot_update_system_config';
  end if;
end;
$owner_account$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'eee55a08-18d1-46e3-a303-1411d1bb9333',
    'email', 'changed-adilkhan-email@example.com',
    'role', 'authenticated'
  )::text,
  true
);

do $adilkhan_account$
declare
  v_rows integer;
begin
  if not public.is_x5_developer() or not public.x5_is_developer() then
    raise exception 'adilkhan_account_lost_developer_access';
  end if;

  update public.courses
     set description = 'Updated by Adilkhan account'
   where id = current_setting('x5.test_developer_course_id')::uuid;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'adilkhan_account_cannot_update_courses';
  end if;

  update public.system_config
     set value = '{"enabled":false}'::jsonb
   where key = current_setting('x5.test_developer_config_key');
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'adilkhan_account_cannot_update_system_config';
  end if;
end;
$adilkhan_account$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9ae99a45-91ac-486a-b7ec-e6614b7bc257',
    'email', 'h-a-n-1@mail.ru',
    'role', 'authenticated'
  )::text,
  true
);

do $former_developer_account$
declare
  v_rows integer;
begin
  if public.is_x5_developer() or public.x5_is_developer() then
    raise exception 'former_developer_account_still_allowed';
  end if;

  update public.courses
     set description = 'Unauthorized update'
   where id = current_setting('x5.test_developer_course_id')::uuid;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'course_author_policy_bypassed_developer_lockdown';
  end if;

  update public.course_submissions
     set status = 'approved'
   where id = current_setting('x5.test_developer_submission_id')::uuid;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'former_developer_updated_submission';
  end if;

  update public.system_config
     set value = '{"enabled":true}'::jsonb
   where key = current_setting('x5.test_developer_config_key');
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'former_developer_updated_system_config';
  end if;
end;
$former_developer_account$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '0c9fc55f-81ef-4124-8f8c-a4f58bcf24f4',
    'email', 'tooyakov@icloud.com',
    'role', 'authenticated'
  )::text,
  true
);

do $former_email_account$
begin
  if public.is_x5_developer() or public.x5_is_developer() then
    raise exception 'legacy_email_still_grants_developer_access';
  end if;
end;
$former_email_account$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '496071cf-7c5b-43e8-886e-9f43c4618f90',
    'email', 'removed-user@example.com',
    'role', 'authenticated'
  )::text,
  true
);

do $former_uuid_account$
begin
  if public.is_x5_developer() or public.x5_is_developer() then
    raise exception 'legacy_uuid_still_grants_developer_access';
  end if;
end;
$former_uuid_account$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '00000000-0000-4000-8000-000000000099',
    'email', 'tooyakov.art@gmail.com',
    'role', 'authenticated'
  )::text,
  true
);

do $legacy_email_alias$
declare
  v_rows integer;
begin
  if public.is_x5_developer() or public.x5_is_developer() then
    raise exception 'legacy_email_alias_still_grants_developer_access';
  end if;

  if not exists (
    select 1
      from public.courses
     where id = current_setting('x5.test_developer_course_id')::uuid
       and is_public = true
  ) then
    raise exception 'non_developer_cannot_read_public_courses';
  end if;

  if exists (
    select 1
      from public.course_submissions
     where id = current_setting('x5.test_developer_submission_id')::uuid
  ) then
    raise exception 'non_developer_can_read_foreign_submission';
  end if;

  if exists (
    select 1
      from public.system_config
     where key = current_setting('x5.test_developer_config_key')
  ) then
    raise exception 'non_developer_can_read_private_system_config';
  end if;

  insert into public.course_submissions (
    author_id,
    title,
    description
  ) values (
    auth.uid()::text,
    'Legitimate owner submission',
    'A non-developer must still be able to submit a course for review'
  );
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'non_developer_cannot_submit_own_course';
  end if;
end;
$legacy_email_alias$;

reset role;

do $policy_and_acl_checks$
begin
  if exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'courses'
       and policyname = 'Authors can manage own courses'
  ) then
    raise exception 'course_author_write_bypass_policy_still_exists';
  end if;

  if exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'course_submissions'
       and policyname in (
         'Authenticated users can read submissions',
         'Authenticated users can update submissions',
         'Users can insert own submissions'
       )
  ) then
    raise exception 'broad_submission_policy_still_exists';
  end if;

  if exists (
    select 1
      from pg_policies
     where schemaname = 'public'
       and tablename = 'system_config'
       and policyname in (
         'Allow public insert system_config',
         'Allow public update system_config'
       )
  ) then
    raise exception 'public_system_config_write_policy_still_exists';
  end if;

  if exists (
    select 1
      from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'
       and policyname = 'course_media_insert_public'
  ) then
    raise exception 'anonymous_course_media_upload_policy_still_exists';
  end if;

  if not exists (
    select 1
      from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'
       and policyname = 'course_media_submission_insert'
       and with_check like '%submissions%'
       and with_check like '%auth.uid()%'
  ) then
    raise exception 'owned_course_submission_media_policy_missing';
  end if;

  if exists (
    select 1
      from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'
       and policyname in (
         'x5 storage authenticated write',
         'x5 storage authenticated update',
         'x5 storage authenticated delete own'
       )
       and concat_ws(' ', qual, with_check) like '%course-covers%'
  ) then
    raise exception 'generic_storage_policy_bypasses_course_cover_gate';
  end if;

  if has_table_privilege('anon', 'public.courses', 'truncate')
     or has_table_privilege('authenticated', 'public.courses', 'truncate')
     or has_table_privilege('anon', 'public.course_submissions', 'truncate')
     or has_table_privilege('authenticated', 'public.course_submissions', 'truncate')
     or has_table_privilege('anon', 'public.system_config', 'truncate')
     or has_table_privilege('authenticated', 'public.system_config', 'truncate') then
    raise exception 'client_role_still_has_truncate_privilege';
  end if;

  if has_table_privilege('anon', 'public.system_config', 'insert')
     or has_table_privilege('anon', 'public.system_config', 'update')
     or has_table_privilege('anon', 'public.system_config', 'delete') then
    raise exception 'anonymous_role_can_still_write_system_config';
  end if;
end;
$policy_and_acl_checks$;

rollback;

select 'developer_access_locked_to_two_accounts_with_rollback' as status;
