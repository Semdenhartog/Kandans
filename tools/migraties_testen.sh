#!/usr/bin/env bash
# Draait alle supabase/migrations achter elkaar op een lege Postgres (met kleine nepversies van Supabase-onderdelen).
# Gebruik: tools/migraties_testen.sh "postgresql://postgres@localhost:5432/postgres"
# Stopt bij de eerste fout. pg_cron/pg_net bestaan niet in gewone Postgres: daar komen nepversies voor in de plaats.
set -u
URL="${1:?geef een Postgres-adres mee}"
psql() { command psql "$URL" -v ON_ERROR_STOP=1 -q "$@"; }
psql -f - <<'SQL'
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema if not exists auth; create schema if not exists storage; create schema if not exists extensions;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}', created_at timestamptz default now());
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon') $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
create table if not exists storage.buckets (id text primary key, name text, public boolean default false, file_size_limit bigint, allowed_mime_types text[]);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, metadata jsonb);
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name, '/') $$;
create schema if not exists cron; create schema if not exists net;
create table if not exists cron.job (jobid bigserial primary key, jobname text);
create or replace function cron.schedule(a text, b text, c text default null) returns bigint language sql as $$ select 1::bigint $$;
create or replace function cron.unschedule(a text) returns boolean language sql as $$ select true $$;
create or replace function net.http_post(url text, body jsonb default null, params jsonb default null, headers jsonb default null, timeout_milliseconds int default 1000) returns bigint language sql as $$ select 1::bigint $$;
grant usage on schema auth, storage to anon, authenticated, service_role;
SQL
fail=0
for f in $(ls supabase/migrations/*.sql | sort); do
  # pg_cron/pg_net: alleen de extensieregel eruit; de nepversies hierboven nemen de aanroepen over.
  sed -E '/create extension.*(pg_cron|pg_net)/Id' "$f" > /tmp/migratie.sql
  src=/tmp/migratie.sql
  if psql -f "$src" >/tmp/migratie.log 2>&1; then echo "ok   $f"; else echo "FOUT $f"; tail -5 /tmp/migratie.log; fail=1; break; fi
done
exit $fail
