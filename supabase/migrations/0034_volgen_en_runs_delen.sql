-- 0034_volgen_en_runs_delen.sql
-- Volgen zoals bij Strava: volgers (met optie "ik keur volgers goed"), runs delen met je volgers of iedereen,
-- applaus en reacties op runs, en een feed "Volgend".
--
-- Privacy (bewuste keuzes):
--  * Alleen wie meedoet aan Samen (bijnaam). Anderen zien je bijnaam, nooit je naam of e-mail.
--  * Delen is per run en standaard "Volgers". Niets wordt vanzelf gedeeld.
--  * Runs uit Strava (ook via Health Connect) kunnen niet gedeeld worden (voorwaarden van Strava).
--  * Gedeeld wordt een kopie: titel, datum (zonder tijdstip), afstand, tijd, tempo, hoogtemeters en een route
--    waarvan de app begin en eind al heeft weggeknipt (privacyzone). Geen hartslag of andere gezondheidsgegevens.
--  * Melden en blokkeren werken net als in de community; blokkeren haalt ook het volgen aan beide kanten weg.
--
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run. (Na 0033_community_feed.)

-- Volgen: verzoeken en goedkeuren ---------------------------------------------

alter table public.community_profiles add column if not exists approve_followers boolean not null default false;

alter table public.community_follows add column if not exists status text not null default 'accepted';
alter table public.community_follows drop constraint if exists community_follows_status_check;
alter table public.community_follows add constraint community_follows_status_check check (status in ('pending', 'accepted'));
create index if not exists community_follows_followee on public.community_follows (followee, status);

-- Gedeelde runs ---------------------------------------------------------------

create table if not exists public.run_shares (
  id bigint generated always as identity primary key,
  activity_id uuid not null unique references public.activities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  visibility text not null default 'followers' check (visibility in ('followers', 'everyone')),
  title text not null check (char_length(title) between 1 and 80),
  run_date date not null,
  distance_meters numeric not null,
  moving_time_seconds integer not null,
  pace_seconds_per_km numeric not null,
  elevation_gain_meters numeric,
  polyline text check (polyline is null or char_length(polyline) <= 20000),
  created_at timestamptz not null default now(),
  hidden boolean not null default false,
  report_count int not null default 0
);
create index if not exists run_shares_user_time on public.run_shares (user_id, id desc) where not hidden;
create index if not exists run_shares_time on public.run_shares (id desc) where not hidden;

create table if not exists public.run_kudos (
  share_id bigint not null references public.run_shares(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (share_id, user_id)
);

create table if not exists public.run_comments (
  id bigint generated always as identity primary key,
  share_id bigint not null references public.run_shares(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now(),
  hidden boolean not null default false,
  report_count int not null default 0
);
create index if not exists run_comments_share on public.run_comments (share_id, id);

alter table public.run_shares enable row level security;
alter table public.run_kudos enable row level security;
alter table public.run_comments enable row level security;
revoke all on public.run_shares, public.run_kudos, public.run_comments from anon, authenticated;

-- Melden: ook runs en reacties op runs.
alter table public.community_reports drop constraint if exists community_reports_kind_check;
alter table public.community_reports add constraint community_reports_kind_check
  check (kind in ('post', 'comment', 'run', 'run_comment'));

-- Hulpfuncties ----------------------------------------------------------------

create or replace function public._sr_follows(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.community_follows where follower = a and followee = b and status = 'accepted');
$$;

create or replace function public._sr_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.community_blocks
                 where (blocker = a and blocked = b) or (blocker = b and blocked = a));
$$;

-- Mag [viewer] een run van [owner] met deze zichtbaarheid zien?
-- Volgers: alleen goedgekeurde volgers. Iedereen: alle leden, behalve als de eigenaar volgers goedkeurt
-- (dan telt "iedereen" als "volgers").
create or replace function public._sr_can_see(viewer uuid, owner uuid, vis text)
returns boolean language sql stable security definer set search_path = public as $$
  select viewer = owner or (
    not public._sr_blocked(viewer, owner) and (
      public._sr_follows(viewer, owner)
      or (vis = 'everyone' and not coalesce((select approve_followers from public.community_profiles where user_id = owner), true))
    )
  );
$$;

create or replace function public._sr_user(p_nickname text)
returns uuid language sql stable security definer set search_path = public as $$
  select user_id from public.community_profiles where lower(nickname) = lower(trim(p_nickname));
$$;

create or replace function public._sr_follow_state(a uuid, b uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select status from public.community_follows where follower = a and followee = b), 'none');
$$;

-- Volgen ----------------------------------------------------------------------

