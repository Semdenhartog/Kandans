-- 0044: kruisverwijzingen in de coach-kennis.
-- 'zie' = sleutels van verwante onderwerpen. De coach stelt na een antwoord een vervolgvraag over het eerste
-- verwante onderwerp en de app toont de eerste vraag van elk verwant onderwerp als tikbare suggestie.
-- Gevuld door tools/coach_kennis_naar_sql.py (uit 'zie=' in supabase/coach_kennis/*.txt, anders automatisch).
alter table public.coach_kennis add column if not exists zie text[] not null default '{}'::text[];
comment on column public.coach_kennis.zie is 'Sleutels van verwante onderwerpen (kruisverwijzingen), in volgorde van belang.';
