alter table public.profiles
  add column username text,
  add column first_name text,
  add column last_name text,
  add column street text,
  add column house_number text,
  add column postal_code text,
  add column city text,
  add column country text not null default 'NL',
  add constraint profiles_username_format check (username is null or username ~ '^[A-Za-z0-9_-]{3,32}$');

create unique index profiles_username_lower_unique
  on public.profiles (lower(username))
  where username is not null;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  metadata jsonb := new.raw_user_meta_data;
begin
  insert into public.profiles (
    id, full_name, username, first_name, last_name, street, house_number,
    postal_code, city, country
  ) values (
    new.id,
    coalesce(nullif(trim(metadata->>'full_name'), ''), trim(concat_ws(' ', metadata->>'first_name', metadata->>'last_name'))),
    nullif(trim(metadata->>'username'), ''),
    nullif(trim(metadata->>'first_name'), ''),
    nullif(trim(metadata->>'last_name'), ''),
    nullif(trim(metadata->>'street'), ''),
    nullif(trim(metadata->>'house_number'), ''),
    nullif(trim(metadata->>'postal_code'), ''),
    nullif(trim(metadata->>'city'), ''),
    coalesce(nullif(trim(metadata->>'country'), ''), 'NL')
  );
  return new;
end;
$$;