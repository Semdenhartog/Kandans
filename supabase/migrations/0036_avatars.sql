-- 0036: eigen profielplaatje in Samen (icoon + kleur) en een omslag (seizoenslandschap).
-- Bewust geen eigen foto's: die zouden moderatie nodig hebben.

alter table public.community_profiles add column if not exists avatar_icon text
  check (avatar_icon is null or avatar_icon in
    ('run','bolt','fire','leaf','sun','moon','mountain','wave','star','heart','paw','crown','flag','tree','snow','coffee'));
alter table public.community_profiles add column if not exists avatar_color smallint
  check (avatar_color is null or avatar_color between 0 and 7);
alter table public.community_profiles add column if not exists cover text
  check (cover is null or cover in ('auto','winter','lente','zomer','hei','herfst','mist'));

-- Plaatjes van meerdere lopers tegelijk (voor lijsten). Geblokkeerde lopers worden overgeslagen.
create or replace function public.social_avatars(p_nicknames text[])
returns table (nickname text, avatar_icon text, avatar_color smallint, cover text)
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return; end if;
  return query
  select cp.nickname, cp.avatar_icon, cp.avatar_color, cp.cover
  from public.community_profiles cp
  where lower(cp.nickname) = any (select lower(n) from unnest(p_nicknames[1:200]) n)
    and not public._sr_blocked(uid, cp.user_id);
end;
$$;

create or replace function public.social_set_avatar(p_icon text, p_color smallint, p_cover text)
returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public._cm_check_member(uid);
  update public.community_profiles
     set avatar_icon = p_icon, avatar_color = p_color, cover = p_cover
   where user_id = uid;
end;
$$;

revoke all on function public.social_avatars(text[]) from public, anon;
revoke all on function public.social_set_avatar(text, smallint, text) from public, anon;
grant execute on function public.social_avatars(text[]) to authenticated;
grant execute on function public.social_set_avatar(text, smallint, text) to authenticated;
