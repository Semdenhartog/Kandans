-- RunWise: alle nieuwe databasewijzigingen in één keer (0012 t/m 0014).
-- Plak dit hele bestand in Supabase -> SQL Editor -> New query, en klik op Run.

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

drop policy if exists "external_connections_all_own" on public.external_connections;

create policy "external_connections_select_own"
  on public.external_connections for select
  using (auth.uid() = user_id);

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

-- ============================================================
-- 0013_ai_coach.sql
-- AI-hardloopcoach: gesprekken + limieten (gratis proberen, daarna premium)
-- ============================================================

create table public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) <= 8000),
  created_at timestamptz not null default now()
);

comment on table public.coach_messages is 'Chatgeschiedenis met de AI-coach. Schrijven alleen via Edge Function "coach".';

create index idx_coach_messages_user_created
  on public.coach_messages(user_id, created_at desc);

alter table public.coach_messages enable row level security;

-- Gebruikers mogen hun eigen gesprek lezen en wissen; schrijven gaat via de server.
create policy "coach_messages_select_own"
  on public.coach_messages for select
  using (auth.uid() = user_id);

create policy "coach_messages_delete_own"
  on public.coach_messages for delete
  using (auth.uid() = user_id);

-- Limieten (aanpasbaar zonder nieuwe app-versie)
insert into public.model_config (key, value) values
  ('coach_free_questions', '3'),        -- totaal aantal gratis vragen per account
  ('coach_premium_daily_limit', '30')   -- vragen per dag voor premium
on conflict (key) do nothing;

-- Teller voor gratis vragen: telt ook als de gebruiker zijn gesprek wist.
alter table public.profiles
  add column if not exists coach_free_questions_used integer not null default 0;

-- Gebruikers mogen deze teller niet zelf aanpassen (alleen de server).
create or replace function public.protect_profile_server_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    new.coach_free_questions_used := old.coach_free_questions_used;
    new.is_premium := old.is_premium;
  end if;
  return new;
end;
$$;

create trigger trg_profiles_protect_server_fields
  before update on public.profiles
  for each row execute function public.protect_profile_server_fields();

revoke execute on function public.protect_profile_server_fields() from public, anon, authenticated;

-- ============================================================
-- 0014_health_connect_source.sql
-- Runs uit Health Connect (Android: Fitbit, Samsung, Garmin, Polar ...)
-- ============================================================

alter table public.activities drop constraint if exists activities_source_check;
alter table public.activities add constraint activities_source_check
  check (source in ('strava', 'garmin', 'manual', 'health_connect'));
