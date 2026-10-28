-- Runs die je in Kadans zelf opneemt (GPS).
alter table public.activities drop constraint if exists activities_source_check;
alter table public.activities add constraint activities_source_check
  check (source in ('strava', 'garmin', 'manual', 'health_connect', 'runwise'));
