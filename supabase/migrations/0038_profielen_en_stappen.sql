-- 0038: rijkere profielen in Samen (eigen foto, korte bio, plaats, favoriete afstand, cijfers) en een
-- maandelijkse stappenwedstrijd met vrienden en loopgroepen (stappen uit Health Connect).
--
-- Profielfoto's (Sem koos: eigen foto mét melden en blokkeren):
--  * Bucket `avatars`, alleen jpg/png/webp tot 512 kB. Iedereen schrijft alleen in de eigen map (<user_id>/...).
--  * Melden: na 3 meldingen van verschillende lopers wordt de foto vanzelf verborgen (dan weer het icoon).
--    Een moderator kan hem terugzetten of definitief verbergen met social_mod_photo.
--  * Geblokkeerde lopers zien elkaars foto niet (zoals de rest van het profiel).
-- Stappen: alleen het maandtotaal wordt bewaard, geen dagwaarden of tijdstippen. Strava speelt hier geen rol.

-- Profiel ----------------------------------------------------------------------------
alter table public.community_profiles add column if not exists bio text
  check (bio is null or char_length(bio) <= 160);
alter table public.community_profiles add column if not exists home_area text
  check (home_area is null or char_length(home_area) <= 40);
alter table public.community_profiles add column if not exists fav_distance text
  check (fav_distance is null or fav_distance in ('5k', '10k', 'half', 'marathon', 'trail', 'ultra'));
alter table public.community_profiles add column if not exists photo_path text
  check (photo_path is null or char_length(photo_path) <= 120);
alter table public.community_profiles add column if not exists photo_hidden boolean not null default false;

create table if not exists public.profile_reports (
  target uuid not null references auth.users(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 200),
  created_at timestamptz not null default now(),
  primary key (target, user_id)
);
alter table public.profile_reports enable row level security;
revoke all on public.profile_reports from anon, authenticated;

-- Opslag voor foto's.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "avatars_own_insert" on storage.objects;
drop policy if exists "avatars_own_update" on storage.objects;
drop policy if exists "avatars_own_delete" on storage.objects;
create policy "avatars_own_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars_own_update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars_own_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Bio, plaats en favoriete afstand. Zelfde tekstfilter als in de community.
create or replace function public.social_set_profile(p_bio text, p_area text, p_fav text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); b text := nullif(trim(coalesce(p_bio, '')), ''); a text := nullif(trim(coalesce(p_area, '')), '');
  problem text;
begin
  perform public._cm_check_member(uid);
  problem := coalesce(public._cm_text_problem(coalesce(b, '')), public._cm_text_problem(coalesce(a, '')));
  if problem is not null then raise exception '%', problem; end if;
  update public.community_profiles
     set bio = left(b, 160), home_area = left(a, 40), fav_distance = nullif(p_fav, '')
   where user_id = uid;
end;
$$;

-- Foto vastleggen (na het uploaden) of weghalen (null). Een nieuwe foto begint zonder meldingen.
-- Geeft het pad van de vorige foto terug, zodat de app die kan opruimen.
create or replace function public.social_set_photo(p_path text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); old text;
begin
  perform public._cm_check_member(uid);
  if p_path is not null and (p_path not like uid::text || '/%' or p_path ~ '\.\.' or char_length(p_path) > 120) then
    raise exception 'Ongeldige foto.';
  end if;
  select photo_path into old from public.community_profiles where user_id = uid;
  update public.community_profiles set photo_path = p_path, photo_hidden = false where user_id = uid;
  delete from public.profile_reports where target = uid;
  return old;
end;
$$;

