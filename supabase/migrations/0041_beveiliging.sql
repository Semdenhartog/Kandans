-- 0041 Beveiligingsronde (pentest 9-11-2026)
--  1. Groepscodes: cryptografisch willekeurig (32 tekens, zonder 0/O en 1/I) en max. 15 pogingen per dag.
--     group_join geeft null bij een onbekende code (i.p.v. een fout), anders telt de poging niet mee.
--  2. Verborgen profielfoto's: het pad verdwijnt uit het profiel, zodat niemand de link nog krijgt.
--     Wordt de foto weer zichtbaar gemaakt, dan komt het pad terug. Bij een nieuwe foto ruimt de app het oude bestand op.
--  3. Wachtlijst: de (dode) leesregel voor ingelogden weg en max. 5 inschrijvingen per uur per IP-adres.
--  4. _cm_text_problem: vaste search_path.
-- De oude lege tabel "Waitlist" (hoofdletter) gaat weg in een apart deel (0041b).

-- ---------------------------------------------------------------- 1. groepscodes
create schema if not exists private;

create or replace function public._group_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  b bytea := extensions.gen_random_bytes(6);
  c text := '';
begin
  for i in 0..5 loop
    c := c || substr(chars, (get_byte(b, i) % 32) + 1, 1);
  end loop;
  return c;
end;
$$;
revoke all on function public._group_code() from public, anon, authenticated;

create or replace function public.group_create(p_name text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare uid uuid := auth.uid(); c text; gid bigint;
begin
  perform public._cm_check_member(uid);
  if (select count(*) from public.run_groups where owner = uid) >= 5 then
    raise exception 'Je kunt hooguit 5 groepen maken.';
  end if;
  loop
    c := public._group_code();
    exit when not exists (select 1 from public.run_groups where code = c);
  end loop;
  insert into public.run_groups (name, code, owner) values (trim(p_name), c, uid) returning id into gid;
  insert into public.run_group_members (group_id, user_id) values (gid, uid);
  return c;
end;
$$;

create table if not exists private.group_join_attempts (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null default current_date,
  attempts int not null default 1,
  primary key (user_id, day)
);
alter table private.group_join_attempts enable row level security;

create or replace function public.group_join(p_code text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare uid uuid := auth.uid(); g public.run_groups; tries int;
begin
  perform public._cm_check_member(uid);
  insert into private.group_join_attempts (user_id) values (uid)
  on conflict (user_id, day) do update set attempts = private.group_join_attempts.attempts + 1
  returning attempts into tries;
  if tries > 15 then
    raise exception 'Te veel pogingen vandaag. Probeer het morgen opnieuw.';
  end if;
  select * into g from public.run_groups where code = upper(trim(p_code));
  -- Geen exception: dan zou de telling hierboven worden teruggedraaid. De app toont bij null de melding.
  if g is null then return null; end if;
  if (select count(*) from public.run_group_members where group_id = g.id) >= 50 then
    raise exception 'Deze groep is vol (50 lopers).';
  end if;
  insert into public.run_group_members (group_id, user_id) values (g.id, uid) on conflict do nothing;
  return g.name;
end;
$$;

-- ---------------------------------------------------------------- 2. verborgen profielfoto's
create table if not exists private.hidden_avatars (
  user_id uuid primary key references auth.users (id) on delete cascade,
  photo_path text not null,
  hidden_at timestamptz not null default now()
);
alter table private.hidden_avatars enable row level security;

create or replace function public._cp_hide_photo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare kept text;
begin
  if new.photo_hidden and not coalesce(old.photo_hidden, false) and new.photo_path is not null then
    insert into private.hidden_avatars (user_id, photo_path) values (new.user_id, new.photo_path)
    on conflict (user_id) do update set photo_path = excluded.photo_path, hidden_at = now();
    new.photo_path := null;
  elsif not new.photo_hidden and coalesce(old.photo_hidden, false) and new.photo_path is null then
    delete from private.hidden_avatars where user_id = new.user_id returning photo_path into kept;
    new.photo_path := kept;
  end if;
  return new;
end;
$$;
revoke all on function public._cp_hide_photo() from public, anon, authenticated;

drop trigger if exists trg_cp_hide_photo on public.community_profiles;
create trigger trg_cp_hide_photo
  before update of photo_hidden on public.community_profiles
  for each row execute function public._cp_hide_photo();

-- Bij een nieuwe foto geeft deze functie het oude pad terug; de app verwijdert dat bestand.
-- Nu telt ook een verborgen foto mee, zodat die bij de volgende upload echt verdwijnt.
create or replace function public.social_set_photo(p_path text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare uid uuid := auth.uid(); old text; hidden text;
begin
  perform public._cm_check_member(uid);
  if p_path is not null and (p_path not like uid::text || '/%' or p_path ~ '\.\.' or char_length(p_path) > 120) then
    raise exception 'Ongeldige foto.';
  end if;
  select photo_path into old from public.community_profiles where user_id = uid;
  delete from private.hidden_avatars where user_id = uid returning photo_path into hidden;
  update public.community_profiles set photo_hidden = false, photo_path = p_path where user_id = uid;
  delete from public.profile_reports where target = uid;
  return coalesce(old, hidden);
end;
$$;

-- Al verborgen foto's (nu 0) meteen ook zo behandelen.
insert into private.hidden_avatars (user_id, photo_path)
select user_id, photo_path from public.community_profiles where photo_hidden and photo_path is not null
on conflict (user_id) do nothing;
update public.community_profiles set photo_path = null where photo_hidden and photo_path is not null;

-- ---------------------------------------------------------------- 3. wachtlijst
drop policy if exists waitlist_select_authenticated on public.waitlist;

create table if not exists private.waitlist_ip (
  ip_hash text not null,
  hour timestamptz not null,
  n int not null default 1,
  primary key (ip_hash, hour)
);
alter table private.waitlist_ip enable row level security;

create or replace function public._waitlist_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  hdr json := nullif(current_setting('request.headers', true), '')::json;
  ip text;
  h text;
  cnt int;
begin
  if hdr is null then return new; end if; -- niet via de website/API (bv. dashboard): geen limiet
  ip := coalesce(hdr ->> 'cf-connecting-ip', split_part(hdr ->> 'x-forwarded-for', ',', 1), hdr ->> 'x-real-ip');
  ip := nullif(trim(ip), '');
  if ip is null then return new; end if;
  h := encode(extensions.digest('kadans-wachtlijst:' || ip, 'sha256'), 'hex');
  insert into private.waitlist_ip (ip_hash, hour) values (h, date_trunc('hour', now()))
  on conflict (ip_hash, hour) do update set n = private.waitlist_ip.n + 1
  returning n into cnt;
  delete from private.waitlist_ip where hour < now() - interval '2 days';
  if cnt > 5 then
    raise exception 'Te veel aanmeldingen vanaf dit adres. Probeer het later opnieuw.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public._waitlist_rate_limit() from public, anon, authenticated;

drop trigger if exists trg_waitlist_rate_limit on public.waitlist;
create trigger trg_waitlist_rate_limit
  before insert on public.waitlist
  for each row execute function public._waitlist_rate_limit();

-- ---------------------------------------------------------------- 4. search_path
alter function public._cm_text_problem(text) set search_path = pg_catalog, public;
