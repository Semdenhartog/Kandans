-- ============================================================
-- 0015_generated_routes.sql
-- Routes die RunWise zelf maakt (rondje vanaf een startpunt)
-- ============================================================

alter table public.routes drop constraint if exists routes_source_check;
alter table public.routes add constraint routes_source_check
  check (source in ('drawn', 'gpx_upload', 'strava_import', 'generated'));
