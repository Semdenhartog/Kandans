-- Hoogteprofiel per route (elke ~50 m: [meters, hoogte]) voor het profiel onder de kaart.
alter table public.routes
  add column if not exists elevation_profile jsonb;

alter table public.routes
  add constraint routes_elevation_profile_is_array
  check (elevation_profile is null or (jsonb_typeof(elevation_profile) = 'array' and jsonb_array_length(elevation_profile) <= 2000));
