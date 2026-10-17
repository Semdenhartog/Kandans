-- ============================================================
-- 0012_strava_connection.sql
-- Strava-koppeling: tokens veilig opslaan + koppelstatus voor de app
-- ============================================================

-- Het schema "private" is NIET bereikbaar via de API (alleen "public" is dat).
-- Alleen de server-functie (service role) kan hier lezen en schrijven.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Strava-tokens per gebruiker. Komen nooit in de app.
create table private.strava_tokens (
  user_id uuid primary key references auth.users(id) on delete cascade,
  athlete_id bigint not null,
  access_token text not null,
  refresh_token text not null,
  expires_at timestamptz not null,
  scope text,
  updated_at timestamptz not null default now()
);

-- Eenmalige "state"-codes tegen vervalste koppelverzoeken (CSRF).
create table private.oauth_states (
  state text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'strava',
  created_at timestamptz not null default now()
);

revoke all on all tables in schema private from public, anon, authenticated;
grant usage on schema private to service_role;
grant all on all tables in schema private to service_role;

-- ------------------------------------------------------------
-- Koppelstatus: extra velden + gebruikers mogen alleen LEZEN.
-- Koppelen/ontkoppelen loopt via de server-functie "strava".
-- ------------------------------------------------------------
alter table public.external_connections
  add column if not exists athlete_name text,
  add column if not exists last_error text;

-- De bestaande lees-/schrijfpolicy blijft; schrijven door gebruikers wordt
-- geblokkeerd met "restrictive" policies (alleen de server mag wijzigen).
create policy "external_connections_no_insert" on public.external_connections
  as restrictive for insert to anon, authenticated with check (false);
create policy "external_connections_no_update" on public.external_connections
  as restrictive for update to anon, authenticated using (false);
create policy "external_connections_no_delete" on public.external_connections
  as restrictive for delete to anon, authenticated using (false);

-- Runs: zoeken op bron (voor dubbele runs en ontkoppelen).
create index if not exists idx_activities_user_source
  on public.activities(user_id, source);

-- ------------------------------------------------------------
-- Hulpfuncties voor de server-functie. Alleen service_role mag ze aanroepen.
-- ------------------------------------------------------------
create or replace function public.strava_save_state(p_state text, p_user uuid)
returns void language sql security definer set search_path = '' as $$
  delete from private.oauth_states where created_at < now() - interval '1 hour';
  insert into private.oauth_states (state, user_id) values (p_state, p_user);
$$;

-- Geeft de gebruiker bij een state terug (max. 15 min oud) en verwijdert hem.
create or replace function public.strava_take_state(p_state text)
returns uuid language sql security definer set search_path = '' as $$
  delete from private.oauth_states
  where state = p_state and created_at > now() - interval '15 minutes'
  returning user_id;
$$;

create or replace function public.strava_save_tokens(
  p_user uuid, p_athlete bigint, p_access text, p_refresh text,
  p_expires timestamptz, p_scope text
) returns void language sql security definer set search_path = '' as $$
  insert into private.strava_tokens (user_id, athlete_id, access_token, refresh_token, expires_at, scope, updated_at)
  values (p_user, p_athlete, p_access, p_refresh, p_expires, p_scope, now())
  on conflict (user_id) do update set
    athlete_id = excluded.athlete_id,
    access_token = excluded.access_token,
    refresh_token = excluded.refresh_token,
    expires_at = excluded.expires_at,
    scope = coalesce(excluded.scope, private.strava_tokens.scope),
    updated_at = now();
$$;

create or replace function public.strava_get_tokens(p_user uuid)
returns table (athlete_id bigint, access_token text, refresh_token text, expires_at timestamptz, scope text)
language sql security definer set search_path = '' as $$
  select t.athlete_id, t.access_token, t.refresh_token, t.expires_at, t.scope
  from private.strava_tokens t where t.user_id = p_user;
$$;

create or replace function public.strava_delete_tokens(p_user uuid)
returns void language sql security definer set search_path = '' as $$
  delete from private.strava_tokens where user_id = p_user;
$$;

revoke execute on function public.strava_save_state(text, uuid) from public, anon, authenticated;
revoke execute on function public.strava_take_state(text) from public, anon, authenticated;
revoke execute on function public.strava_save_tokens(uuid, bigint, text, text, timestamptz, text) from public, anon, authenticated;
revoke execute on function public.strava_get_tokens(uuid) from public, anon, authenticated;
revoke execute on function public.strava_delete_tokens(uuid) from public, anon, authenticated;
grant execute on function public.strava_save_state(text, uuid) to service_role;
grant execute on function public.strava_take_state(text) to service_role;
grant execute on function public.strava_save_tokens(uuid, bigint, text, text, timestamptz, text) to service_role;
grant execute on function public.strava_get_tokens(uuid) to service_role;
grant execute on function public.strava_delete_tokens(uuid) to service_role;
