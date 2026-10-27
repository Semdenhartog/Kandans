-- 0033_community_feed.sql
-- Community: berichten per onderwerp, reacties, duimpjes, melden en blokkeren.
-- Alleen voor wie meedoet aan Samen (met een bijnaam). Alleen tekst: geen foto's, links of runs/locaties
-- (minder risico op misbruik; Strava-runs worden nooit getoond).
-- Alles gaat via de functies hieronder (de tabellen zelf zijn niet direct leesbaar of schrijfbaar vanuit de app).
--
-- Moderator worden (jij):
--   insert into public.community_moderators (user_id)
--   select id from auth.users where email = 'sb.denhartog@hotmail.com';
-- Gemelde berichten bekijken:  select * from public.community_reported;
--
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run. (Na 0029_community_boards.)

create table if not exists public.community_posts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  topic text not null check (topic in ('algemeen', 'beginners', 'routes', 'wedstrijden', 'blessures', 'spullen', 'afspreken')),
  body text not null check (char_length(body) between 2 and 1000),
  created_at timestamptz not null default now(),
  hidden boolean not null default false,
  report_count int not null default 0
);
create index if not exists community_posts_topic_time on public.community_posts (topic, id desc) where not hidden;
create index if not exists community_posts_time on public.community_posts (id desc) where not hidden;

create table if not exists public.community_comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now(),
  hidden boolean not null default false,
  report_count int not null default 0
);
create index if not exists community_comments_post on public.community_comments (post_id, id);

create table if not exists public.community_likes (
  post_id bigint not null references public.community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (post_id, user_id)
);

create table if not exists public.community_reports (
  kind text not null check (kind in ('post', 'comment')),
  target_id bigint not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 200),
  created_at timestamptz not null default now(),
  primary key (kind, target_id, user_id)
);

create table if not exists public.community_blocks (
  blocker uuid not null references auth.users(id) on delete cascade,
  blocked uuid not null references auth.users(id) on delete cascade,
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

create table if not exists public.community_rules (
  user_id uuid primary key references auth.users(id) on delete cascade,
  accepted_at timestamptz not null default now()
);

create table if not exists public.community_moderators (
  user_id uuid primary key references auth.users(id) on delete cascade
);

alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_likes enable row level security;
alter table public.community_reports enable row level security;
alter table public.community_blocks enable row level security;
alter table public.community_rules enable row level security;
alter table public.community_moderators enable row level security;
revoke all on public.community_posts, public.community_comments, public.community_likes, public.community_reports,
  public.community_blocks, public.community_rules, public.community_moderators from anon, authenticated;

-- Hulpfuncties ---------------------------------------------------------------

create or replace function public._cm_nickname(uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select nickname from public.community_profiles where user_id = uid;
$$;

create or replace function public._cm_is_mod(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.community_moderators where user_id = uid);
$$;

-- Weigert links, telefoonnummers en grove woorden (eenvoudige eerste filter; melden doet de rest).
create or replace function public._cm_text_problem(t text)
returns text language plpgsql immutable as $$
declare
  l text := lower(t);
begin
  if l ~ '(https?://|www\.|\.(nl|com|be|net|org|io)(\s|/|$))' then
    return 'Links zijn (nog) niet toegestaan.';
  end if;
  if l ~ '(\+?\d[\d\s-]{8,}\d)' then
    return 'Deel geen telefoonnummers; spreek af via een bericht.';
  end if;
  if l ~ '\m(kanker|tering|tyfus|klootzak|hoer|kut|lul|neuk|fuck|shit|cunt|nigger|neger|homo|mongool)' then
    return 'Houd het vriendelijk: dit woord laten we niet toe.';
  end if;
  return null;
end;
$$;

create or replace function public._cm_check_member(uid uuid)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if uid is null then raise exception 'Log eerst in.'; end if;
  if public._cm_nickname(uid) is null then raise exception 'Doe eerst mee met Samen (kies een bijnaam).'; end if;
end;
$$;

-- Voor de app --------------------------------------------------------------

create or replace function public.community_feed(p_topic text default null, p_before bigint default null, p_limit int default 30)
returns table (id bigint, topic text, body text, created_at timestamptz, nickname text, likes int, comments int,
               liked boolean, mine boolean, can_delete boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  return query
  select p.id, p.topic, p.body, p.created_at, cp.nickname,
         (select count(*)::int from public.community_likes l where l.post_id = p.id),
         (select count(*)::int from public.community_comments c where c.post_id = p.id and not c.hidden),
         exists (select 1 from public.community_likes l where l.post_id = p.id and l.user_id = uid),
         p.user_id = uid,
         p.user_id = uid or public._cm_is_mod(uid)
  from public.community_posts p
  join public.community_profiles cp on cp.user_id = p.user_id
  where not p.hidden
    and (p_topic is null or p.topic = p_topic)
    and (p_before is null or p.id < p_before)
    and not exists (select 1 from public.community_blocks b where b.blocker = uid and b.blocked = p.user_id)
  order by p.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50);
end;
$$;

create or replace function public.community_comments_of(p_post bigint)
returns table (id bigint, body text, created_at timestamptz, nickname text, mine boolean, can_delete boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  return query
  select c.id, c.body, c.created_at, cp.nickname, c.user_id = uid, c.user_id = uid or public._cm_is_mod(uid)
  from public.community_comments c
  join public.community_profiles cp on cp.user_id = c.user_id
  where c.post_id = p_post and not c.hidden
    and not exists (select 1 from public.community_blocks b where b.blocker = uid and b.blocked = c.user_id)
  order by c.id
  limit 200;
end;
$$;

create or replace function public.community_rules_accepted()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.community_rules where user_id = auth.uid());
$$;

create or replace function public.community_accept_rules()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._cm_check_member(auth.uid());
  insert into public.community_rules (user_id) values (auth.uid()) on conflict do nothing;
end;
$$;

create or replace function public.community_post(p_topic text, p_body text)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); problem text; n int; new_id bigint;
begin
  perform public._cm_check_member(uid);
  if not exists (select 1 from public.community_rules where user_id = uid) then
    raise exception 'Lees en accepteer eerst de huisregels.';
  end if;
  problem := public._cm_text_problem(p_body);
  if problem is not null then raise exception '%', problem; end if;
  select count(*) into n from public.community_posts where user_id = uid and created_at > now() - interval '1 day';
  if n >= 10 then raise exception 'Je hebt vandaag al 10 berichten geplaatst. Morgen weer.'; end if;
  insert into public.community_posts (user_id, topic, body) values (uid, p_topic, trim(p_body)) returning community_posts.id into new_id;
  return new_id;
end;
$$;

create or replace function public.community_comment(p_post bigint, p_body text)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); problem text; n int; new_id bigint;
begin
  perform public._cm_check_member(uid);
  if not exists (select 1 from public.community_rules where user_id = uid) then
    raise exception 'Lees en accepteer eerst de huisregels.';
  end if;
  if not exists (select 1 from public.community_posts where id = p_post and not hidden) then
    raise exception 'Dit bericht bestaat niet meer.';
  end if;
  problem := public._cm_text_problem(p_body);
  if problem is not null then raise exception '%', problem; end if;
  select count(*) into n from public.community_comments where user_id = uid and created_at > now() - interval '1 day';
  if n >= 50 then raise exception 'Je hebt vandaag al 50 reacties geplaatst. Morgen weer.'; end if;
  insert into public.community_comments (post_id, user_id, body) values (p_post, uid, trim(p_body)) returning community_comments.id into new_id;
  return new_id;
