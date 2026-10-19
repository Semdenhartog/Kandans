-- Verloop van een run uit Strava (voor tijden per km en de grafiek), eenmalig opgehaald en bewaard.
alter table public.activities add column if not exists streams jsonb;
alter table public.activities add constraint activities_streams_size
  check (streams is null or pg_column_size(streams) <= 200000);
comment on column public.activities.streams is 'Verloop van de run (tijd, afstand, hoogte, hartslag, positie), uit Strava; voor tijden per km en de grafiek.';
