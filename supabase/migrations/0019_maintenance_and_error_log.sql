-- ------------------------------------------------------------
-- Snelheid: RLS-policies rekenen auth.uid() één keer per query uit
-- (in plaats van per rij), en een ontbrekende index.
-- ------------------------------------------------------------
alter policy "profiles_select_own" on public.profiles using ((select auth.uid()) = id);
alter policy "profiles_update_own" on public.profiles
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
alter policy "coach_messages_select_own" on public.coach_messages using ((select auth.uid()) = user_id);
alter policy "coach_messages_delete_own" on public.coach_messages using ((select auth.uid()) = user_id);

create index if not exists idx_oauth_states_user on private.oauth_states(user_id);

-- ------------------------------------------------------------
-- Foutenlogboek: de app meldt fouten zodat we kunnen zien wat er
-- misgaat. Gebruikers kunnen alleen schrijven, niet lezen.
-- ------------------------------------------------------------
create table if not exists public.app_errors (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  message text not null check (length(message) <= 2000),
  stack text check (length(stack) <= 8000),
  context text check (length(context) <= 200),
  app_version text check (length(app_version) <= 40),
  platform text check (length(platform) <= 40)
);

create index if not exists idx_app_errors_user_time on public.app_errors(user_id, created_at desc);

alter table public.app_errors enable row level security;

-- Alleen eigen fouten, en maximaal 100 per dag per gebruiker (tegen spam).
-- Telt via een security-definer-functie: gebruikers kunnen de tabel zelf niet lezen.
create or replace function public.app_error_quota_ok()
returns boolean language sql stable security definer set search_path = '' as $$
  select count(*) < 100 from public.app_errors e
  where e.user_id = (select auth.uid()) and e.created_at > now() - interval '1 day';
$$;
revoke execute on function public.app_error_quota_ok() from public, anon;
grant execute on function public.app_error_quota_ok() to authenticated;

create policy "app_errors_insert_own" on public.app_errors
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.app_error_quota_ok()));
