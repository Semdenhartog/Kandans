-- 0030_wachtlijst.sql
-- Wachtlijst voor de website: bezoekers laten hun e-mailadres achter (alleen toevoegen, niemand kan de lijst lezen
-- behalve jij in Supabase → Table Editor → waitlist).
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run.

create table if not exists public.waitlist (
  id bigint generated always as identity primary key,
  email text not null check (char_length(email) between 5 and 200 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  source text not null default 'website' check (char_length(source) <= 40),
  created_at timestamptz not null default now()
);
create unique index if not exists waitlist_email_lower on public.waitlist (lower(email));

alter table public.waitlist enable row level security;

-- Iedereen (ook zonder account) mag zich aanmelden; lezen, wijzigen en verwijderen kan niemand via de API.
drop policy if exists "waitlist insert" on public.waitlist;
create policy "waitlist insert" on public.waitlist
  for insert to anon, authenticated
  with check (true);

grant insert on public.waitlist to anon, authenticated;
revoke select, update, delete on public.waitlist from anon, authenticated;
