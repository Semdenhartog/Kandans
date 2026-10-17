-- ============================================================
-- 0003_activities.sql
-- Uitgevoerde runs (bron: Strava, Garmin, handmatig)
-- Basis voor het AI-persoonlijkheidsmodel
-- ============================================================

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  route_id uuid references public.routes(id) on delete set null,
  source text not null check (source in ('strava', 'garmin', 'manual')),
  external_id text,                      -- id bij de bron (voor dedup bij sync)
  started_at timestamptz not null,
  distance_meters numeric not null,
  moving_time_seconds integer not null,
  average_pace_seconds_per_km numeric not null,
  average_heart_rate integer,
  elevation_gain_meters numeric,

  -- weersomstandigheden tijdens de run (opgehaald/gecached uit weather_snapshots)
  temperature_celsius numeric,
  feels_like_celsius numeric,
  precipitation_probability_pct numeric,
  wind_speed_kmh numeric,
  wind_direction_degrees numeric,
  humidity_pct numeric,
  uv_index numeric,

  created_at timestamptz not null default now(),
  unique (user_id, source, external_id)
);

comment on table public.activities is 'Historische runs met bijbehorende weersomstandigheden; voedt het AI-persoonlijkheidsmodel.';

create index idx_activities_user_id_started_at on public.activities(user_id, started_at desc);

alter table public.activities enable row level security;

create policy "activities_all_own"
  on public.activities for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ------------------------------------------------------------
-- external_connections: OAuth-koppelingen (Strava/Garmin)
-- Tokens worden NIET hier opgeslagen -> Supabase Vault (zie edge functions).
-- Deze tabel bevat alleen niet-gevoelige koppelingsstatus.
-- ------------------------------------------------------------
create table public.external_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check (provider in ('strava', 'garmin')),
  provider_athlete_id text,
  connected_at timestamptz not null default now(),
  last_synced_at timestamptz,
  sync_status text not null default 'idle' check (sync_status in ('idle', 'syncing', 'error')),
  unique (user_id, provider)
);

alter table public.external_connections enable row level security;

create policy "external_connections_all_own"
  on public.external_connections for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
