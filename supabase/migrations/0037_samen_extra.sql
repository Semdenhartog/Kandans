-- 0037: valmelding + aanmoedigen bij live delen, loopmaatjes, weddenschappen en loopgroepen.
-- Strava-runs tellen nergens mee (regel: source <> 'strava' en external_id not like 'viastrava-%').

-- Kadans-runs van een loper in een periode (zonder Strava). Alleen voor intern gebruik.
create or replace function public._own_km(uid uuid, p_from timestamptz, p_to timestamptz)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(distance_meters), 0) / 1000.0
  from public.activities
  where user_id = uid and started_at >= p_from and started_at < p_to
    and source <> 'strava' and coalesce(external_id, '') not like 'viastrava-%';
$$;
revoke all on function public._own_km(uuid, timestamptz, timestamptz) from public, anon, authenticated;

-- Live delen: valmelding ---------------------------------------------------------
alter table public.live_shares add column if not exists alert text check (alert is null or alert in ('fall'));
alter table public.live_shares add column if not exists alert_at timestamptz;

-- Live delen: aanmoedigingen (kijkers schrijven via de functie live-share) --------
create table if not exists public.live_cheers (
  id bigint generated always as identity primary key,
  share_id uuid not null references public.live_shares(id) on delete cascade,
  from_name text check (from_name is null or char_length(from_name) <= 30),
  kind text not null check (kind in ('hup', 'top', 'bijna', 'trots')),
  created_at timestamptz not null default now(),
  heard boolean not null default false
);
create index if not exists idx_live_cheers_share on public.live_cheers(share_id, created_at);
alter table public.live_cheers enable row level security;
create policy "live_cheers_select_own" on public.live_cheers for select to authenticated
  using (exists (select 1 from public.live_shares s where s.id = share_id and s.user_id = (select auth.uid())));
create policy "live_cheers_update_own" on public.live_cheers for update to authenticated
  using (exists (select 1 from public.live_shares s where s.id = share_id and s.user_id = (select auth.uid())));

-- Loopmaatjes (alleen wie het zelf aanzet; plek afgerond op ± 5 km) -------------
create table if not exists public.buddy_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  grid_lat numeric not null check (grid_lat between -90 and 90),
  grid_lon numeric not null check (grid_lon between -180 and 180),
  pace_sec int not null check (pace_sec between 150 and 1200),
  times text[] not null default '{}',
  note text check (note is null or char_length(note) <= 80),
  updated_at timestamptz not null default now()
);
alter table public.buddy_profiles enable row level security;
create policy "buddy_own" on public.buddy_profiles for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.buddy_set(p_on boolean, p_lat double precision, p_lon double precision,
                                            p_pace int, p_times text[], p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  if not p_on then delete from public.buddy_profiles where user_id = uid; return; end if;
  insert into public.buddy_profiles (user_id, grid_lat, grid_lon, pace_sec, times, note, updated_at)
  values (uid, round((p_lat * 20)::numeric) / 20, round((p_lon * 20)::numeric) / 20, p_pace,
          coalesce(p_times[1:4], '{}'), nullif(trim(coalesce(p_note, '')), ''), now())
  on conflict (user_id) do update set grid_lat = excluded.grid_lat, grid_lon = excluded.grid_lon,
    pace_sec = excluded.pace_sec, times = excluded.times, note = excluded.note, updated_at = now();
end;
$$;

create or replace function public.buddy_find()
returns table (nickname text, km int, pace_sec int, times text[], note text)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); me public.buddy_profiles;
begin
  perform public._cm_check_member(uid);
  select * into me from public.buddy_profiles where user_id = uid;
  if me is null then return; end if;
  return query
  select cp.nickname,
         greatest(1, round(111 * sqrt(power(b.grid_lat - me.grid_lat, 2)
           + power((b.grid_lon - me.grid_lon) * cos(radians(me.grid_lat::double precision)), 2)))::int) as km,
         b.pace_sec, b.times, b.note
  from public.buddy_profiles b
  join public.community_profiles cp on cp.user_id = b.user_id
  where b.user_id <> uid
    and abs(b.grid_lat - me.grid_lat) <= 0.2 and abs(b.grid_lon - me.grid_lon) <= 0.3
    and abs(b.pace_sec - me.pace_sec) <= 60
    and b.updated_at > now() - interval '90 days'
    and not public._sr_blocked(uid, b.user_id)
  order by km, abs(b.pace_sec - me.pace_sec)
  limit 30;
