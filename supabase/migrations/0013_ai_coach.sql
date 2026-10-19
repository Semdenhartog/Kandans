-- ============================================================
-- 0013_ai_coach.sql
-- AI-hardloopcoach: gesprekken + limieten (gratis proberen, daarna premium)
-- ============================================================

create table public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) <= 8000),
  created_at timestamptz not null default now()
);

comment on table public.coach_messages is 'Chatgeschiedenis met de AI-coach. Schrijven alleen via Edge Function "coach".';

create index idx_coach_messages_user_created
  on public.coach_messages(user_id, created_at desc);

alter table public.coach_messages enable row level security;

-- Gebruikers mogen hun eigen gesprek lezen en wissen; schrijven gaat via de server.
create policy "coach_messages_select_own"
  on public.coach_messages for select
  using (auth.uid() = user_id);

create policy "coach_messages_delete_own"
  on public.coach_messages for delete
  using (auth.uid() = user_id);

-- Limieten (aanpasbaar zonder nieuwe app-versie)
insert into public.model_config (key, value) values
  ('coach_free_questions', '3'),        -- totaal aantal gratis vragen per account
  ('coach_premium_daily_limit', '30')   -- vragen per dag voor premium
on conflict (key) do nothing;

-- Teller voor gratis vragen: telt ook als de gebruiker zijn gesprek wist.
alter table public.profiles
  add column if not exists coach_free_questions_used integer not null default 0;

-- Gebruikers mogen deze teller niet zelf aanpassen (alleen de server).
create or replace function public.protect_profile_server_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    new.coach_free_questions_used := old.coach_free_questions_used;
    new.is_premium := old.is_premium;
  end if;
  return new;
end;
$$;

create trigger trg_profiles_protect_server_fields
  before update on public.profiles
  for each row execute function public.protect_profile_server_fields();

revoke execute on function public.protect_profile_server_fields() from public, anon, authenticated;
