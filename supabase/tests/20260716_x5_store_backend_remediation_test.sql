begin;

do $acl$
begin
  if has_function_privilege(
    'authenticated',
    'public.apply_verified_app_store_subscription_lifecycle(uuid,text,timestamptz,uuid,text,text,text,text,uuid,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,integer)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.apply_verified_app_store_subscription_lifecycle(uuid,text,timestamptz,uuid,text,text,text,text,uuid,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,integer)',
    'execute'
  ) then
    raise exception 'lifecycle_rpc_is_client_callable';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.apply_verified_app_store_subscription_lifecycle(uuid,text,timestamptz,uuid,text,text,text,text,uuid,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,integer)',
    'execute'
  ) then
    raise exception 'lifecycle_rpc_is_not_service_callable';
  end if;
  if has_table_privilege(
    'service_role', 'public.app_store_verified_lifecycle_events', 'insert'
  ) or has_table_privilege(
    'authenticated', 'public.app_store_verified_lifecycle_events', 'select'
  ) then
    raise exception 'lifecycle_ledger_is_directly_accessible';
  end if;
end;
$acl$;

select set_config(
  'x5.remediation_user_1',
  (select id::text from public.profiles order by id limit 1),
  true
);
select set_config(
  'x5.remediation_user_2',
  (
    select profile.id::text
      from public.profiles as profile
     where profile.id <>
           current_setting('x5.remediation_user_1')::uuid
       and not exists (
         select 1 from public.app_store_transactions as apple
          where apple.user_id = profile.id
            and apple.product_id in (
              'com.x5studio.app.lite.monthly',
              'com.x5studio.app.pro.monthly',
              'com.x5studio.app.max.monthly'
            )
            and apple.expires_date > now()
       )
       and not exists (
         select 1 from public.iap_entitlements as entitlement
          where entitlement.user_id = profile.id
            and entitlement.product_id in (
              'com.x5studio.app.lite.monthly',
              'com.x5studio.app.pro.monthly',
              'com.x5studio.app.max.monthly',
              'x5_lite_monthly_v2', 'x5_pro_monthly_v2',
              'x5_max_monthly_v2', 'x5_pro_monthly', 'x5_pro_yearly'
            )
            and entitlement.subscription_end_date > now()
       )
     order by profile.id
     limit 1
  ),
  true
);
select set_config(
  'x5.remediation_user_3',
  (
    select profile.id::text
      from public.profiles as profile
     where profile.id not in (
       current_setting('x5.remediation_user_1')::uuid,
       current_setting('x5.remediation_user_2')::uuid
     )
       and not exists (
         select 1
           from public.app_store_sandbox_review_accounts as allowed
          where allowed.user_id = profile.id
            and allowed.enabled
       )
       and not exists (
         select 1 from public.app_store_transactions as apple
          where apple.user_id = profile.id
            and apple.product_id = 'com.x5studio.app.verified.monthly'
            and apple.expires_date > now()
       )
       and not exists (
         select 1 from public.app_store_sandbox_review_transactions as sandbox
          where sandbox.user_id = profile.id
            and sandbox.product_id = 'com.x5studio.app.verified.monthly'
            and sandbox.expires_date > now()
       )
       and not exists (
         select 1 from public.iap_entitlements as entitlement
          where entitlement.user_id = profile.id
            and entitlement.product_id in (
              'com.x5studio.app.verified.monthly',
              'x5_verified_monthly_v2', 'x5_verified_monthly'
            )
            and entitlement.subscription_end_date > now()
       )
     order by profile.id
     limit 1
  ),
  true
);

do $fixtures$
begin
  if nullif(current_setting('x5.remediation_user_1', true), '') is null
     or nullif(current_setting('x5.remediation_user_2', true), '') is null
     or nullif(current_setting('x5.remediation_user_3', true), '') is null then
    raise exception 'three_profile_fixtures_required';
  end if;
end;
$fixtures$;

do $existing_owner_legacy_binding$
declare
  v_uid constant uuid :=
    'f3eea23f-0aeb-405b-ab35-2c53173b7a8f'::uuid;
  v_chain constant text := '2000001163575812';
  v_expected_end constant timestamptz :=
    '2026-07-30 10:44:39.862088+00'::timestamptz;
  v_before_credits integer;
