-- 0031_foutoverzicht.sql
-- Foutoverzicht voor Sem: welke fouten testers het vaakst raken, per foutmelding en appversie.
-- Alleen te bekijken in Supabase (Table Editor of SQL Editor: select * from foutoverzicht;),
-- niet via de app: de app-rollen krijgen geen toegang.
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run.

create or replace view public.foutoverzicht
with (security_invoker = true) as
select
  left(regexp_replace(message, '\s+', ' ', 'g'), 160) as fout,
  context,
  app_version,
  count(*)                    as aantal,
  count(distinct user_id)     as gebruikers,
  min(created_at)             as eerste_keer,
  max(created_at)             as laatste_keer
from public.app_errors
where created_at > now() - interval '30 days'
group by 1, 2, 3
order by aantal desc, laatste_keer desc;

revoke all on public.foutoverzicht from anon, authenticated;
