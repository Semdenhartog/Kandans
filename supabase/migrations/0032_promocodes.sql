-- 0032_promocodes.sql
-- Eigen actiecodes en vouchers (gratis toegang, zonder betaling): voor testers, influencers en winacties.
-- Betaalde abonnementen en aankopen blijven via Google Play lopen (regels van Google Play).
--
-- Codes staan alleen als hash in de database; de leesbare code bestaat alleen bij jou.
-- Een code maken (in de SQL Editor, niet in de app):
--   select public.create_promo('JOUWCODE', 'alles', null, 1, 'Eigenaar');        -- alles, voor altijd, 1 keer
--   select public.create_promo('LOPER30', 'premium', 30, 200, 'Actie Instagram'); -- 30 dagen Premium, 200 keer
--   select public.create_promo('LUXE-WIN', 'luxe', null, 10, 'Winactie');         -- Luxe-ontwerpen voor altijd
-- Uitzetten: update public.promo_codes set active = false where label = 'Actie Instagram';
-- Overzicht:  select label, grants, days, uses, max_uses, expires_at, active from public.promo_codes;
--
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run.

create extension if not exists pgcrypto with schema extensions;

-- Ook "promo" als bron van een abonnement (naast RevenueCat en Stripe).
alter table public.subscriptions drop constraint if exists subscriptions_provider_check;
alter table public.subscriptions add constraint subscriptions_provider_check
  check (provider in ('revenuecat', 'stripe', 'promo'));
alter table public.subscriptions drop constraint if exists subscriptions_plan_check;
alter table public.subscriptions add constraint subscriptions_plan_check
  check (plan in ('monthly', 'yearly', 'promo'));

-- Premium = minstens één actief abonnement (niet alleen het laatst gewijzigde).
create or replace function public.sync_premium_status()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  perform set_config('kadans.server', 'on', true);
  update public.profiles p
  set is_premium = exists (
    select 1 from public.subscriptions s
    where s.user_id = new.user_id
      and s.status in ('active', 'trialing', 'cancelled')
      and s.current_period_end > now()
  )
  where p.id = new.user_id;
  return new;
end;
$$;

-- De server (en deze functies) mogen is_premium zetten; gebruikers zelf niet.
create or replace function public.protect_profile_server_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated')
     and coalesce(current_setting('kadans.server', true), '') <> 'on' then
    new.coach_free_questions_used := old.coach_free_questions_used;
    new.is_premium := old.is_premium;
  end if;
  return new;
end;
$$;

create table if not exists public.promo_codes (
  code_hash text primary key,
  label text not null check (char_length(label) between 1 and 80),
  grants text not null check (grants in ('premium', 'luxe', 'alles')),
  days int check (days is null or days between 1 and 3650),   -- null = voor altijd
  max_uses int not null default 1 check (max_uses between 1 and 100000),
  uses int not null default 0,
  expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.promo_redemptions (
  code_hash text not null references public.promo_codes(code_hash) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  primary key (code_hash, user_id)
);

-- Pogingen per gebruiker per dag (tegen raden).
create table if not exists public.promo_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null default current_date,
  attempts int not null default 0,
  primary key (user_id, day)
);

-- Losse rechten buiten een abonnement (nu: Luxe-ontwerpen via een code).
create table if not exists public.user_entitlements (
  user_id uuid not null references auth.users(id) on delete cascade,
  entitlement text not null check (entitlement in ('luxe')),
  until timestamptz,                                           -- null = voor altijd
  source text not null default 'promo',
  primary key (user_id, entitlement)
);

alter table public.promo_codes enable row level security;
alter table public.promo_redemptions enable row level security;
alter table public.promo_attempts enable row level security;
alter table public.user_entitlements enable row level security;

drop policy if exists "entitlements_select_own" on public.user_entitlements;
create policy "entitlements_select_own" on public.user_entitlements
  for select using (auth.uid() = user_id);

