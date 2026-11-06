-- 0040: profielfoto-upload repareren, loopgroep-agenda, reacties met emoji en @vermeldingen.
--
--  * Profielfoto: uploaden gaf 400. Storage heeft voor upload (upsert) ook een SELECT-regel nodig;
--    die ontbrak. Iedereen leest alleen de eigen map (openbare links werken los daarvan).
--    Grens omhoog naar 2 MB voor telefoons die het verkleinen overslaan.
--  * Loopgroep-agenda: leden plannen een groepsrun (tijd, plek, afstand) en zeggen "ik kom" / "kan niet".
--  * Snelle reacties 👏 🔥 💪 op een reactie (aan/uit per persoon).
--  * @bijnaam in een reactie: de genoemde loper krijgt een melding (alleen als hij de run mag zien).

-- Profielfoto ---------------------------------------------------------------------
update storage.buckets set file_size_limit = 2097152 where id = 'avatars';
drop policy if exists "avatars_own_select" on storage.objects;
create policy "avatars_own_select" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Loopgroep-agenda ----------------------------------------------------------------
create table if not exists public.group_runs (
  id bigint generated always as identity primary key,
  group_id bigint not null references public.run_groups(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null,
  place text check (place is null or char_length(place) <= 60),
  distance_km numeric check (distance_km is null or (distance_km > 0 and distance_km <= 100)),
  note text check (note is null or char_length(note) <= 140),
  created_at timestamptz not null default now()
);
create index if not exists group_runs_group_idx on public.group_runs (group_id, starts_at);
create table if not exists public.group_run_rsvps (
  run_id bigint not null references public.group_runs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  going boolean not null,
  updated_at timestamptz not null default now(),
  primary key (run_id, user_id)
);
alter table public.group_runs enable row level security;
alter table public.group_run_rsvps enable row level security;
-- Geen directe toegang: alles via de functies hieronder.

create or replace function public._grp_member(p_group bigint, p_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.run_group_members where group_id = p_group and user_id = p_uid);
$$;

create or replace function public.group_run_plan(p_group bigint, p_starts timestamptz, p_place text, p_km numeric, p_note text)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); new_id bigint; problem text;
begin
  if not public._grp_member(p_group, uid) then raise exception 'Je zit niet in deze groep.'; end if;
  if p_starts < now() - interval '1 hour' or p_starts > now() + interval '90 days' then
    raise exception 'Kies een moment in de komende 90 dagen.';
  end if;
  problem := public._cm_text_problem(coalesce(p_place, '') || ' ' || coalesce(p_note, ''));
  if problem is not null then raise exception '%', problem; end if;
  if (select count(*) from public.group_runs where group_id = p_group and starts_at > now()) >= 20 then
    raise exception 'Er staan al 20 groepsruns gepland.';
  end if;
  insert into public.group_runs (group_id, created_by, starts_at, place, distance_km, note)
  values (p_group, uid, p_starts, nullif(trim(coalesce(p_place, '')), ''), p_km, nullif(trim(coalesce(p_note, '')), ''))
  returning id into new_id;
  insert into public.group_run_rsvps (run_id, user_id, going) values (new_id, uid, true);
  return new_id;
end;
$$;

create or replace function public.group_runs_of(p_group bigint)
returns table (id bigint, starts_at timestamptz, place text, distance_km numeric, note text, planner text,
               going int, not_going int, going_names text[], my_answer boolean, can_delete boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if not public._grp_member(p_group, uid) then raise exception 'Je zit niet in deze groep.'; end if;
  return query
  select r.id, r.starts_at, r.place, r.distance_km, r.note, cp.nickname,
         (select count(*)::int from public.group_run_rsvps v where v.run_id = r.id and v.going),
         (select count(*)::int from public.group_run_rsvps v where v.run_id = r.id and not v.going),
         coalesce((select array_agg(p.nickname order by v.updated_at) from public.group_run_rsvps v
                   join public.community_profiles p on p.user_id = v.user_id
                   where v.run_id = r.id and v.going and not public._sr_blocked(uid, v.user_id)), '{}'),
         (select v.going from public.group_run_rsvps v where v.run_id = r.id and v.user_id = uid),
         r.created_by = uid or (select g.owner from public.run_groups g where g.id = r.group_id) = uid
  from public.group_runs r
  left join public.community_profiles cp on cp.user_id = r.created_by
  where r.group_id = p_group and r.starts_at > now() - interval '3 hours'
  order by r.starts_at
  limit 20;
end;
$$;

create or replace function public.group_run_answer(p_run bigint, p_going boolean)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); gid bigint;
begin
  select group_id into gid from public.group_runs where id = p_run;
  if gid is null or not public._grp_member(gid, uid) then raise exception 'Deze groepsrun bestaat niet (meer).'; end if;
  if p_going is null then
    delete from public.group_run_rsvps where run_id = p_run and user_id = uid;
  else
    insert into public.group_run_rsvps (run_id, user_id, going) values (p_run, uid, p_going)
    on conflict (run_id, user_id) do update set going = excluded.going, updated_at = now();
  end if;
end;
$$;

