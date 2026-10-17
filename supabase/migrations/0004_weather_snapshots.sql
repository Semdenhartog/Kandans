-- ============================================================
-- 0004_weather_snapshots.sql
-- Cache van Open-Meteo forecast/historische data
-- Voorkomt herhaalde externe calls voor dezelfde locatie+tijdstip
-- ============================================================

create table public.weather_snapshots (
  id uuid primary key default gen_random_uuid(),
  latitude_rounded numeric not null,     -- afgerond op 2 decimalen (~1.1km precisie) voor cache-hergebruik
  longitude_rounded numeric not null,
  valid_at timestamptz not null,         -- uur waarvoor deze data geldt
  temperature_celsius numeric,
  feels_like_celsius numeric,
  precipitation_probability_pct numeric,
  precipitation_mm numeric,
  wind_speed_kmh numeric,
  wind_direction_degrees numeric,
  humidity_pct numeric,
  uv_index numeric,
  is_forecast boolean not null default true,  -- true = voorspelling, false = historisch/actueel
  fetched_at timestamptz not null default now(),
  unique (latitude_rounded, longitude_rounded, valid_at)
);

comment on table public.weather_snapshots is 'Gecachte Open-Meteo data per locatie+uur; TTL-beheer via fetched_at + cron cleanup.';

create index idx_weather_snapshots_lookup
  on public.weather_snapshots(latitude_rounded, longitude_rounded, valid_at);

-- Snapshots zijn geen persoonsgegevens -> leesbaar voor elke ingelogde gebruiker (gedeelde cache),
-- schrijven alleen via service_role (Edge Functions).
alter table public.weather_snapshots enable row level security;

-- Geen policies in lokale dev; RLS is uitgeschakeld
-- create policy "weather_snapshots_select_authenticated"
--   on public.weather_snapshots for select
--   to authenticated
--   using (true);

-- Geen insert/update policy voor 'authenticated' -> alleen service_role (Edge Functions) mag schrijven,
-- wat automatisch RLS omzeilt via de service key.

-- Cleanup: verwijder oude forecast-snapshots ouder dan 14 dagen (behoud historische i.v.m. AI-model)
-- Uitgeschakeld voor lokale dev (pg_cron niet beschikbaar zonder postgre contrib)
-- select cron.schedule(
--   'cleanup-old-weather-forecasts',
--   '0 3 * * *',  -- dagelijks 03:00 UTC
--   $$
--     delete from public.weather_snapshots
--     where is_forecast = true and fetched_at < now() - interval '14 days';
--   $$
-- );
