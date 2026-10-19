-- ------------------------------------------------------------
-- Maanduitdaging: één doel (km) per gebruiker per maand.
-- ------------------------------------------------------------
create table if not exists public.monthly_goals (
  user_id uuid not null references public.profiles(id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  target_km numeric not null check (target_km between 5 and 1000),
  updated_at timestamptz not null default now(),
  primary key (user_id, month)
);

alter table public.monthly_goals enable row level security;

create policy "monthly_goals_all_own" on public.monthly_goals
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ------------------------------------------------------------
-- Live locatie delen tijdens een run.
-- Kijkers lezen NIET direct uit deze tabellen: dat gaat via de
-- server-functie "live-share" met het geheime token uit de link.
-- ------------------------------------------------------------
create table if not exists public.live_shares (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique check (length(token) >= 24),
  display_name text check (length(display_name) <= 40),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  last_lat double precision,
  last_lon double precision,
  last_accuracy real,
  last_at timestamptz,
  check (expires_at <= started_at + interval '6 hours')
);

create index if not exists idx_live_shares_user on public.live_shares(user_id, started_at desc);

create table if not exists public.live_share_points (
  id bigint generated always as identity primary key,
  share_id uuid not null references public.live_shares(id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  recorded_at timestamptz not null default now()
);

create index if not exists idx_live_share_points_share on public.live_share_points(share_id, recorded_at);

alter table public.live_shares enable row level security;
alter table public.live_share_points enable row level security;

create policy "live_shares_all_own" on public.live_shares
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "live_share_points_select_own" on public.live_share_points
  for select to authenticated
  using (exists (select 1 from public.live_shares s where s.id = share_id and s.user_id = (select auth.uid())));

create policy "live_share_points_insert_own" on public.live_share_points
  for insert to authenticated
  with check (exists (
    select 1 from public.live_shares s
    where s.id = share_id and s.user_id = (select auth.uid()) and s.ended_at is null and s.expires_at > now()
  ));

create policy "live_share_points_delete_own" on public.live_share_points
  for delete to authenticated
  using (exists (select 1 from public.live_shares s where s.id = share_id and s.user_id = (select auth.uid())));