revoke all on public.promo_codes, public.promo_redemptions, public.promo_attempts from anon, authenticated;
grant select on public.user_entitlements to authenticated;

create or replace function public._promo_hash(code text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select encode(extensions.digest(upper(regexp_replace(coalesce(code, ''), '\s', '', 'g')), 'sha256'), 'hex');
$$;

-- Alleen voor jou (SQL Editor): een code aanmaken.
create or replace function public.create_promo(code text, grants text, days int, max_uses int, label text, expires_at timestamptz default null)
returns text
language plpgsql
security definer set search_path = public, extensions
as $$
begin
  if char_length(regexp_replace(coalesce(code, ''), '\s', '', 'g')) < 6 then
    raise exception 'Code moet minstens 6 tekens hebben';
  end if;
  insert into public.promo_codes (code_hash, label, grants, days, max_uses, expires_at)
  values (public._promo_hash(code), label, grants, days, max_uses, expires_at);
  return 'Code aangemaakt: ' || label;
end;
$$;
revoke execute on function public.create_promo(text, text, int, int, text, timestamptz) from public, anon, authenticated;
revoke execute on function public._promo_hash(text) from public, anon, authenticated;

-- Voor de app: een code inwisselen. Geeft {ok, grants?, until?, message}.
create or replace function public.redeem_promo(code text)
returns jsonb
language plpgsql
security definer set search_path = public, extensions
as $$
declare
  uid uuid := auth.uid();
  h text;
  pc public.promo_codes%rowtype;
  tries int;
  until_at timestamptz;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'message', 'Log eerst in.');
  end if;

  insert into public.promo_attempts (user_id) values (uid)
  on conflict (user_id, day) do update set attempts = public.promo_attempts.attempts + 1
  returning attempts into tries;
  if tries > 10 then
    return jsonb_build_object('ok', false, 'message', 'Te veel pogingen vandaag. Probeer het morgen opnieuw.');
  end if;

  h := public._promo_hash(code);
  select * into pc from public.promo_codes where code_hash = h for update;
  if not found or not pc.active then
    return jsonb_build_object('ok', false, 'unknown', true, 'message', 'Deze code kennen we niet.');
  end if;
  if pc.expires_at is not null and pc.expires_at < now() then
    return jsonb_build_object('ok', false, 'message', 'Deze code is verlopen.');
  end if;
  if exists (select 1 from public.promo_redemptions where code_hash = h and user_id = uid) then
    return jsonb_build_object('ok', false, 'message', 'Je hebt deze code al gebruikt.');
  end if;
  if pc.uses >= pc.max_uses then
    return jsonb_build_object('ok', false, 'message', 'Deze code is al zo vaak gebruikt als mocht.');
  end if;

  until_at := case when pc.days is null then timestamptz '2999-12-31' else now() + make_interval(days => pc.days) end;

  insert into public.promo_redemptions (code_hash, user_id) values (h, uid);
  update public.promo_codes set uses = uses + 1 where code_hash = h;

  perform set_config('kadans.server', 'on', true);
  if pc.grants in ('premium', 'alles') then
    insert into public.subscriptions (user_id, provider, plan, status, current_period_end)
    values (uid, 'promo', 'promo', 'active', until_at)
    on conflict (user_id, provider) do update
      set status = 'active',
          current_period_end = greatest(public.subscriptions.current_period_end, excluded.current_period_end);
  end if;
  if pc.grants in ('luxe', 'alles') then
    insert into public.user_entitlements (user_id, entitlement, until)
    values (uid, 'luxe', case when pc.days is null then null else until_at end)
    on conflict (user_id, entitlement) do update
      set until = case when excluded.until is null or public.user_entitlements.until is null then null
                       else greatest(public.user_entitlements.until, excluded.until) end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'grants', pc.grants,
    'until', case when pc.days is null then null else until_at end,
    'message', 'Gelukt!'
  );
end;
$$;
revoke execute on function public.redeem_promo(text) from public, anon;
grant execute on function public.redeem_promo(text) to authenticated;
