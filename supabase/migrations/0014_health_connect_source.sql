-- ============================================================
-- 0014_health_connect_source.sql
-- Runs uit Health Connect (Android: Fitbit, Samsung, Garmin, Polar ...)
-- ============================================================

alter table public.activities drop constraint if exists activities_source_check;
alter table public.activities add constraint activities_source_check
  check (source in ('strava', 'garmin', 'manual', 'health_connect'));
