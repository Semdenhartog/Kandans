-- ============================================================
-- 0005_performance_profile.sql
-- Afgeleide AI-inzichten per gebruiker (uitkomst van het
-- persoonlijkheidsmodel, herberekend na elke sync/nieuwe activity)
-- ============================================================

create table public.performance_profile (
  user_id uuid primary key references public.profiles(id) on delete cascade,

  -- Temperatuurzones (uit regressie pace ~ temperatuur op basis van activities)
  optimal_temp_min_celsius numeric,
  optimal_temp_max_celsius numeric,
  worst_temp_min_celsius numeric,
  worst_temp_max_celsius numeric,
  pct_faster_in_optimal_zone numeric,    -- bv. 23.0 -> "23% beter tussen X en Y"

  -- Windgevoeligheid: seconden vertraging per km per 10 km/u extra wind
  wind_sensitivity_sec_per_km_per_10kmh numeric,

  -- Luchtvochtigheid: seconden vertraging per km per 10% extra vocht boven 60%
  humidity_sensitivity_sec_per_km_per_10pct numeric,

  -- Ochtend vs avond
  morning_avg_pace_seconds_per_km numeric,
  evening_avg_pace_seconds_per_km numeric,
  preferred_time_of_day text check (preferred_time_of_day in ('morning', 'evening', 'no_preference')),

  sample_size integer not null default 0,  -- aantal activities gebruikt in laatste berekening
  model_version text not null default 'v1_linear',
  computed_at timestamptz not null default now()
);

comment on table public.performance_profile is 'Output van het AI-persoonlijkheidsmodel: 1 rij per gebruiker, herberekend via Edge Function na nieuwe activities.';

alter table public.performance_profile enable row level security;

create policy "performance_profile_select_own"
  on public.performance_profile for select
  using (auth.uid() = user_id);

-- Schrijven gebeurt uitsluitend server-side (Edge Function met service_role),
-- dus geen insert/update policy voor 'authenticated'.

-- Minimum aantal runs vereist voordat het model betrouwbaar is (business rule,
-- gebruikt door de AI Edge Function; hier gedocumenteerd als constante-tabel)
create table public.model_config (
  key text primary key,
  value text not null
);

alter table public.model_config enable row level security;
create policy "model_config_select_authenticated"
  on public.model_config for select
  to authenticated
  using (true);

insert into public.model_config (key, value) values
  ('min_activities_for_profile', '8'),
  ('min_activities_for_high_confidence', '20');
