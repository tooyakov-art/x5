-- Make iOS purchase claiming atomic: the RPC that claims an App Store
-- transaction also grants the plan credits exactly once.

alter table public.iap_entitlements
    add column if not exists credited_at timestamptz,
    add column if not exists credits_granted integer not null default 0,
    add column if not exists subscription_end_date timestamptz;

create index if not exists iap_entitlements_user_created_idx
    on public.iap_entitlements (user_id, created_at desc);

create index if not exists iap_entitlements_uncredited_idx
    on public.iap_entitlements (user_id, created_at desc)
    where credited_at is null;

alter table public.profiles
    drop constraint if exists profiles_subscription_type_check;

alter table public.profiles
    add constraint profiles_subscription_type_check
    check (
        subscription_type is null
        or subscription_type in ('monthly', 'yearly', 'lite_monthly', 'pro_monthly', 'max_monthly')
    );

create table if not exists public.app_diagnostics (
    id              bigserial primary key,
    created_at      timestamptz not null default now(),
    build_number    text,
    app_version     text,
    os_version      text,
    device_model    text,
    device_name     text,
    locale          text,
    event           text not null,
    kind            text,
    summary         text,
    stack           text,
    ts              text
);

create index if not exists app_diagnostics_created_at_idx
    on public.app_diagnostics (created_at desc);
create index if not exists app_diagnostics_event_idx
    on public.app_diagnostics (event);
create index if not exists app_diagnostics_build_idx
    on public.app_diagnostics (build_number);

alter table public.app_diagnostics enable row level security;

drop policy if exists "anon_insert_app_diagnostics" on public.app_diagnostics;
create policy "anon_insert_app_diagnostics"
    on public.app_diagnostics
    for insert
    to anon
    with check (true);

create or replace function public.claim_iap_entitlement(
    p_original_transaction_id text,
    p_product_id text,
    p_platform text default 'ios'
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
begin
    if v_uid is null then
        raise exception 'not authenticated';
    end if;

    select *
      into v_row
      from public.iap_entitlements
     where original_transaction_id = p_original_transaction_id
     for update;

    if not found then
        insert into public.iap_entitlements(original_transaction_id, user_id, product_id, platform)
        values (p_original_transaction_id, v_uid, p_product_id, p_platform)
        returning * into v_row;
        v_status := 'claimed';
    elsif v_row.user_id = v_uid then
        v_status := 'already_owned';
    else
        return 'owned_by_other';
    end if;

    v_credits := case p_product_id
        when 'com.x5studio.app.lite.monthly' then 1000
        when 'com.x5studio.app.pro.monthly' then 2000
        when 'com.x5studio.app.max.monthly' then 5000
        else 0
    end;

    v_subscription_type := case p_product_id
        when 'com.x5studio.app.lite.monthly' then 'lite_monthly'
        when 'com.x5studio.app.pro.monthly' then 'pro_monthly'
        when 'com.x5studio.app.max.monthly' then 'max_monthly'
        else null
    end;

    if v_credits > 0 then
        if v_row.credited_at is null then
            update public.iap_entitlements
               set product_id = p_product_id,
                   platform = p_platform,
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
