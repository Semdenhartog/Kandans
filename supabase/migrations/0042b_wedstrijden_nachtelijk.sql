-- 0042b Nachtelijke import van de wedstrijdkalender (10-11-2026)
-- pg_cron start elke nacht om 04:17 de edge function race-import via pg_net, met een eenmalige code
-- (geen extra geheime sleutel nodig). De functie controleert die code met race_import_claim().
-- Met de hand starten: select private.start_race_import();
-- Laatste runs bekijken: select * from private.race_import_runs order by at desc limit 10;

create extension if not exists pg_net;
create extension if not exists pg_cron;

create schema if not exists private;

create table if not exists private.race_import_nonces (
  nonce text primary key,
  created_at timestamptz not null default now()
);
create table if not exists private.race_import_seen (
  source_id text primary key,
  seen_at timestamptz not null default now()
);
create table if not exists private.race_import_runs (
  at timestamptz not null default now(),
  summary jsonb not null
);
alter table private.race_import_nonces enable row level security;
alter table private.race_import_seen enable row level security;
alter table private.race_import_runs enable row level security;

create or replace function private.start_race_import()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare n text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  delete from private.race_import_nonces where created_at < now() - interval '1 day';
  insert into private.race_import_nonces (nonce) values (n);
  return net.http_post(
    url := 'https://jdswennyfczpqblfkrxt.supabase.co/functions/v1/race-import',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-import-nonce', n),
    body := '{}'::jsonb,
    timeout_milliseconds := 300000
  );
end;
$$;
revoke all on function private.start_race_import() from public, anon, authenticated;

-- Eenmalige code inwisselen (alleen de server, binnen 15 minuten).
create or replace function public.race_import_claim(p_nonce text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare found_it boolean;
begin
  delete from private.race_import_nonces
  where nonce = p_nonce and created_at > now() - interval '15 minutes'
  returning true into found_it;
  return coalesce(found_it, false);
end;
$$;

create or replace function public.race_import_first_run()
returns boolean language sql stable security definer set search_path = ''
as $$ select not exists (select 1 from private.race_import_seen) $$;

create or replace function public.race_import_unseen(p_ids text[])
returns text[] language sql stable security definer set search_path = ''
as $$ select coalesce(array_agg(i), '{}') from unnest(p_ids) i where not exists (select 1 from private.race_import_seen s where s.source_id = i) $$;

create or replace function public.race_import_mark_seen(p_ids text[])
returns void language sql security definer set search_path = ''
as $$ insert into private.race_import_seen (source_id) select unnest(p_ids) on conflict do nothing $$;

create or replace function public.race_import_log(p_summary jsonb)
returns void language sql security definer set search_path = ''
as $$
  insert into private.race_import_runs (summary) values (p_summary);
  delete from private.race_import_runs where at < now() - interval '60 days';
$$;

-- Alleen de server (service role) mag deze aanroepen.
revoke all on function public.race_import_claim(text) from public, anon, authenticated;
revoke all on function public.race_import_first_run() from public, anon, authenticated;
revoke all on function public.race_import_unseen(text[]) from public, anon, authenticated;
revoke all on function public.race_import_mark_seen(text[]) from public, anon, authenticated;
revoke all on function public.race_import_log(jsonb) from public, anon, authenticated;
grant execute on function public.race_import_claim(text) to service_role;
grant execute on function public.race_import_first_run() to service_role;
grant execute on function public.race_import_unseen(text[]) to service_role;
grant execute on function public.race_import_mark_seen(text[]) to service_role;
grant execute on function public.race_import_log(jsonb) to service_role;

select cron.unschedule('kadans-race-import') where exists (select 1 from cron.job where jobname = 'kadans-race-import');
select cron.schedule('kadans-race-import', '17 4 * * *', 'select private.start_race_import()');
