-- Let an App Store entitlement move to a new X5 account when the old X5
-- account was deleted. Live accounts still keep exclusive ownership.

alter table public.iap_entitlements
    add column if not exists app_account_token uuid;

drop function if exists public.claim_iap_entitlement(text, text, text);

create or replace function public.claim_iap_entitlement(
    p_original_transaction_id text,
    p_product_id text,
    p_platform text default 'ios',
    p_app_account_token text default null
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_uid uuid := auth.uid();
    v_row public.iap_entitlements%rowtype;
    v_status text;
    v_credits integer := 0;
    v_subscription_type text;
    v_period_end timestamptz := now() + interval '1 month';
    v_owner_auth_exists boolean := false;
    v_owner_profile_exists boolean := false;
    v_app_account_token uuid := null;
begin
    if v_uid is null then
        raise exception 'not authenticated';
    end if;

    if p_app_account_token ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        v_app_account_token := p_app_account_token::uuid;
    end if;

    select *
      into v_row
      from public.iap_entitlements
     where original_transaction_id = p_original_transaction_id
     for update;

    if not found then
        insert into public.iap_entitlements(
            original_transaction_id,
            user_id,
            product_id,
            platform,
            app_account_token
        )
        values (
            p_original_transaction_id,
            v_uid,
            p_product_id,
            p_platform,
            v_app_account_token
        )
        returning * into v_row;
        v_status := 'claimed';
    elsif v_row.user_id = v_uid then
        update public.iap_entitlements
           set product_id = p_product_id,
               platform = p_platform,
               app_account_token = coalesce(v_app_account_token, app_account_token)
         where original_transaction_id = p_original_transaction_id
         returning * into v_row;
        v_status := 'already_owned';
    else
        select exists(select 1 from auth.users where id = v_row.user_id)
          into v_owner_auth_exists;
        select exists(select 1 from public.profiles where id = v_row.user_id)
          into v_owner_profile_exists;

        if v_owner_auth_exists and v_owner_profile_exists then
            return 'owned_by_other';
        end if;

        update public.iap_entitlements
           set user_id = v_uid,
               product_id = p_product_id,
               platform = p_platform,
               app_account_token = coalesce(v_app_account_token, app_account_token),
               credited_at = null,
               credits_granted = 0,
               subscription_end_date = null
         where original_transaction_id = p_original_transaction_id
         returning * into v_row;
        v_status := 'transferred';
    end if;

    v_credits := case p_product_id
        when 'com.x5studio.app.lite.monthly' then 1000
        when 'com.x5studio.app.pro.monthly' then 2000
        when 'com.x5studio.app.max.monthly' then 5000
        when 'x5_lite_monthly' then 1000
        when 'x5_pro_monthly' then 2000
        when 'x5_max_monthly' then 5000
        else 0
    end;

    v_subscription_type := case p_product_id
        when 'com.x5studio.app.lite.monthly' then 'lite_monthly'
        when 'com.x5studio.app.pro.monthly' then 'pro_monthly'
        when 'com.x5studio.app.max.monthly' then 'max_monthly'
        when 'x5_lite_monthly' then 'lite_monthly'
        when 'x5_pro_monthly' then 'pro_monthly'
        when 'x5_max_monthly' then 'max_monthly'
        else null
    end;

    if v_credits > 0 then
        if v_row.credited_at is null then
            update public.iap_entitlements
               set product_id = p_product_id,
                   platform = p_platform,
                   app_account_token = coalesce(v_app_account_token, app_account_token),
                   credited_at = now(),
                   credits_granted = v_credits,
                   subscription_end_date = coalesce(subscription_end_date, v_period_end)
             where original_transaction_id = p_original_transaction_id
             returning * into v_row;

            insert into public.profiles (
                id,
                credits,
                plan,
                subscription_type,
                subscription_date,
                subscription_end_date
            )
            values (
                v_uid,
                v_credits,
                'pro',
                v_subscription_type,
                now(),
                v_period_end
            )
            on conflict (id) do update
               set credits = coalesce(public.profiles.credits, 0) + excluded.credits,
                   plan = 'pro',
                   subscription_type = excluded.subscription_type,
                   subscription_date = coalesce(public.profiles.subscription_date, excluded.subscription_date),
                   subscription_end_date = greatest(
                       coalesce(public.profiles.subscription_end_date, '-infinity'::timestamptz),
                       excluded.subscription_end_date
                   );
        else
            update public.profiles
               set plan = 'pro',
                   subscription_type = coalesce(public.profiles.subscription_type, v_subscription_type),
                   subscription_end_date = greatest(
                       coalesce(public.profiles.subscription_end_date, '-infinity'::timestamptz),
                       coalesce(v_row.subscription_end_date, v_period_end)
                   )
             where id = v_uid;
        end if;
    elsif p_product_id in ('com.x5studio.app.verified.monthly', 'x5_verified_monthly') then
        if v_row.credited_at is null then
            update public.iap_entitlements
               set product_id = p_product_id,
                   platform = p_platform,
                   app_account_token = coalesce(v_app_account_token, app_account_token),
                   credited_at = now(),
                   credits_granted = 0,
                   subscription_end_date = coalesce(subscription_end_date, v_period_end)
             where original_transaction_id = p_original_transaction_id
             returning * into v_row;
        end if;

        update public.profiles
           set is_verified = true,
               verified_until = greatest(
                   coalesce(public.profiles.verified_until, '-infinity'::timestamptz),
                   coalesce(v_row.subscription_end_date, v_period_end)
               )
         where id = v_uid;
    end if;

    return v_status;
end;
$function$;
