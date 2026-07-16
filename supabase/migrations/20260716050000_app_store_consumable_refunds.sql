begin;

-- Apple can refund a finished consumable after its credits have already been
-- spent. Keep refund events separate from the immutable purchase ledgers. A
-- negative profile balance is intentional debt: every spending path requires
-- enough non-negative credits before it can deduct another amount.
create table public.app_store_consumable_refunds (
  environment text not null,
  transaction_id text not null,
  original_transaction_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  app_account_token uuid not null,
  purchase_date timestamptz not null,
  signed_date timestamptz not null,
  revocation_date timestamptz not null,
  quantity integer not null,
  credits_reversed integer not null,
  created_at timestamptz not null default now(),
  primary key (environment, transaction_id),
  constraint app_store_consumable_refunds_environment
    check (environment in ('Production', 'Sandbox')),
  constraint app_store_consumable_refunds_transaction_nonempty
    check (btrim(transaction_id) <> ''),
  constraint app_store_consumable_refunds_original_nonempty
    check (btrim(original_transaction_id) <> ''),
  constraint app_store_consumable_refunds_account_matches_user
    check (app_account_token = user_id),
  constraint app_store_consumable_refunds_quantity_one
    check (quantity = 1),
  constraint app_store_consumable_refunds_dates_valid
    check (
      signed_date >= purchase_date - interval '5 minutes'
      and revocation_date >= purchase_date
      and signed_date >= revocation_date - interval '5 minutes'
    ),
  constraint app_store_consumable_refunds_server_amount
    check (
      (product_id = 'com.x5studio.app.credits.1000' and credits_reversed = 1000)
      or (product_id = 'com.x5studio.app.credits.2000' and credits_reversed = 2000)
      or (product_id = 'com.x5studio.app.credits.5000' and credits_reversed = 5000)
    )
);

create index app_store_consumable_refunds_user_id_idx
  on public.app_store_consumable_refunds (user_id, revocation_date desc);

alter table public.app_store_consumable_refunds owner to postgres;
alter table public.app_store_consumable_refunds enable row level security;
alter table public.app_store_consumable_refunds force row level security;

revoke all privileges on table public.app_store_consumable_refunds
  from public, anon, authenticated;
revoke all privileges on table public.app_store_consumable_refunds
  from service_role;

