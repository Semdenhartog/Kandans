-- Korte analyse van de coach per run (alleen eigen runs, niet uit Strava).
alter table public.activities add column if not exists ai_summary text;
