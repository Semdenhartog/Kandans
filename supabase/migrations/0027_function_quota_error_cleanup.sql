-- 0027_function_quota_error_cleanup.sql
-- 1) Daglimiet per gebruiker voor server-functies die betaalde of gelimiteerde API's aanroepen
--    (route-generator: OpenRouteService, street-photos: Mapillary).
-- 2) Foutmeldingen (app_errors) niet langer dan 60 dagen bewaren (zoals de privacyverklaring belooft).
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run.

create table if not exists private.function_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  fn text not null,
  day date not null default (now() at time zone 'Europe/Amsterdam')::date,
  n integer not null default 0,
  primary key (user_id, fn, day)
);

create or replace function public.bump_function_usage(p_user uuid, p_fn text, p_max integer)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_n integer;
begin
  insert into private.function_usage as u (user_id, fn, day, n)
  values (p_user, p_fn, (now() at time zone 'Europe/Amsterdam')::date, 1)
  on conflict (user_id, fn, day) do update set n = u.n + 1
  returning u.n into v_n;
  delete from private.function_usage
   where user_id = p_user and day < (now() at time zone 'Europe/Amsterdam')::date - 7;
  return v_n <= p_max;
end;
$$;

revoke all on function public.bump_function_usage(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.bump_function_usage(uuid, text, integer) to service_role;

create or replace function public.app_errors_prune()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  delete from public.app_errors where created_at < now() - interval '60 days';
  return null;
end;
$$;

revoke all on function public.app_errors_prune() from public, anon, authenticated;

drop trigger if exists trg_app_errors_prune on public.app_errors;
create trigger trg_app_errors_prune
  after insert on public.app_errors
  for each statement execute function public.app_errors_prune();
