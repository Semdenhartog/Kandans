-- ============================================================
-- 0007_race_events.sql
-- Wedstrijdmodus: doelen + AI-advies
-- ============================================================

create table public.race_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,                    -- "Halve Marathon Eindhoven"
  race_date date not null,
  distance_meters numeric not null,
  start_time time,
  start_latitude double precision,
  start_longitude double precision,
  goal_time_seconds integer not null,    -- doeltijd, bv. 6300 = 1:45:00
  route_id uuid references public.routes(id) on delete set null,

  -- AI-advies, herberekend naarmate de wedstrijddatum nadert en forecast beschikbaar komt
  predicted_finish_seconds integer,
  temperature_impact_seconds integer,    -- verwachte extra/minder seconden door temperatuur
  wind_impact_seconds integer,
  clothing_advice text,
  hydration_advice text,
  pacing_advice text,
  advice_computed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.race_events is 'Wedstrijddoelen van de gebruiker met AI-gegenereerd advies naarmate de weersvoorspelling beschikbaar komt (doorgaans binnen 10 dagen voor de wedstrijd).';

create index idx_race_events_user_id on public.race_events(user_id, race_date);

create trigger trg_race_events_updated_at
  before update on public.race_events
  for each row execute function public.set_updated_at();

alter table public.race_events enable row level security;

create policy "race_events_all_own"
  on public.race_events for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
