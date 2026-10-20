-- Trainingsschema: één rij per training. De app maakt het schema; de coach leest het mee.
create table if not exists public.plan_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_date date not null,
  kind text not null check (kind in ('easy', 'long', 'tempo', 'interval', 'race')),
  title text not null,
  description text not null default '',
  distance_meters integer,
  target_pace integer,
  intervals jsonb,
  week integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists plan_sessions_user_date on public.plan_sessions (user_id, session_date);
alter table public.plan_sessions enable row level security;
create policy "plan_sessions_select_own" on public.plan_sessions for select to authenticated using (user_id = (select auth.uid()));
create policy "plan_sessions_insert_own" on public.plan_sessions for insert to authenticated with check (user_id = (select auth.uid()));
create policy "plan_sessions_delete_own" on public.plan_sessions for delete to authenticated using (user_id = (select auth.uid()));
