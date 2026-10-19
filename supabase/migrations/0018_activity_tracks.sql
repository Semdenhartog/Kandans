-- GPS-spoor van een run (Google-polyline, uit Strava) om runs automatisch aan routes te koppelen.
-- Lege tekst = bron heeft geen spoor (bijv. handmatig in Strava ingevoerd).
alter table public.activities
  add column if not exists track_polyline text,
  add column if not exists route_link_locked boolean not null default false;

alter table public.activities
  add constraint activities_track_polyline_size check (track_polyline is null or length(track_polyline) <= 100000);

comment on column public.activities.route_link_locked is
  'true = de gebruiker heeft zelf een route gekozen of losgemaakt; dan niet automatisch koppelen.';