begin
  if exists (
    select 1 from public.iap_entitlements
     where original_transaction_id = v_chain
  ) then
    if not exists (
      select 1
        from public.iap_entitlements as legacy
        join public.app_store_legacy_bindings as binding
          on binding.original_transaction_id = legacy.original_transaction_id
         and binding.user_id = legacy.user_id
         and binding.product_id = legacy.product_id
         and binding.legacy_credited_at is not distinct from
             legacy.credited_at
         and binding.legacy_subscription_end_date is not distinct from
             legacy.subscription_end_date
         and binding.legacy_created_at is not distinct from legacy.created_at
         and binding.app_account_token = coalesce(
           legacy.legacy_app_account_token,
           legacy.app_account_token,
           legacy.user_id
         )
       where legacy.original_transaction_id = v_chain
         and legacy.user_id = v_uid
         and legacy.subscription_end_date = v_expected_end
    ) then
      raise exception 'existing_owner_chain_not_exactly_bound';
    end if;

    select credits into v_before_credits
      from public.profiles where id = v_uid;
    perform public.x5_reconcile_paid_plan_profile(v_uid);
    if (select plan from public.profiles where id = v_uid) <> 'pro'
       or (select subscription_end_date from public.profiles where id = v_uid)
          is distinct from v_expected_end then
      raise exception 'existing_owner_plan_was_not_advanced';
    end if;
    if (select credits from public.profiles where id = v_uid)
       is distinct from v_before_credits then
      raise exception 'existing_owner_reconciliation_changed_credits';
    end if;
  end if;
end;
$existing_owner_legacy_binding$;

do $credit_neutral_reconciliation$
declare
  v_uid uuid := current_setting('x5.remediation_user_3')::uuid;
  v_credits integer;
  v_permanent integer;
  v_debt integer;
  v_expiry timestamptz := now() + interval '9 days';
  v_retention integer;
begin
  update public.profiles
     set credits = 123,
         is_verified = true,
         verified_until = now() - interval '1 day'
   where id = v_uid;
  update public.profiles
     set credits_expires_at = v_expiry
   where id = v_uid;
  select credits, permanent_credits, permanent_credit_debt,
         credits_retention_months
    into v_credits, v_permanent, v_debt, v_retention
    from public.profiles where id = v_uid;

  perform public.x5_reconcile_store_profiles(10000);
  if (select is_verified from public.profiles where id = v_uid)
     or (select credits from public.profiles where id = v_uid) <> v_credits
     or (select permanent_credits from public.profiles where id = v_uid)
        <> v_permanent
     or (select permanent_credit_debt from public.profiles where id = v_uid)
        <> v_debt
     or (select credits_expires_at from public.profiles where id = v_uid)
        is distinct from v_expiry
     or (select credits_retention_months from public.profiles where id = v_uid)
        <> v_retention then
    raise exception 'reconciliation_changed_credit_metadata';
  end if;
end;
$credit_neutral_reconciliation$;

set local role service_role;

do $permanent_credit_packs$
declare
  v_uid uuid := current_setting('x5.remediation_user_1')::uuid;
  v_before public.profiles%rowtype;
  v_after public.profiles%rowtype;
  v_response jsonb;
  v_purchase timestamptz := now() - interval '1 minute';