create or replace function public.social_settings()
returns table (nickname text, approve_followers boolean, requests int)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  return query
  select cp.nickname, cp.approve_followers,
         (select count(*)::int from public.community_follows f where f.followee = uid and f.status = 'pending')
  from public.community_profiles cp where cp.user_id = uid;
end;
$$;

create or replace function public.social_set_approve(p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  update public.community_profiles set approve_followers = coalesce(p_approve, false) where user_id = uid;
  -- Goedkeuren uitgezet: openstaande verzoeken gaan vanzelf door.
  if not coalesce(p_approve, false) then
    update public.community_follows set status = 'accepted' where followee = uid and status = 'pending';
  end if;
end;
$$;

create or replace function public.social_follow(p_nickname text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid; needs_ok boolean; n int;
begin
  perform public._cm_check_member(uid);
  other := public._sr_user(p_nickname);
  if other is null or public._sr_blocked(uid, other) then raise exception 'Deze loper is niet gevonden.'; end if;
  if other = uid then raise exception 'Jezelf volgen kan niet.'; end if;
  if exists (select 1 from public.community_follows where follower = uid and followee = other) then
    return public._sr_follow_state(uid, other);
  end if;
  select count(*) into n from public.community_follows where follower = uid and created_at > now() - interval '1 day';
  if n >= 100 then raise exception 'Je hebt vandaag al 100 lopers gevolgd. Morgen weer.'; end if;
  select approve_followers into needs_ok from public.community_profiles where user_id = other;
  insert into public.community_follows (follower, followee, status)
  values (uid, other, case when needs_ok then 'pending' else 'accepted' end);
  return case when needs_ok then 'pending' else 'accepted' end;
end;
$$;

-- Ontvolgen (of je verzoek intrekken).
create or replace function public.social_unfollow(p_nickname text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  delete from public.community_follows where follower = uid and followee = public._sr_user(p_nickname);
end;
$$;

-- Verzoek goedkeuren of weigeren.
create or replace function public.social_answer(p_nickname text, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public._cm_check_member(uid);
  other := public._sr_user(p_nickname);
  if p_accept then
    update public.community_follows set status = 'accepted' where follower = other and followee = uid and status = 'pending';
  else
    delete from public.community_follows where follower = other and followee = uid and status = 'pending';
  end if;
end;
$$;

-- Iemand als volger weghalen (die krijgt daar geen bericht van).
create or replace function public.social_remove_follower(p_nickname text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  delete from public.community_follows where follower = public._sr_user(p_nickname) and followee = uid;
end;
$$;

-- Jouw lijsten: 'followers', 'following' of 'requests'. Alleen je eigen lijsten zijn op te vragen.
create or replace function public.social_people(p_kind text)
returns table (nickname text, follow_state text, follows_me boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  if p_kind = 'following' then
    return query
    select cp.nickname, f.status, public._sr_follows(cp.user_id, uid)
    from public.community_follows f join public.community_profiles cp on cp.user_id = f.followee
    where f.follower = uid order by lower(cp.nickname) limit 500;
  elsif p_kind = 'requests' then
    return query
    select cp.nickname, public._sr_follow_state(uid, cp.user_id), false
    from public.community_follows f join public.community_profiles cp on cp.user_id = f.follower
    where f.followee = uid and f.status = 'pending' order by f.created_at desc limit 200;
  else
    return query
    select cp.nickname, public._sr_follow_state(uid, cp.user_id), true
    from public.community_follows f join public.community_profiles cp on cp.user_id = f.follower
    where f.followee = uid and f.status = 'accepted' order by lower(cp.nickname) limit 500;
  end if;
end;
$$;

-- Zoeken op bijnaam (begint met…), minstens 2 tekens.
create or replace function public.social_search(p_query text)
returns table (nickname text, follow_state text, follows_me boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := lower(trim(coalesce(p_query, '')));
begin
  perform public._cm_check_member(uid);
  if char_length(q) < 2 then return; end if;
  q := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');
  return query
  select cp.nickname, public._sr_follow_state(uid, cp.user_id), public._sr_follows(cp.user_id, uid)
  from public.community_profiles cp
  where lower(cp.nickname) like q || '%' and cp.user_id <> uid and not public._sr_blocked(uid, cp.user_id)
  order by lower(cp.nickname) limit 20;
end;
$$;

-- Profiel van een loper. Aantallen zijn openbaar voor leden; de lijsten zelf niet.
create or replace function public.social_profile(p_nickname text)
returns table (nickname text, is_me boolean, approve_followers boolean, followers int, following int, runs int,
               follow_state text, follows_me boolean, can_see_runs boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public._cm_check_member(uid);
  other := public._sr_user(p_nickname);
  if other is null or public._sr_blocked(uid, other) then raise exception 'Deze loper is niet gevonden.'; end if;
  return query
  select cp.nickname, other = uid, cp.approve_followers,
         (select count(*)::int from public.community_follows f where f.followee = other and f.status = 'accepted'),
         (select count(*)::int from public.community_follows f where f.follower = other and f.status = 'accepted'),
         (select count(*)::int from public.run_shares s
            where s.user_id = other and not s.hidden and public._sr_can_see(uid, other, s.visibility)),
         public._sr_follow_state(uid, other),
         public._sr_follows(other, uid),
         other = uid or public._sr_follows(uid, other) or not cp.approve_followers
  from public.community_profiles cp where cp.user_id = other;
end;
$$;

-- Runs delen ------------------------------------------------------------------

create or replace function public.social_share_run(p_activity uuid, p_visibility text, p_title text, p_polyline text)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a record; problem text; n int; t text := trim(coalesce(p_title, '')); new_id bigint;
begin
  perform public._cm_check_member(uid);
  if not exists (select 1 from public.community_rules where user_id = uid) then
    raise exception 'Lees en accepteer eerst de huisregels.';
  end if;
  if p_visibility not in ('followers', 'everyone') then raise exception 'Kies wie je run mag zien.'; end if;
  select * into a from public.activities where id = p_activity and user_id = uid;
  if a.id is null then raise exception 'Deze run bestaat niet (meer).'; end if;
  if a.source = 'strava' or coalesce(a.external_id, '') like 'viastrava-%' then
    raise exception 'Runs uit Strava kun je hier niet delen (voorwaarden van Strava).';
  end if;
  if t = '' then t := 'Run'; end if;
  if char_length(t) > 80 then raise exception 'De titel mag maximaal 80 tekens zijn.'; end if;
  problem := public._cm_text_problem(t);
  if problem is not null then raise exception '%', problem; end if;
  if p_polyline is not null and char_length(p_polyline) > 20000 then raise exception 'De route is te lang om te delen.'; end if;
  select count(*) into n from public.run_shares where user_id = uid and created_at > now() - interval '1 day';
  if n >= 20 and not exists (select 1 from public.run_shares where activity_id = p_activity) then
    raise exception 'Je hebt vandaag al 20 runs gedeeld. Morgen weer.';
  end if;
  insert into public.run_shares (activity_id, user_id, visibility, title, run_date, distance_meters, moving_time_seconds,
                                 pace_seconds_per_km, elevation_gain_meters, polyline)
  values (a.id, uid, p_visibility, t, (a.started_at at time zone 'Europe/Amsterdam')::date, a.distance_meters,
          a.moving_time_seconds, a.average_pace_seconds_per_km, a.elevation_gain_meters, nullif(p_polyline, ''))
  on conflict (activity_id) do update set
    visibility = excluded.visibility, title = excluded.title, run_date = excluded.run_date,
    distance_meters = excluded.distance_meters, moving_time_seconds = excluded.moving_time_seconds,
    pace_seconds_per_km = excluded.pace_seconds_per_km, elevation_gain_meters = excluded.elevation_gain_meters,
    polyline = excluded.polyline
  returning run_shares.id into new_id;
  return new_id;
end;
$$;

create or replace function public.social_unshare_run(p_activity uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.run_shares where activity_id = p_activity and user_id = auth.uid();
$$;

-- Is deze eigen run gedeeld? (Leeg = niet gedeeld.)
create or replace function public.social_share_of(p_activity uuid)
returns table (id bigint, visibility text, title text, kudos int, comments int)
language sql stable security definer set search_path = public as $$
  select s.id, s.visibility, s.title,
         (select count(*)::int from public.run_kudos k where k.share_id = s.id),
         (select count(*)::int from public.run_comments c where c.share_id = s.id and not c.hidden)
  from public.run_shares s where s.activity_id = p_activity and s.user_id = auth.uid();
$$;

-- Feed: 'following' = jij + wie je volgt; 'everyone' = runs die voor iedereen zijn; of één loper (p_nickname).
create or replace function public.social_feed(p_scope text default 'following', p_nickname text default null,
                                              p_before bigint default null, p_limit int default 20)
returns table (id bigint, nickname text, title text, run_date date, distance_meters numeric, moving_time_seconds int,
               pace_seconds_per_km numeric, elevation_gain_meters numeric, polyline text, visibility text, created_at timestamptz,
               kudos int, comments int, kudoed boolean, mine boolean, can_delete boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); one_user uuid;
begin
  perform public._cm_check_member(uid);
  if p_nickname is not null then
    one_user := public._sr_user(p_nickname);
    if one_user is null then return; end if;
  end if;
  return query
  select s.id, cp.nickname, s.title, s.run_date, s.distance_meters, s.moving_time_seconds, s.pace_seconds_per_km,
         s.elevation_gain_meters, s.polyline, s.visibility, s.created_at,
         (select count(*)::int from public.run_kudos k where k.share_id = s.id),
         (select count(*)::int from public.run_comments c where c.share_id = s.id and not c.hidden),
         exists (select 1 from public.run_kudos k where k.share_id = s.id and k.user_id = uid),
         s.user_id = uid,
         s.user_id = uid or public._cm_is_mod(uid)
  from public.run_shares s
  join public.community_profiles cp on cp.user_id = s.user_id
  where not s.hidden
    and (p_before is null or s.id < p_before)
    and (one_user is null or s.user_id = one_user)
    and (
      one_user is not null
      or (p_scope = 'everyone' and (s.visibility = 'everyone' or s.user_id = uid))
      or (coalesce(p_scope, 'following') <> 'everyone' and (s.user_id = uid or public._sr_follows(uid, s.user_id)))
    )
    and public._sr_can_see(uid, s.user_id, s.visibility)
  order by s.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
end;
$$;

-- Applaus geven of terugnemen. Niet op je eigen run.
create or replace function public.social_kudo(p_share bigint)
returns boolean language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record;
begin
  perform public._cm_check_member(uid);
  select * into s from public.run_shares where id = p_share and not hidden;
  if s.id is null or not public._sr_can_see(uid, s.user_id, s.visibility) then raise exception 'Deze run is niet (meer) te zien.'; end if;
  if s.user_id = uid then return false; end if;
  if exists (select 1 from public.run_kudos where share_id = p_share and user_id = uid) then
    delete from public.run_kudos where share_id = p_share and user_id = uid;
    return false;
  end if;
  insert into public.run_kudos (share_id, user_id) values (p_share, uid) on conflict do nothing;
  return true;
end;
$$;

-- Wie gaf applaus (bijnamen), voor de eigenaar en wie de run mag zien.
create or replace function public.social_kudos_of(p_share bigint)
returns table (nickname text)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record;
begin
  perform public._cm_check_member(uid);
  select * into s from public.run_shares where id = p_share and not hidden;
  if s.id is null or not public._sr_can_see(uid, s.user_id, s.visibility) then return; end if;
  return query
  select cp.nickname from public.run_kudos k join public.community_profiles cp on cp.user_id = k.user_id
  where k.share_id = p_share and not public._sr_blocked(uid, k.user_id)
  order by k.created_at desc limit 200;
end;
$$;

create or replace function public.social_comments_of(p_share bigint)
returns table (id bigint, body text, created_at timestamptz, nickname text, mine boolean, can_delete boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record;
begin
  perform public._cm_check_member(uid);
  select * into s from public.run_shares where run_shares.id = p_share and not hidden;
  if s.id is null or not public._sr_can_see(uid, s.user_id, s.visibility) then return; end if;
  return query
  select c.id, c.body, c.created_at, cp.nickname, c.user_id = uid,
         c.user_id = uid or s.user_id = uid or public._cm_is_mod(uid)
  from public.run_comments c join public.community_profiles cp on cp.user_id = c.user_id
  where c.share_id = p_share and not c.hidden and not public._sr_blocked(uid, c.user_id)
  order by c.id limit 200;
end;
$$;

create or replace function public.social_comment(p_share bigint, p_body text)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record; problem text; n int; new_id bigint;
begin
  perform public._cm_check_member(uid);
  if not exists (select 1 from public.community_rules where user_id = uid) then
    raise exception 'Lees en accepteer eerst de huisregels.';
  end if;
  select * into s from public.run_shares where id = p_share and not hidden;
  if s.id is null or not public._sr_can_see(uid, s.user_id, s.visibility) then raise exception 'Deze run is niet (meer) te zien.'; end if;
  problem := public._cm_text_problem(p_body);
  if problem is not null then raise exception '%', problem; end if;
  select count(*) into n from public.run_comments where user_id = uid and created_at > now() - interval '1 day';
  if n >= 50 then raise exception 'Je hebt vandaag al 50 reacties geplaatst. Morgen weer.'; end if;
  insert into public.run_comments (share_id, user_id, body) values (p_share, uid, trim(p_body)) returning run_comments.id into new_id;
  return new_id;
end;
$$;

-- Melden: na 3 meldingen (of 1 van een moderator) verdwijnt het tot een moderator kijkt.
create or replace function public.social_report(p_kind text, p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int;
begin
  perform public._cm_check_member(uid);
  if p_kind not in ('run', 'run_comment') then raise exception 'Onbekend soort melding.'; end if;
  insert into public.community_reports (kind, target_id, user_id, reason)
  values (p_kind, p_id, uid, left(coalesce(nullif(trim(p_reason), ''), 'Gemeld'), 200))
  on conflict do nothing;
  select count(*) into n from public.community_reports where kind = p_kind and target_id = p_id;
  if p_kind = 'run' then
    update public.run_shares set report_count = n, hidden = hidden or n >= 3 or public._cm_is_mod(uid) where id = p_id;
  else
    update public.run_comments set report_count = n, hidden = hidden or n >= 3 or public._cm_is_mod(uid) where id = p_id;
  end if;
end;
$$;

-- Verwijderen: eigen run of reactie; reacties ook onder je eigen run; moderator alles.
create or replace function public.social_delete(p_kind text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  if p_kind = 'run' then
    delete from public.run_shares where id = p_id and (user_id = uid or public._cm_is_mod(uid));
  else
    delete from public.run_comments c where c.id = p_id and (c.user_id = uid or public._cm_is_mod(uid)
      or exists (select 1 from public.run_shares s where s.id = c.share_id and s.user_id = uid));
  end if;
end;
$$;

-- Blokkeren haalt nu ook het volgen aan beide kanten weg.
create or replace function public.community_block(p_nickname text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public._cm_check_member(uid);
  select user_id into other from public.community_profiles where lower(nickname) = lower(p_nickname);
  if other is null or other = uid then return; end if;
  insert into public.community_blocks (blocker, blocked) values (uid, other) on conflict do nothing;
  delete from public.community_follows where (follower = uid and followee = other) or (follower = other and followee = uid);
end;
$$;

-- Overzicht voor jou (SQL Editor): wat is er gemeld? Nu ook runs en reacties op runs.
create or replace view public.community_reported with (security_invoker = true) as
select r.kind, r.target_id, count(*) as meldingen, string_agg(distinct r.reason, ' | ') as redenen,
       coalesce(p.body, c.body, s.title, rc.body) as tekst,
       coalesce(p.hidden, c.hidden, s.hidden, rc.hidden) as verborgen, max(r.created_at) as laatste
from public.community_reports r
left join public.community_posts p on r.kind = 'post' and p.id = r.target_id
left join public.community_comments c on r.kind = 'comment' and c.id = r.target_id
left join public.run_shares s on r.kind = 'run' and s.id = r.target_id
left join public.run_comments rc on r.kind = 'run_comment' and rc.id = r.target_id
group by r.kind, r.target_id, p.body, c.body, s.title, rc.body, p.hidden, c.hidden, s.hidden, rc.hidden
order by laatste desc;
revoke all on public.community_reported from anon, authenticated;

-- Rechten ---------------------------------------------------------------------

revoke execute on function public._sr_follows(uuid, uuid), public._sr_blocked(uuid, uuid), public._sr_can_see(uuid, uuid, text),
  public._sr_user(text), public._sr_follow_state(uuid, uuid) from public, anon, authenticated;

revoke execute on function public.social_settings(), public.social_set_approve(boolean), public.social_follow(text),
  public.social_unfollow(text), public.social_answer(text, boolean), public.social_remove_follower(text),
  public.social_people(text), public.social_search(text), public.social_profile(text),
  public.social_share_run(uuid, text, text, text), public.social_unshare_run(uuid), public.social_share_of(uuid),
  public.social_feed(text, text, bigint, int), public.social_kudo(bigint), public.social_kudos_of(bigint),
  public.social_comments_of(bigint), public.social_comment(bigint, text), public.social_report(text, bigint, text),
  public.social_delete(text, bigint), public.community_block(text) from public, anon;
grant execute on function public.social_settings(), public.social_set_approve(boolean), public.social_follow(text),
  public.social_unfollow(text), public.social_answer(text, boolean), public.social_remove_follower(text),
  public.social_people(text), public.social_search(text), public.social_profile(text),
  public.social_share_run(uuid, text, text, text), public.social_unshare_run(uuid), public.social_share_of(uuid),
  public.social_feed(text, text, bigint, int), public.social_kudo(bigint), public.social_kudos_of(bigint),
  public.social_comments_of(bigint), public.social_comment(bigint, text), public.social_report(text, bigint, text),
  public.social_delete(text, bigint), public.community_block(text) to authenticated;
