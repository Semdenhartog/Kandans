-- ============================================================
-- 0006_start_time_scores.sql
-- Berekende scores per kandidaat-vertrektijd, per route/dag.
-- Gecached zodat het dashboard niet elke keer herberekent.
-- ============================================================

create table public.start_time_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  route_id uuid not null references public.routes(id) on delete cascade,
  for_date date not null,
  candidate_time time not null,          -- bv. 06:45:00

  weather_score numeric not null,        -- 0-100
  performance_score numeric not null,    -- 0-100, gebaseerd op performance_profile
  comfort_score numeric not null,        -- 0-100, samengesteld
  total_score numeric not null,          -- gewogen eindscore 0-100

  predicted_pace_delta_sec_per_km numeric,  -- t.o.v. persoonlijk gemiddelde, bv. -11 = 11 sec/km sneller
  temperature_celsius numeric,
  feels_like_celsius numeric,
  precipitation_probability_pct numeric,
  wind_speed_kmh numeric,
  humidity_pct numeric,

  computed_at timestamptz not null default now(),
  unique (user_id, route_id, for_date, candidate_time)
);

comment on table public.start_time_scores is 'Resultaat van de slimme vertrekplanner: alle geteste starttijden met scores, top 5 wordt client-side geselecteerd op total_score.';

create index idx_start_time_scores_lookup
  on public.start_time_scores(user_id, route_id, for_date);

alter table public.start_time_scores enable row level security;

create policy "start_time_scores_select_own"
  on public.start_time_scores for select
  using (auth.uid() = user_id);

-- Schrijven via Edge Function (compute-optimal-start) met service_role.