end;
$$;

create or replace function public.community_like(p_post bigint)
returns boolean language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  if exists (select 1 from public.community_likes where post_id = p_post and user_id = uid) then
    delete from public.community_likes where post_id = p_post and user_id = uid;
    return false;
  end if;
  insert into public.community_likes (post_id, user_id) values (p_post, uid) on conflict do nothing;
  return true;
end;
$$;

-- Melden: na 3 meldingen (of 1 van een moderator) verdwijnt het bericht tot een moderator kijkt.
create or replace function public.community_report(p_kind text, p_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int;
begin
  perform public._cm_check_member(uid);
  insert into public.community_reports (kind, target_id, user_id, reason)
  values (p_kind, p_id, uid, left(coalesce(nullif(trim(p_reason), ''), 'Gemeld'), 200))
  on conflict do nothing;
  select count(*) into n from public.community_reports where kind = p_kind and target_id = p_id;
  if p_kind = 'post' then
    update public.community_posts set report_count = n, hidden = hidden or n >= 3 or public._cm_is_mod(uid) where id = p_id;
  else
    update public.community_comments set report_count = n, hidden = hidden or n >= 3 or public._cm_is_mod(uid) where id = p_id;
  end if;
end;
$$;

create or replace function public.community_delete(p_kind text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  if p_kind = 'post' then
    delete from public.community_posts where id = p_id and (user_id = uid or public._cm_is_mod(uid));
  else
    delete from public.community_comments where id = p_id and (user_id = uid or public._cm_is_mod(uid));
  end if;
end;
$$;

create or replace function public.community_block(p_nickname text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public._cm_check_member(uid);
  select user_id into other from public.community_profiles where lower(nickname) = lower(p_nickname);
  if other is null or other = uid then return; end if;
  insert into public.community_blocks (blocker, blocked) values (uid, other) on conflict do nothing;
end;
$$;

create or replace function public.community_unblock_all()
returns void language sql security definer set search_path = public as $$
  delete from public.community_blocks where blocker = auth.uid();
$$;

-- Overzicht voor jou (SQL Editor): wat is er gemeld?
create or replace view public.community_reported with (security_invoker = true) as
select r.kind, r.target_id, count(*) as meldingen, string_agg(distinct r.reason, ' | ') as redenen,
       coalesce(p.body, c.body) as tekst, coalesce(p.hidden, c.hidden) as verborgen, max(r.created_at) as laatste
from public.community_reports r
left join public.community_posts p on r.kind = 'post' and p.id = r.target_id
left join public.community_comments c on r.kind = 'comment' and c.id = r.target_id
group by r.kind, r.target_id, p.body, c.body, p.hidden, c.hidden
order by laatste desc;
revoke all on public.community_reported from anon, authenticated;

revoke execute on function public._cm_nickname(uuid), public._cm_is_mod(uuid), public._cm_text_problem(text),
  public._cm_check_member(uuid) from public, anon, authenticated;
revoke execute on function public.community_feed(text, bigint, int), public.community_comments_of(bigint),
  public.community_rules_accepted(), public.community_accept_rules(), public.community_post(text, text),
  public.community_comment(bigint, text), public.community_like(bigint), public.community_report(text, bigint, text),
  public.community_delete(text, bigint), public.community_block(text), public.community_unblock_all() from public, anon;
grant execute on function public.community_feed(text, bigint, int), public.community_comments_of(bigint),
  public.community_rules_accepted(), public.community_accept_rules(), public.community_post(text, text),
  public.community_comment(bigint, text), public.community_like(bigint), public.community_report(text, bigint, text),
  public.community_delete(text, bigint), public.community_block(text), public.community_unblock_all() to authenticated;
