-- 0042 Wedstrijdkalender uit open overheidsdata (10-11-2026)
-- Bron: officiële bekendmakingen van gemeenten (evenementenvergunningen en meldingen), via de SRU-zoekdienst
-- van KOOP (repository.overheid.nl, licentie CC-0). Gevuld door de GitHub-workflow "Wedstrijden ophalen"
-- (tools/wedstrijden/importeer.py) met de Management API; de app leest alleen.

create table if not exists public.race_calendar (
  key text primary key,                 -- genormaliseerde naam + datum (één wedstrijd, ook bij meerdere publicaties)
  name text not null check (char_length(name) between 2 and 120),
  race_date date not null,
  municipality text,                    -- gemeente die publiceerde
  place text,                           -- plaats of straat uit de titel, als die er duidelijk in staat
  lat double precision,
  lon double precision,
  kind text not null default 'loop' check (kind in ('marathon', 'halve', 'trail', 'cross', 'loop', 'estafette')),
  status text not null default 'aangevraagd' check (status in ('aangevraagd', 'melding', 'verleend')),
  source_id text not null,              -- bv. gmb-2026-498017
  source_url text not null,
  source_title text not null,
  published date,
  hidden boolean not null default false, -- met de hand verbergen (fout herkend)
  updated_at timestamptz not null default now()
);

create index if not exists race_calendar_date on public.race_calendar (race_date) where not hidden;

alter table public.race_calendar enable row level security;

-- Openbare overheidsinformatie: elke ingelogde gebruiker mag lezen. Schrijven alleen via de importer (service).
drop policy if exists race_calendar_read on public.race_calendar;
create policy race_calendar_read on public.race_calendar
  for select to authenticated
  using (not hidden);

revoke insert, update, delete on public.race_calendar from anon, authenticated;
grant select on public.race_calendar to authenticated;
