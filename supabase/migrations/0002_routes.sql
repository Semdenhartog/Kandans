-- ============================================================
-- 0002_routes.sql
-- Routes + geografische punten (PostGIS)
-- ============================================================

create table public.routes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  source text not null check (source in ('drawn', 'gpx_upload', 'strava_import')),
  strava_route_id text,                 -- externe referentie indien geïmporteerd
  distance_meters numeric not null,
  elevation_gain_meters numeric,
  estimated_duration_seconds integer,   -- op basis van gebruikersprofiel-pace
  start_latitude double precision not null,
  start_longitude double precision not null,
  polyline text not null,  -- volledige route als WKT of polyline-string (geen postgis geography nodig)
  is_favorite boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.routes is 'Opgeslagen hardlooproutes: getekend, GPX-upload of Strava-import.';

create index idx_routes_user_id on public.routes(user_id);
-- Geen GIST-index op text; polyline is nu text in plaats van geography

create trigger trg_routes_updated_at
  before update on public.routes
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- route_points: puntenreeks per km-marker, voor per-km weeranalyse
-- ------------------------------------------------------------
create table public.route_points (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.routes(id) on delete cascade,
  sequence_index integer not null,       -- volgorde langs de route (0-based)
  km_marker numeric not null,            -- afstand vanaf start in km (bv. 3.0)
  latitude double precision not null,
  longitude double precision not null,
  elevation_meters numeric,
  bearing_degrees numeric,               -- looprichting op dit punt, nodig voor windrichting-analyse
  created_at timestamptz not null default now(),
  unique (route_id, sequence_index)
);

comment on table public.route_points is 'Punten per kilometer langs een route, gebruikt voor per-km weeranalyse en windrichting t.o.v. looprichting.';

create index idx_route_points_route_id on public.route_points(route_id);

-- ------------------------------------------------------------
-- RLS: toegang alleen via eigenaarschap van de route
-- ------------------------------------------------------------
alter table public.routes enable row level security;
alter table public.route_points enable row level security;

create policy "routes_all_own"
  on public.routes for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "route_points_select_own"
  on public.route_points for select
  using (
    exists (
      select 1 from public.routes r
      where r.id = route_points.route_id and r.user_id = auth.uid()
    )
  );

create policy "route_points_write_own"
  on public.route_points for insert
  with check (
    exists (
      select 1 from public.routes r
      where r.id = route_points.route_id and r.user_id = auth.uid()
    )
  );

create policy "route_points_delete_own"
  on public.route_points for delete
  using (
    exists (
      select 1 from public.routes r
      where r.id = route_points.route_id and r.user_id = auth.uid()
    )
  );