create function public.apply_verified_app_store_consumable_refund(
  p_user_id uuid,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_environment text,
  p_app_account_token uuid,
  p_purchase_date timestamptz,
  p_signed_date timestamptz,
  p_revocation_date timestamptz,
  p_quantity integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_transaction_id text := nullif(btrim(p_transaction_id), '');
  v_original_transaction_id text := nullif(btrim(p_original_transaction_id), '');
  v_product_id text := nullif(btrim(p_product_id), '');
  v_environment text := case lower(btrim(coalesce(p_environment, '')))
    when 'production' then 'Production'
    when 'sandbox' then 'Sandbox'
    else null
  end;
  v_expected_credits integer;
  v_credits_reversed integer;
  source record;
  existing public.app_store_consumable_refunds%rowtype;
begin
  if p_user_id is null then
    raise exception using errcode = '22023', message = 'invalid_user_id';
  end if;
  if v_transaction_id is null or length(v_transaction_id) > 255 then
    raise exception using errcode = '22023', message = 'invalid_transaction_id';
  end if;
  if v_original_transaction_id is null
     or length(v_original_transaction_id) > 255 then
    raise exception using errcode = '22023', message = 'invalid_original_transaction_id';
  end if;
  if v_environment is null then
    raise exception using errcode = '22023', message = 'invalid_environment';
  end if;

  v_expected_credits := case v_product_id
    when 'com.x5studio.app.credits.1000' then 1000
    when 'com.x5studio.app.credits.2000' then 2000
    when 'com.x5studio.app.credits.5000' then 5000
    else null
  end;
  if v_expected_credits is null then
    raise exception using errcode = '22023', message = 'unknown_product';
  end if;
  if p_quantity is distinct from 1 then
    raise exception using errcode = '22023', message = 'invalid_quantity';
  end if;
  if p_app_account_token is null then
    raise exception using errcode = '22023', message = 'missing_account_token';
  end if;
  if p_app_account_token <> p_user_id then
    raise exception using errcode = '22023', message = 'account_token_mismatch';
  end if;
  if p_purchase_date is null
     or p_signed_date is null
     or p_revocation_date is null then
    raise exception using errcode = '22023', message = 'missing_transaction_dates';
  end if;
  if p_purchase_date > clock_timestamp() + interval '10 minutes'
     or p_signed_date > clock_timestamp() + interval '10 minutes'
     or p_revocation_date > clock_timestamp() + interval '10 minutes'
     or p_signed_date < p_purchase_date - interval '5 minutes'
     or p_revocation_date < p_purchase_date
     or p_signed_date < p_revocation_date - interval '5 minutes' then
    raise exception using errcode = '22023', message = 'invalid_revocation_date';
  end if;

  -- Match both grant RPCs' lock order: profile, transaction advisory lock, then
  -- immutable source row. Concurrent grant/refund requests cannot double-apply.
  perform 1
    from public.profiles
   where id = p_user_id
   for update;
  if not found then
    raise exception using errcode = '22023', message = 'profile_not_found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'app-store-consumable-refund:' || v_environment || ':' || v_transaction_id,
      0
    )
  );

  if v_environment = 'Production' then
    select
      purchase.user_id,
      purchase.original_transaction_id,
      purchase.product_id,
      purchase.environment,
      purchase.app_account_token,
      purchase.purchase_date,
      purchase.signed_date,
      purchase.revocation_date,
      purchase.quantity,
      purchase.credits_granted,
      null::timestamptz as expires_date,
      false as is_verified_product
      into source
      from public.app_store_consumable_transactions as purchase
     where purchase.transaction_id = v_transaction_id
     for update;
  else
    select
      purchase.user_id,
      purchase.original_transaction_id,
      purchase.product_id,
      purchase.environment,
      purchase.app_account_token,
      purchase.purchase_date,
      purchase.signed_date,
      purchase.revocation_date,
      purchase.quantity,
      purchase.credits_granted,
      purchase.expires_date,
      purchase.is_verified_product
      into source
      from public.app_store_sandbox_review_transactions as purchase
     where purchase.transaction_id = v_transaction_id
     for update;
  end if;

  if not found then
    raise exception using errcode = '22023', message = 'consumable_refund_source_not_found';
  end if;
  if source.user_id <> p_user_id then
    raise exception using errcode = '22023', message = 'owned_by_other';
  end if;
  if source.original_transaction_id <> v_original_transaction_id
     or source.product_id <> v_product_id
     or source.environment <> v_environment
     or source.app_account_token <> p_app_account_token
     or source.purchase_date <> p_purchase_date
     or source.quantity <> p_quantity
     or source.revocation_date is not null
     or source.signed_date > p_signed_date then
    raise exception using errcode = '22023', message = 'consumable_refund_source_mismatch';
  end if;
  if v_environment = 'Sandbox'
     and (source.expires_date is not null or source.is_verified_product) then
    raise exception using errcode = '22023', message = 'consumable_refund_source_mismatch';
  end if;

  -- Never trust a caller-supplied amount. The immutable purchase ledger is the
  -- sole source of the exact amount being reversed.
  v_credits_reversed := source.credits_granted;
  if v_credits_reversed is distinct from v_expected_credits then
    raise exception using errcode = '22023', message = 'consumable_refund_source_mismatch';
  end if;

  select refund.*
    into existing
    from public.app_store_consumable_refunds as refund
   where refund.environment = v_environment
     and refund.transaction_id = v_transaction_id
   for update;

  if found then
    if existing.user_id <> p_user_id then
      raise exception using errcode = '22023', message = 'owned_by_other';
    end if;
    if existing.original_transaction_id <> v_original_transaction_id
       or existing.product_id <> v_product_id
       or existing.app_account_token <> p_app_account_token
       or existing.purchase_date <> p_purchase_date
       or existing.revocation_date <> p_revocation_date
       or existing.quantity <> p_quantity
       or existing.credits_reversed <> v_credits_reversed then
      raise exception using errcode = '22023', message = 'consumable_refund_id_conflict';
    end if;

    -- Apple may re-sign the exact refund with a newer signedDate. Keep the
    -- first signed date immutable and do not subtract the balance again.
    return jsonb_build_object(
      'status', 'already_applied',
      'credits_granted', 0,
      'subscription_end_date', null,
      'is_verified', false
    );
  end if;

  insert into public.app_store_consumable_refunds (
    environment,
    transaction_id,
    original_transaction_id,
    user_id,
    product_id,
    app_account_token,
    purchase_date,
    signed_date,
    revocation_date,
    quantity,
    credits_reversed
  ) values (
    v_environment,
    v_transaction_id,
    v_original_transaction_id,
    p_user_id,
    v_product_id,
    p_app_account_token,
    p_purchase_date,
    p_signed_date,
    p_revocation_date,
    p_quantity,
    v_credits_reversed
  );

  update public.profiles
     set credits = coalesce(credits, 0) - v_credits_reversed
   where id = p_user_id;

  return jsonb_build_object(
    'status', 'applied',
    'credits_granted', 0,
    'subscription_end_date', null,
    'is_verified', false
  );
end;
$function$;

comment on table public.app_store_consumable_refunds is
  'Immutable owner-bound Apple-signed refunds for Production and App Review Sandbox credit packs.';
comment on function public.apply_verified_app_store_consumable_refund(
  uuid, text, text, text, text, uuid,
  timestamptz, timestamptz, timestamptz, integer
) is
  'Reverses exactly the credits recorded by a matching immutable App Store consumable purchase. Service role only.';

alter function public.apply_verified_app_store_consumable_refund(
  uuid, text, text, text, text, uuid,
  timestamptz, timestamptz, timestamptz, integer
) owner to postgres;

revoke execute on function public.apply_verified_app_store_consumable_refund(
  uuid, text, text, text, text, uuid,
  timestamptz, timestamptz, timestamptz, integer
) from public, anon, authenticated, service_role;

grant execute on function public.apply_verified_app_store_consumable_refund(
  uuid, text, text, text, text, uuid,
  timestamptz, timestamptz, timestamptz, integer
) to service_role;

commit;
