-- ============================================================
-- 0001_extensions_and_profiles.sql
-- Extensies + gebruikersprofiel
-- ============================================================

-- create extension if not exists postgis;  -- Vereist postgis image
-- create extension if not exists pg_cron;  -- Vereist postgresql-contrib

-- ------------------------------------------------------------
-- profiles: 1-op-1 met auth.users, aangemaakt via trigger
-- ------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  date_of_birth date,
  sex text check (sex in ('male', 'female', 'unspecified')),
  home_latitude double precision,
  home_longitude double precision,
  units text not null default 'metric' check (units in ('metric', 'imperial')),
  is_premium boolean not null default false,
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Publiek profiel per gebruiker, 1-op-1 met auth.users.';

-- Trigger: maak automatisch een profiel aan bij nieuwe auth.users registratie
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- updated_at auto-update helper (herbruikbaar voor alle tabellen)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Geen insert-policy nodig voor gebruikers: gebeurt via security-definer trigger.
-- Geen delete-policy: verwijdering loopt via auth.users cascade (account-verwijdering endpoint).
