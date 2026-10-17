-- ============================================================
-- 0009_subscriptions.sql
-- Premium-abonnementen, gesynchroniseerd vanuit RevenueCat webhook
-- ============================================================

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null default 'revenuecat' check (provider in ('revenuecat', 'stripe')),
  plan text not null check (plan in ('monthly', 'yearly')),
  status text not null check (status in ('active', 'trialing', 'expired', 'cancelled')),
  current_period_end timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider)
);

create trigger trg_subscriptions_updated_at
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

-- Houd profiles.is_premium gesynchroniseerd met de actieve subscription-status
create or replace function public.sync_premium_status()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles
  set is_premium = (new.status in ('active', 'trialing') and new.current_period_end > now())
  where id = new.user_id;
  return new;
end;
$$;

create trigger trg_subscriptions_sync_premium
  after insert or update on public.subscriptions
  for each row execute function public.sync_premium_status();

alter table public.subscriptions enable row level security;

create policy "subscriptions_select_own"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- Schrijven uitsluitend via de RevenueCat/Stripe webhook Edge Function (service_role).

-- ------------------------------------------------------------
-- Free-tier limiet: business rule gedocumenteerd + afdwingbaar via check in Edge Function
-- (1 route voor gratis gebruikers). Hier als constante voor consistentie.
-- ------------------------------------------------------------
insert into public.model_config (key, value) values
  ('free_tier_max_routes', '1')
on conflict (key) do nothing;