-- Profiel (foto of tekst) melden. Bij 3 meldingen verdwijnt de foto vanzelf.
create or replace function public.social_report_profile(p_nickname text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public._cm_check_member(uid);
  other := public._sr_user(p_nickname);
  if other is null or other = uid then raise exception 'Deze loper is niet gevonden.'; end if;
  insert into public.profile_reports (target, user_id, reason)
  values (other, uid, left(coalesce(nullif(trim(p_reason), ''), 'ongepast'), 200))
  on conflict do nothing;
  if (select count(*) from public.profile_reports where target = other) >= 3 then
    update public.community_profiles set photo_hidden = true where user_id = other;
  end if;
end;
$$;

-- Moderator: foto verbergen of terugzetten.
create or replace function public.social_mod_photo(p_nickname text, p_hide boolean)
returns void language plpgsql security definer set search_path = public as $$
declare other uuid := public._sr_user(p_nickname);
begin
  if not public._cm_is_mod(auth.uid()) then raise exception 'Alleen voor moderatoren.'; end if;
  update public.community_profiles set photo_hidden = p_hide where user_id = other;
  if not p_hide then delete from public.profile_reports where target = other; end if;
end;
$$;

-- Plaatjes van meerdere lopers tegelijk, nu met foto (opvolger van social_avatars).
create or replace function public.social_avatars2(p_nicknames text[])
returns table (nickname text, avatar_icon text, avatar_color smallint, cover text, photo_path text)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return; end if;
  return query
  select cp.nickname, cp.avatar_icon, cp.avatar_color, cp.cover,
         case when cp.photo_hidden and cp.user_id <> uid then null else cp.photo_path end
  from public.community_profiles cp
  where lower(cp.nickname) = any (select lower(n) from unnest(p_nicknames[1:200]) n)
    and not public._sr_blocked(uid, cp.user_id);
end;
$$;

-- Extra's voor het profielscherm: bio, plaats, favoriet, sinds wanneer, en km dit jaar/deze maand
-- (alleen eigen Kadans-runs, nooit Strava; alleen als je de runs mag zien).
create or replace function public.social_profile_extra(p_nickname text)
returns table (bio text, home_area text, fav_distance text, member_since date, year_km numeric, month_km numeric,
               month_steps int, photo_hidden boolean)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid; see boolean;
begin
  perform public._cm_check_member(uid);
  other := public._sr_user(p_nickname);
  if other is null or public._sr_blocked(uid, other) then raise exception 'Deze loper is niet gevonden.'; end if;
  select other = uid or public._sr_follows(uid, other) or not cp.approve_followers into see
  from public.community_profiles cp where cp.user_id = other;
  return query
  select cp.bio, cp.home_area, cp.fav_distance, cp.created_at::date,
         case when see then round(public._own_km(other, date_trunc('year', now()), now() + interval '1 day'), 0) end,
         case when see then round(public._own_km(other, date_trunc('month', now()), now() + interval '1 day'), 1) end,
         case when see then (select s.steps from public.step_months s
                              where s.user_id = other and s.month = date_trunc('month', now())::date) end,
         cp.photo_hidden and other = uid
  from public.community_profiles cp where cp.user_id = other;
end;
$$;

-- Stappenwedstrijd per maand -----------------------------------------------------------
create table if not exists public.step_months (
  user_id uuid not null references auth.users(id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  steps int not null check (steps between 0 and 3000000),
  updated_at timestamptz not null default now(),
  primary key (user_id, month)
);
alter table public.step_months enable row level security;
revoke all on public.step_months from anon, authenticated;

-- Maandtotaal doorgeven (alleen deze en vorige maand; hooguit ~100.000 per dag).
create or replace function public.steps_submit(p_month date, p_steps int)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m date := date_trunc('month', p_month)::date; days int;
begin
  perform public._cm_check_member(uid);
  if m not in (date_trunc('month', now())::date, (date_trunc('month', now()) - interval '1 month')::date) then
    raise exception 'Alleen deze en vorige maand.';
  end if;
  days := extract(day from (m + interval '1 month' - interval '1 day'))::int;
  if p_steps < 0 or p_steps > days * 100000 then raise exception 'Dat aantal stappen klopt niet.'; end if;
  insert into public.step_months (user_id, month, steps) values (uid, m, p_steps)
  on conflict (user_id, month) do update set steps = excluded.steps, updated_at = now();
end;
$$;

-- Ranglijst: 'friends' = jij + wie jij volgt + wie jou volgt; 'group' = leden van loopgroep p_group.
create or replace function public.steps_board(p_scope text, p_group bigint, p_month date)
returns table (nickname text, is_me boolean, steps int, rank int)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); m date := date_trunc('month', coalesce(p_month, now()::date))::date;
begin
  perform public._cm_check_member(uid);
  if p_scope = 'group' then
    if not exists (select 1 from public.run_group_members where group_id = p_group and user_id = uid) then
      raise exception 'Je zit niet in deze groep.';
    end if;
    return query
    select cp.nickname, cp.user_id = uid, coalesce(s.steps, 0),
           (rank() over (order by coalesce(s.steps, 0) desc))::int
    from public.run_group_members gm
    join public.community_profiles cp on cp.user_id = gm.user_id
    left join public.step_months s on s.user_id = gm.user_id and s.month = m
    where gm.group_id = p_group and not public._sr_blocked(uid, gm.user_id)
      and (s.user_id is not null or gm.user_id = uid)
    order by 3 desc
    limit 100;
  else
    return query
    with circle as (
      select uid as id
      union select f.followee from public.community_follows f where f.follower = uid and f.status = 'accepted'
      union select f.follower from public.community_follows f where f.followee = uid and f.status = 'accepted'
    )
    select cp.nickname, cp.user_id = uid, coalesce(s.steps, 0),
           (rank() over (order by coalesce(s.steps, 0) desc))::int
    from circle c
    join public.community_profiles cp on cp.user_id = c.id
    left join public.step_months s on s.user_id = c.id and s.month = m
    where not public._sr_blocked(uid, c.id) and (s.user_id is not null or c.id = uid)
    order by 3 desc
    limit 100;
  end if;
end;
$$;

revoke all on function public.social_set_profile(text, text, text), public.social_set_photo(text),
  public.social_report_profile(text, text), public.social_mod_photo(text, boolean), public.social_avatars2(text[]),
  public.social_profile_extra(text), public.steps_submit(date, int), public.steps_board(text, bigint, date)
  from public, anon;
grant execute on function public.social_set_profile(text, text, text), public.social_set_photo(text),
  public.social_report_profile(text, text), public.social_mod_photo(text, boolean), public.social_avatars2(text[]),
  public.social_profile_extra(text), public.steps_submit(date, int), public.steps_board(text, bigint, date)
  to authenticated;
