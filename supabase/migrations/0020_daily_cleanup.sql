-- NOG NIET TOEGEPAST: vraagt bevestiging in Supabase (bevat delete-opdrachten).
-- ------------------------------------------------------------
-- Dagelijks opruimen (pg_cron, 03:30 UTC).
-- ------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

create or replace function private.daily_cleanup()
returns void language sql security definer set search_path = '' as $$
  -- Live delen: na 2 dagen helemaal weg (de link werkt na 2 uur al niet meer).
  delete from public.live_shares where started_at < now() - interval '2 days';
  -- Strava-inlogpogingen die nooit zijn afgemaakt.
  delete from private.oauth_states where created_at < now() - interval '1 day';
  -- Foutmeldingen na 60 dagen.
  delete from public.app_errors where created_at < now() - interval '60 days';
$$;

revoke execute on function private.daily_cleanup() from public, anon, authenticated;

select cron.schedule('runwise-daily-cleanup', '30 3 * * *', 'select private.daily_cleanup()');