begin
  select * into v_before from public.profiles where id = v_uid;
  update public.profiles
     set credits = 0,
         permanent_credits = 0,
         permanent_credit_debt = 0,
         credits_expires_at = null
   where id = v_uid;

  v_response := public.apply_verified_app_store_consumable(
    v_uid, 'codex-remediation-apple-pack',
    'codex-remediation-apple-pack',
    'com.x5studio.app.credits.1000', 'Production', v_uid,
    v_purchase, now(), null, 1
  );
  select * into v_after from public.profiles where id = v_uid;
  if v_response ->> 'status' <> 'applied'
     or v_after.credits <> 1000
     or v_after.permanent_credits <> 1000
     or v_after.credits_expires_at is not null then
    raise exception 'apple_pack_not_permanent:%', v_response;
  end if;
  if v_after.plan is distinct from v_before.plan
     or v_after.subscription_type is distinct from v_before.subscription_type
     or v_after.subscription_end_date is distinct from
        v_before.subscription_end_date
     or v_after.purchased_course_ids is distinct from
        v_before.purchased_course_ids then
    raise exception 'apple_pack_changed_entitlements';
  end if;

  update public.profiles set credits = credits - 200 where id = v_uid;
  if (select credits_expires_at from public.profiles where id = v_uid)
     is not null then
    raise exception 'spending_started_timer_for_permanent_pack';
  end if;
  if (select permanent_credits from public.profiles where id = v_uid) <> 800 then
    raise exception 'permanent_spend_did_not_reduce_floor';
  end if;

  v_response := public.apply_verified_app_store_consumable_refund(
    v_uid, 'codex-remediation-apple-pack',
    'codex-remediation-apple-pack',
    'com.x5studio.app.credits.1000', 'Production', v_uid,
    v_purchase, now(), now(), 1
  );
  select * into v_after from public.profiles where id = v_uid;
  if v_after.credits <> -200
     or v_after.permanent_credits <> 0
     or v_after.permanent_credit_debt <> 200 then
    raise exception 'permanent_refund_after_spend_left_a_floor:%', v_response;
  end if;

  perform pg_catalog.set_config(
    'x5.permanent_credit_adjustment_user', v_uid::text, true
  );
  update public.profiles
     set credits = 0,
         permanent_credits = 0,
         permanent_credit_debt = 0,
         credits_expires_at = null
   where id = v_uid;
  perform pg_catalog.set_config(
    'x5.permanent_credit_adjustment_user', '', true
  );

  v_response := public.apply_android_purchase_entitlement(
    v_uid, 'codex-remediation-android-pack', 'x5_credits_1000_v2',
    'inapp', 'codex-remediation-android-token',
    'codex-remediation-order', null, 1000, null, null, false
  );
  select * into v_after from public.profiles where id = v_uid;
  if (v_response ->> 'already_claimed')::boolean
     or (v_response ->> 'credits_granted')::integer <> 1000
     or v_after.credits <> 1000
     or v_after.permanent_credits <> 1000
     or v_after.credits_expires_at is not null then
    raise exception 'android_pack_not_permanent:%', v_response;
  end if;
  if v_after.plan is distinct from v_before.plan
     or v_after.subscription_type is distinct from v_before.subscription_type
     or v_after.subscription_end_date is distinct from
        v_before.subscription_end_date
     or v_after.purchased_course_ids is distinct from
        v_before.purchased_course_ids then
    raise exception 'android_pack_changed_entitlements';
  end if;

  -- A monthly credit grant is intentionally still expiring and independent
  -- from the permanent one-time pack path.
  v_response := public.apply_android_purchase_entitlement(
    v_uid, 'codex-remediation-android-monthly', 'x5_lite_monthly_v2',
    'subscription', 'codex-remediation-android-monthly-token',
    'codex-remediation-monthly-order', now() + interval '1 month',
    1000, 'lite_monthly', 'pro', false
  );
  select * into v_after from public.profiles where id = v_uid;
  if v_after.credits_expires_at is null
     or v_after.subscription_end_date is null
     or v_after.credits <> 2000
     or v_after.permanent_credits <> 1000 then
    raise exception 'monthly_credit_expiry_was_removed:%', v_response;
  end if;

  update public.profiles set credits = credits - 500 where id = v_uid;
  select * into v_after from public.profiles where id = v_uid;
  if v_after.credits <> 1500 or v_after.permanent_credits <> 1000 then
    raise exception 'mixed_permanent_floor_was_not_preserved';
  end if;
  update public.profiles
     set credits_expires_at = now() - interval '1 minute'
   where id = v_uid;
end;
$permanent_credit_packs$;

reset role;

do $permanent_credit_expiry$
declare
  v_uid uuid := current_setting('x5.remediation_user_1')::uuid;
begin
  perform public.x5_expire_old_credits();
  if (select credits from public.profiles where id = v_uid) <> 1000
     or (select permanent_credits from public.profiles where id = v_uid) <> 1000
     or (select credits_expires_at from public.profiles where id = v_uid)
        is not null then
    raise exception 'mixed_subscription_expiry_erased_permanent_floor';
  end if;

  update public.profiles
     set is_verified = true,
         verified_until = now() + interval '1 month'
   where id = v_uid;
  if (select credits_expires_at from public.profiles where id = v_uid)
     is not null
     or (select permanent_credits from public.profiles where id = v_uid)
        <> 1000 then
    raise exception 'badge_change_expired_permanent_only_balance';
  end if;
end;
$permanent_credit_expiry$;

set local role service_role;

do $sandbox_scope$
declare
  developer_id uuid;
  outsider_id uuid;
  v_rejected boolean := false;
  v_index integer := 0;