end;
$$;

create or replace function public.buddy_mine()
returns table (enabled boolean, pace_sec int, times text[], note text)
language sql stable security definer set search_path = public as $$
  select true, pace_sec, times, note from public.buddy_profiles where user_id = auth.uid();
$$;

-- Weddenschappen ------------------------------------------------------------------
create table if not exists public.bets (
  id bigint generated always as identity primary key,
  creator uuid not null references auth.users(id) on delete cascade,
  opponent uuid not null references auth.users(id) on delete cascade,
  stake text not null check (char_length(stake) between 1 and 60),
  starts_on date not null,
  ends_on date not null check (ends_on > starts_on and ends_on <= starts_on + 62),
  status text not null default 'open' check (status in ('open', 'running', 'declined')),
  created_at timestamptz not null default now(),
  check (creator <> opponent)
);
alter table public.bets enable row level security;
create policy "bets_select_own" on public.bets for select to authenticated
  using ((select auth.uid()) in (creator, opponent));

create or replace function public.bet_create(p_nickname text, p_stake text, p_days int)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid; new_id bigint;
begin
  perform public._cm_check_member(uid);
  other := public._sr_user(p_nickname);
  if other is null or other = uid or public._sr_blocked(uid, other) then raise exception 'Deze loper is niet gevonden.'; end if;
  if not (public._sr_follows(uid, other) or public._sr_follows(other, uid)) then
    raise exception 'Je kunt alleen wedden met lopers die je volgt of die jou volgen.';
  end if;
  if (select count(*) from public.bets where creator = uid and status <> 'declined' and ends_on >= current_date) >= 5 then
    raise exception 'Je hebt al 5 lopende weddenschappen.';
  end if;
  insert into public.bets (creator, opponent, stake, starts_on, ends_on)
  values (uid, other, trim(p_stake), current_date, current_date + greatest(3, least(coalesce(p_days, 30), 62)))
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.bet_answer(p_id bigint, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  update public.bets set status = case when p_accept then 'running' else 'declined' end,
         starts_on = case when p_accept then current_date else starts_on end,
         ends_on = case when p_accept then current_date + (ends_on - starts_on) else ends_on end
  where id = p_id and opponent = uid and status = 'open';
end;
$$;

create or replace function public.bets_list()
returns table (id bigint, other_nickname text, i_created boolean, stake text, starts_on date, ends_on date,
               status text, my_km numeric, their_km numeric)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  return query
  select b.id, cp.nickname, b.creator = uid, b.stake, b.starts_on, b.ends_on, b.status,
         round(public._own_km(uid, b.starts_on::timestamptz, (b.ends_on + 1)::timestamptz), 1),
         round(public._own_km(case when b.creator = uid then b.opponent else b.creator end,
                              b.starts_on::timestamptz, (b.ends_on + 1)::timestamptz), 1)
  from public.bets b
  join public.community_profiles cp on cp.user_id = case when b.creator = uid then b.opponent else b.creator end
  where uid in (b.creator, b.opponent) and b.status <> 'declined' and b.ends_on >= current_date - 14
  order by b.ends_on desc
  limit 30;
end;
$$;

-- Loopgroepen ---------------------------------------------------------------------
create table if not exists public.run_groups (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 2 and 40),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  owner uuid not null references auth.users(id) on delete cascade,
  route_name text check (route_name is null or char_length(route_name) <= 60),
  route_polyline text check (route_polyline is null or char_length(route_polyline) <= 20000),
  created_at timestamptz not null default now()
);
create table if not exists public.run_group_members (
  group_id bigint not null references public.run_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
alter table public.run_groups enable row level security;
alter table public.run_group_members enable row level security;
create policy "run_groups_select_member" on public.run_groups for select to authenticated
  using (exists (select 1 from public.run_group_members m where m.group_id = id and m.user_id = (select auth.uid())));
create policy "run_group_members_select_own" on public.run_group_members for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.group_create(p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c text; gid bigint;
begin
  perform public._cm_check_member(uid);
  if (select count(*) from public.run_groups where owner = uid) >= 5 then raise exception 'Je kunt hooguit 5 groepen maken.'; end if;
  loop
    c := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when c ~ '^[A-Z0-9]{6}$' and not exists (select 1 from public.run_groups where code = c);
  end loop;
  insert into public.run_groups (name, code, owner) values (trim(p_name), c, uid) returning id into gid;
  insert into public.run_group_members (group_id, user_id) values (gid, uid);
  return c;
end;
$$;

create or replace function public.group_join(p_code text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g public.run_groups;
begin
  perform public._cm_check_member(uid);
  select * into g from public.run_groups where code = upper(trim(p_code));
  if g is null then raise exception 'Geen groep gevonden met deze code.'; end if;
  if (select count(*) from public.run_group_members where group_id = g.id) >= 50 then raise exception 'Deze groep is vol (50 lopers).'; end if;
  insert into public.run_group_members (group_id, user_id) values (g.id, uid) on conflict do nothing;
  return g.name;
end;
$$;

create or replace function public.group_leave(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  delete from public.run_group_members where group_id = p_id and user_id = uid;
  -- Laatste lid weg: groep weg. Eigenaar weg: het oudste lid wordt eigenaar.
  if not exists (select 1 from public.run_group_members where group_id = p_id) then
    delete from public.run_groups where id = p_id;
  elsif (select owner from public.run_groups where id = p_id) = uid then
    update public.run_groups set owner = (select user_id from public.run_group_members where group_id = p_id order by joined_at limit 1)
    where id = p_id;
  end if;
end;
$$;

create or replace function public.groups_mine()
returns table (id bigint, name text, code text, members int, is_owner boolean, route_name text, route_polyline text)
language sql stable security definer set search_path = public as $$
  select g.id, g.name, g.code, (select count(*)::int from public.run_group_members m2 where m2.group_id = g.id),
         g.owner = auth.uid(), g.route_name, g.route_polyline
  from public.run_groups g
  join public.run_group_members m on m.group_id = g.id and m.user_id = auth.uid()
  order by g.created_at;
$$;

create or replace function public.group_board(p_id bigint)
returns table (nickname text, is_me boolean, week_km numeric, month_km numeric)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if not exists (select 1 from public.run_group_members where group_id = p_id and user_id = uid) then
    raise exception 'Je zit niet in deze groep.';
  end if;
  return query
  select cp.nickname, m.user_id = uid,
         round(public._own_km(m.user_id, date_trunc('week', now()), now() + interval '1 day'), 1),
         round(public._own_km(m.user_id, date_trunc('month', now()), now() + interval '1 day'), 1)
  from public.run_group_members m
  join public.community_profiles cp on cp.user_id = m.user_id
  where m.group_id = p_id and not public._sr_blocked(uid, m.user_id)
  order by 3 desc, 4 desc;
end;
$$;

create or replace function public.group_set_route(p_id bigint, p_name text, p_polyline text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.run_groups set route_name = nullif(trim(coalesce(p_name, '')), ''), route_polyline = nullif(p_polyline, '')
  where id = p_id and owner = auth.uid();
end;
$$;

-- Rechten -------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'buddy_set(boolean,double precision,double precision,int,text[],text)', 'buddy_find()', 'buddy_mine()',
    'bet_create(text,text,int)', 'bet_answer(bigint,boolean)', 'bets_list()',
    'group_create(text)', 'group_join(text)', 'group_leave(bigint)', 'groups_mine()', 'group_board(bigint)',
    'group_set_route(bigint,text,text)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