create or replace function public.group_run_delete(p_run bigint)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  delete from public.group_runs r
  where r.id = p_run
    and (r.created_by = uid or (select g.owner from public.run_groups g where g.id = r.group_id) = uid);
end;
$$;

-- Snelle reacties op reacties -----------------------------------------------------
create table if not exists public.run_comment_reactions (
  comment_id bigint not null references public.run_comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('👏', '🔥', '💪')),
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id, emoji)
);
alter table public.run_comment_reactions enable row level security;

create or replace function public.social_react(p_comment bigint, p_emoji text)
returns boolean language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record;
begin
  perform public._cm_check_member(uid);
  select rs.* into s from public.run_comments c join public.run_shares rs on rs.id = c.share_id
  where c.id = p_comment and not c.hidden and not rs.hidden;
  if s.id is null or not public._sr_can_see(uid, s.user_id, s.visibility) then raise exception 'Deze reactie is niet (meer) te zien.'; end if;
  if p_emoji not in ('👏', '🔥', '💪') then raise exception 'Onbekende reactie.'; end if;
  if exists (select 1 from public.run_comment_reactions where comment_id = p_comment and user_id = uid and emoji = p_emoji) then
    delete from public.run_comment_reactions where comment_id = p_comment and user_id = uid and emoji = p_emoji;
    return false;
  end if;
  insert into public.run_comment_reactions (comment_id, user_id, emoji) values (p_comment, uid, p_emoji);
  return true;
end;
$$;

-- Zelfde als social_comments_of, plus tellers per emoji en wat ik zelf gaf.
create or replace function public.social_comments_of2(p_share bigint)
returns table (id bigint, body text, created_at timestamptz, nickname text, mine boolean, can_delete boolean,
               reactions jsonb, my_reactions text[])
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record;
begin
  perform public._cm_check_member(uid);
  select * into s from public.run_shares where run_shares.id = p_share and not hidden;
  if s.id is null or not public._sr_can_see(uid, s.user_id, s.visibility) then return; end if;
  return query
  select c.id, c.body, c.created_at, cp.nickname, c.user_id = uid,
         c.user_id = uid or s.user_id = uid or public._cm_is_mod(uid),
         coalesce((select jsonb_object_agg(x.emoji, x.n) from (
            select r.emoji, count(*)::int as n from public.run_comment_reactions r
            where r.comment_id = c.id group by r.emoji) x), '{}'::jsonb),
         coalesce((select array_agg(r.emoji) from public.run_comment_reactions r
            where r.comment_id = c.id and r.user_id = uid), '{}')
  from public.run_comments c join public.community_profiles cp on cp.user_id = c.user_id
  where c.share_id = p_share and not c.hidden and not public._sr_blocked(uid, c.user_id)
  order by c.id limit 200;
end;
$$;

-- @vermeldingen -------------------------------------------------------------------
create table if not exists public.social_mentions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,   -- wie genoemd is
  by_user uuid not null references auth.users(id) on delete cascade,   -- wie het schreef
  share_id bigint not null references public.run_shares(id) on delete cascade,
  comment_id bigint not null references public.run_comments(id) on delete cascade,
  seen boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists social_mentions_user_idx on public.social_mentions (user_id, seen);
alter table public.social_mentions enable row level security;

create or replace function public.social_comment(p_share bigint, p_body text)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s record; problem text; n int; new_id bigint; nick text; target uuid; k int := 0;
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
  -- Vermeldingen: hooguit 5, alleen lopers die de run mogen zien en niet geblokkeerd zijn.
  for nick in select distinct m[1] from regexp_matches(p_body, '@([[:alnum:]_.-]{2,30})', 'g') as m loop
    exit when k >= 5;
    select cp.user_id into target from public.community_profiles cp where lower(cp.nickname) = lower(nick) limit 1;
    if target is not null and target <> uid
       and public._sr_can_see(target, s.user_id, s.visibility)
       and not public._sr_blocked(target, uid) then
      insert into public.social_mentions (user_id, by_user, share_id, comment_id) values (target, uid, p_share, new_id);
      k := k + 1;
    end if;
    target := null;
  end loop;
  return new_id;
end;
$$;

-- Nieuwe vermeldingen voor mij (en meteen als gezien markeren), voor de melding op de telefoon.
create or replace function public.social_mentions_new()
returns table (share_id bigint, by_nickname text, body text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  return query
  with fresh as (
    update public.social_mentions m set seen = true
    where m.user_id = uid and not m.seen
    returning m.share_id, m.by_user, m.comment_id, m.created_at
  )
  select f.share_id, cp.nickname, left(c.body, 140), f.created_at
  from fresh f
  join public.community_profiles cp on cp.user_id = f.by_user
  join public.run_comments c on c.id = f.comment_id and not c.hidden
  where not public._sr_blocked(uid, f.by_user)
  order by f.created_at desc
  limit 10;
end;
$$;

-- Rechten -------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'group_run_plan(bigint,timestamptz,text,numeric,text)', 'group_runs_of(bigint)', 'group_run_answer(bigint,boolean)',
    'group_run_delete(bigint)', 'social_react(bigint,text)', 'social_comments_of2(bigint)', 'social_comment(bigint,text)',
    'social_mentions_new()'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public._grp_member(bigint, uuid) from public, anon, authenticated;