begin
  for developer_id in
    select id from public.profiles
     where id in (
       'f3eea23f-0aeb-405b-ab35-2c53173b7a8f'::uuid,
       'eee55a08-18d1-46e3-a303-1411d1bb9333'::uuid
     )
     order by id
  loop
    v_index := v_index + 1;
    perform public.apply_verified_app_store_sandbox_review_transaction(
      developer_id,
      'codex-remediation-sandbox-dev-' || v_index,
      'codex-remediation-sandbox-dev-' || v_index,
      'com.x5studio.app.verified.monthly', 'Sandbox', developer_id,
      now() - interval '1 minute', now() + interval '1 month',
      now(), null, null
    );
  end loop;
  if v_index <> 2 then
    raise exception 'two_developer_profiles_required:%', v_index;
  end if;

  select id into outsider_id
    from public.profiles
   where id not in (
     'f3eea23f-0aeb-405b-ab35-2c53173b7a8f'::uuid,
     'eee55a08-18d1-46e3-a303-1411d1bb9333'::uuid
   )
     and not exists (
       select 1
         from public.app_store_sandbox_review_accounts as allowed
        where allowed.user_id = public.profiles.id
          and allowed.enabled
     )
   order by id
   limit 1;
  begin
    perform public.apply_verified_app_store_sandbox_review_transaction(
      outsider_id, 'codex-remediation-sandbox-outsider',
      'codex-remediation-sandbox-outsider',
      'com.x5studio.app.verified.monthly', 'Sandbox', outsider_id,
      now() - interval '1 minute', now() + interval '1 month',
      now(), null, null
    );
  exception when sqlstate '22023' then
    if sqlerrm <> 'sandbox_review_account_not_allowed' then raise; end if;
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'arbitrary_sandbox_account_was_allowed';
  end if;
end;
$sandbox_scope$;

reset role;

do $profile_reconciliation$
declare
  v_uid uuid := current_setting('x5.remediation_user_2')::uuid;
  v_before_credits integer;
  v_end timestamptz := now() + interval '20 days';
  v_credited timestamptz := now() - interval '10 days';
  v_created timestamptz := now() - interval '10 days';
begin
  select credits into v_before_credits from public.profiles where id = v_uid;
  insert into public.iap_entitlements (
    original_transaction_id, user_id, product_id, platform,
    app_account_token, credited_at, credits_granted,
    subscription_end_date, created_at, last_transaction_id
  ) values (
    'codex-remediation-plan-chain', v_uid,
    'com.x5studio.app.pro.monthly', 'ios', v_uid,
    v_credited, 2000, v_end, v_created, 'codex-remediation-plan-tx'
  );
  insert into public.app_store_legacy_bindings (
    original_transaction_id, user_id, app_account_token, product_id,
    legacy_credited_at, legacy_subscription_end_date, legacy_created_at
  ) values (
    'codex-remediation-plan-chain', v_uid, v_uid,
    'com.x5studio.app.pro.monthly', v_credited, v_end, v_created
  );

  update public.profiles
     set plan = 'pro', subscription_type = 'manual_permanent',
         subscription_end_date = null
   where id = v_uid;
  perform public.x5_reconcile_paid_plan_profile(v_uid);
  if (select subscription_end_date from public.profiles where id = v_uid)
     is not null
     or (select subscription_type from public.profiles where id = v_uid)
        <> 'manual_permanent' then
    raise exception 'permanent_null_end_plan_was_overwritten';
  end if;

  update public.profiles
     set plan = 'pro', subscription_type = 'pro_monthly',
         subscription_end_date = now() - interval '1 day'
   where id = v_uid;

  perform public.x5_reconcile_paid_plan_profile(v_uid);
  if (select subscription_end_date from public.profiles where id = v_uid)
     is distinct from v_end then
    raise exception 'trusted_plan_expiry_was_not_advanced';
  end if;

  update public.iap_entitlements
     set credited_at = v_credited + interval '1 second'
   where original_transaction_id = 'codex-remediation-plan-chain';
  update public.profiles
     set plan = 'pro', subscription_end_date = now() - interval '1 day'
   where id = v_uid;
  perform public.x5_reconcile_paid_plan_profile(v_uid);
  if (select plan from public.profiles where id = v_uid) <> 'free' then
    raise exception 'mismatched_legacy_tuple_was_trusted';
  end if;

  delete from public.app_store_legacy_bindings
   where original_transaction_id = 'codex-remediation-plan-chain';
  delete from public.iap_entitlements
   where original_transaction_id = 'codex-remediation-plan-chain';
  update public.profiles
     set plan = 'pro', subscription_end_date = now() - interval '1 day'
   where id = v_uid;
  perform public.x5_reconcile_paid_plan_profile(v_uid);
  if (select plan from public.profiles where id = v_uid) <> 'free' then
    raise exception 'expired_untrusted_plan_was_not_cleared';
  end if;

  update public.profiles
     set plan = 'black', subscription_end_date = now() - interval '1 day'
   where id = v_uid;
  perform public.x5_reconcile_paid_plan_profile(v_uid);
  if (select plan from public.profiles where id = v_uid) <> 'black' then
    raise exception 'black_plan_was_downgraded';
  end if;

  update public.profiles
     set plan = 'pro', subscription_end_date = null
   where id = v_uid;
  perform public.x5_reconcile_paid_plan_profile(v_uid);
  if (select plan from public.profiles where id = v_uid) <> 'pro' then
    raise exception 'permanent_null_end_plan_was_downgraded';
  end if;
  if (select credits from public.profiles where id = v_uid)
     is distinct from v_before_credits then
    raise exception 'plan_reconciliation_changed_credits';
  end if;
