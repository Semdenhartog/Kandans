-- Schoenenteller en "hoe voelde het" bij een run.
create table if not exists public.shoes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  name text not null check (length(name) between 1 and 60),
  start_km numeric not null default 0 check (start_km between 0 and 5000),
  limit_km integer not null default 700 check (limit_km between 200 and 2000),
  is_default boolean not null default false,
  retired boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_shoes_user on public.shoes(user_id);
-- Hooguit één standaardschoen per gebruiker.
create unique index if not exists uq_shoes_one_default on public.shoes(user_id) where is_default and not retired;

alter table public.shoes enable row level security;
create policy "shoes_all_own" on public.shoes
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter table public.activities
  add column if not exists shoe_id uuid references public.shoes(id) on delete set null,
  add column if not exists feel smallint check (feel between 1 and 3),
  add column if not exists note text check (length(note) <= 500);

create index if not exists idx_activities_shoe on public.activities(shoe_id);
