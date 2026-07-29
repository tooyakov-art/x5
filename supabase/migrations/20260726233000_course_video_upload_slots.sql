-- Quarantined Bunny Stream upload-slot draft. Build 192 does not use it.
-- No API-facing role receives EXECUTE on these functions; a future server-only
-- broker must be designed before this ledger can authorize any upload.

create table if not exists public.course_video_upload_slots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  upload_key text not null
    check (upload_key ~ '^[A-Za-z0-9_-]{16,128}$'),
  purpose text not null
    check (purpose in ('course_submission', 'lesson_video')),
  resource_id text not null
    check (resource_id ~ '^[A-Za-z0-9._:-]{1,160}$'),
  request_fingerprint text not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  status text not null default 'creating'
    check (status in ('creating', 'ready')),
  lease_token uuid,
  lease_expires_at timestamptz,
  bunny_video_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (user_id, upload_key),
  check (
    (status = 'creating' and bunny_video_id is null) or
    (status = 'ready' and bunny_video_id is not null)
  )
);

create index if not exists course_video_upload_slots_rate_idx
  on public.course_video_upload_slots (user_id, created_at desc);

alter table public.course_video_upload_slots enable row level security;
revoke all on table public.course_video_upload_slots
  from public, anon, authenticated;

create or replace function public.claim_course_video_upload_slot(
  p_upload_key text,
  p_purpose text,
  p_resource_id text,
  p_request_fingerprint text,
  p_lease_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing public.course_video_upload_slots%rowtype;
  v_is_developer boolean := false;
  v_recent_count integer := 0;
  v_limit integer := 3;
begin
  if v_user_id is null then
    return jsonb_build_object('status', 'not_authenticated');
  end if;
  if p_purpose not in ('course_submission', 'lesson_video')
     or coalesce(p_upload_key, '') !~ '^[A-Za-z0-9_-]{16,128}$'
     or coalesce(p_resource_id, '') !~ '^[A-Za-z0-9._:-]{1,160}$'
     or coalesce(p_request_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or p_lease_token is null then
    return jsonb_build_object('status', 'invalid_request');
  end if;

  v_is_developer := public.is_x5_developer();
  if p_purpose = 'lesson_video' and not v_is_developer then
    return jsonb_build_object('status', 'not_authorized');
  end if;
  if v_is_developer then
    v_limit := 30;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_user_id::text,
      0
    )
  );

  select *
    into v_existing
    from public.course_video_upload_slots
   where user_id = v_user_id
     and upload_key = p_upload_key
   for update;

  if found then
    if v_existing.request_fingerprint <> p_request_fingerprint
       or v_existing.purpose <> p_purpose
       or v_existing.resource_id <> p_resource_id then
      return jsonb_build_object('status', 'idempotency_conflict');
    end if;
    if v_existing.status = 'ready' then
      return jsonb_build_object(
        'status', 'replay',
        'video_id', v_existing.bunny_video_id
      );
    end if;
    if v_existing.lease_expires_at > clock_timestamp() then
      return jsonb_build_object('status', 'in_progress');
    end if;

    update public.course_video_upload_slots
       set lease_token = p_lease_token,
           lease_expires_at = clock_timestamp() + interval '10 minutes',
           updated_at = clock_timestamp()
     where id = v_existing.id;
    return jsonb_build_object(
      'status', 'claimed',
      'lease_token', p_lease_token,
      'reclaimed', true
    );
  end if;

  select count(*)
    into v_recent_count
    from public.course_video_upload_slots
   where user_id = v_user_id
     and created_at >= clock_timestamp() - interval '10 minutes';

  if v_recent_count >= v_limit then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  insert into public.course_video_upload_slots (
    user_id,
    upload_key,
    purpose,
    resource_id,
    request_fingerprint,
    status,
    lease_token,
    lease_expires_at
  )
  values (
    v_user_id,
    p_upload_key,
    p_purpose,
    p_resource_id,
    p_request_fingerprint,
    'creating',
    p_lease_token,
    clock_timestamp() + interval '10 minutes'
  );

  return jsonb_build_object(
    'status', 'claimed',
    'lease_token', p_lease_token,
    'reclaimed', false
  );
end;
$$;

create or replace function public.complete_course_video_upload_slot(
  p_upload_key text,
  p_request_fingerprint text,
  p_lease_token uuid,
  p_video_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing public.course_video_upload_slots%rowtype;
begin
  if v_user_id is null then
    return jsonb_build_object('status', 'not_authenticated');
  end if;
  if p_video_id is null or p_lease_token is null then
    return jsonb_build_object('status', 'invalid_request');
  end if;

  select *
    into v_existing
    from public.course_video_upload_slots
   where user_id = v_user_id
     and upload_key = p_upload_key
   for update;

  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  if v_existing.request_fingerprint <> p_request_fingerprint then
    return jsonb_build_object('status', 'idempotency_conflict');
  end if;
  if v_existing.status = 'ready' then
    if v_existing.bunny_video_id = p_video_id then
      return jsonb_build_object(
        'status', 'already_completed',
        'video_id', v_existing.bunny_video_id
      );
    end if;
    return jsonb_build_object('status', 'idempotency_conflict');
  end if;
  if v_existing.lease_token <> p_lease_token
     or v_existing.lease_expires_at <= clock_timestamp() then
    return jsonb_build_object('status', 'stale_lease');
  end if;

  update public.course_video_upload_slots
     set status = 'ready',
         bunny_video_id = p_video_id,
         lease_token = null,
         lease_expires_at = null,
         updated_at = clock_timestamp()
   where id = v_existing.id;

  return jsonb_build_object(
    'status', 'completed',
    'video_id', p_video_id
  );
end;
$$;

revoke all on function public.claim_course_video_upload_slot(
  text, text, text, text, uuid
) from public;
revoke all on function public.complete_course_video_upload_slot(
  text, text, uuid, uuid
) from public;
revoke execute on function public.claim_course_video_upload_slot(
  text, text, text, text, uuid
) from anon, authenticated;
revoke execute on function public.complete_course_video_upload_slot(
  text, text, uuid, uuid
) from anon, authenticated;

-- Release quarantine: no API-facing role receives EXECUTE. These RPC sources
-- remain for a future server-only broker, but an authenticated JWT cannot use
-- them even if this migration is applied accidentally.