end;
$profile_reconciliation$;

set local role service_role;

do $verified_lifecycle$
declare
  v_uid uuid := current_setting('x5.remediation_user_3')::uuid;
  v_before_credits integer;
  v_purchase timestamptz := now() - interval '1 day';
  v_expiry timestamptz := now() + interval '1 month';
  v_response jsonb;
begin
  select credits into v_before_credits from public.profiles where id = v_uid;
  update public.profiles
     set is_verified = false, verified_until = now() - interval '1 day'
   where id = v_uid;

  v_response := public.apply_verified_app_store_subscription_lifecycle(
    '94000000-0000-4000-8000-000000000000', 'REVOKE', now(),
    v_uid, 'codex-remediation-revoke-first-tx',
    'codex-remediation-revoke-first-chain',
    'com.x5studio.app.verified.monthly', 'Production', v_uid,
    v_purchase, v_expiry, now(), now(), now(), null, 0
  );
  if v_response ->> 'status' not in ('applied', 'already_applied')
     or (select is_verified from public.profiles where id = v_uid)
     or (select credits from public.profiles where id = v_uid)
        is distinct from v_before_credits then
    raise exception 'revoke_first_lifecycle_failed:%', v_response;
  end if;

  v_response := public.apply_verified_app_store_subscription_lifecycle(
    '94000000-0000-4000-8000-000000000001', 'SUBSCRIBED', now(),
    v_uid, 'codex-remediation-lifecycle-tx',
    'codex-remediation-lifecycle-chain',
    'com.x5studio.app.verified.monthly', 'Production', v_uid,
    v_purchase, v_expiry, now() - interval '1 minute',
    now() - interval '1 minute', null, null, 1
  );
  if v_response ->> 'status' not in ('applied', 'already_applied')
     or not (select is_verified from public.profiles where id = v_uid)
     or (select verified_until from public.profiles where id = v_uid)
        is distinct from v_expiry then
    raise exception 'subscription_lifecycle_grant_failed:%', v_response;
  end if;

  v_response := public.apply_verified_app_store_subscription_lifecycle(
    '94000000-0000-4000-8000-000000000001', 'SUBSCRIBED', now(),
    v_uid, 'codex-remediation-lifecycle-tx',
    'codex-remediation-lifecycle-chain',
    'com.x5studio.app.verified.monthly', 'Production', v_uid,
    v_purchase, v_expiry, now() - interval '1 minute',
    now() - interval '1 minute', null, null, 1
  );
  if v_response ->> 'status' <> 'already_applied' then
    raise exception 'lifecycle_replay_was_not_exact_once:%', v_response;
  end if;

  v_response := public.apply_verified_app_store_subscription_lifecycle(
    '94000000-0000-4000-8000-000000000002', 'REVOKE', now(),
    v_uid, 'codex-remediation-lifecycle-tx',
    'codex-remediation-lifecycle-chain',
    'com.x5studio.app.verified.monthly', 'Production', v_uid,
    v_purchase, v_expiry, now(), now(), now(), null, 0
  );
  if (select is_verified from public.profiles where id = v_uid) then
    raise exception 'subscription_lifecycle_revoke_failed:%', v_response;
  end if;
  if (select credits from public.profiles where id = v_uid)
     is distinct from v_before_credits then
    raise exception 'verified_lifecycle_changed_credits';
  end if;
end;
$verified_lifecycle$;

reset role;
rollback;

select 'x5_store_backend_remediation_validated_with_rollback' as result;
