-- 0029_community_boards.sql
-- "Samen": ranglijsten voor uitdagingen. Alleen voor wie zelf meedoet (met een bijnaam).
-- Gedeeld wordt alleen: bijnaam + totaal per ranglijst. Geen locatie, runs of gezondheidsgegevens.
-- Runs uit Strava tellen niet mee (voorwaarden van Strava: niet tonen aan andere gebruikers).
-- Schrijven en lezen gaat via de edge function "community" (service role); de app leest hier niets direct.
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run.

create table if not exists public.community_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 24),
  friend_code text not null unique check (friend_code ~ '^[A-Z0-9]{6}$'),
  created_at timestamptz not null default now()
);
create unique index if not exists community_profiles_nickname_lower on public.community_profiles (lower(nickname));

create table if not exists public.community_follows (
  follower uuid not null references auth.users(id) on delete cascade,
  followee uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);

create table if not exists public.board_entries (
  board text not null check (board ~ '^[a-z]+-[0-9]{4}(-[0-9]{2})?$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  value numeric not null default 0,
  updated_at timestamptz not null default now(),
  primary key (board, user_id)
);
create index if not exists idx_board_entries_rank on public.board_entries (board, value desc);

-- Alles dicht voor de app: RLS aan zonder policies. De edge function gebruikt de service role.
alter table public.community_profiles enable row level security;
alter table public.community_follows enable row level security;
alter table public.board_entries enable row level security;
