-- 0043: Coach-kennisbank. De coach antwoordt eerst uit deze kennis (gratis, geen AI).
-- Alleen als niets goed past gaat de vraag naar Claude; dat antwoord komt daarna (algemeen
-- gemaakt, zonder persoonsgegevens) in de kennis, zodat dezelfde vraag niet twee keer geld kost.
--
--   coach_kennis      onderwerp + antwoord (of een 'actie' = antwoord uit je eigen runs/weer)
--   coach_vragen      voorbeeldvragen per onderwerp (hierop wordt gezocht)
--   coach_onbeantwoord vragen zonder goed antwoord (zonder gebruiker), na 90 dagen weg
--   coach_admins      wie mag beheren (kadans.fit/coach-beheer.html)
--
-- Zoeken: Nederlandse woordstammen (stopwoorden eruit) met "zachte" overlap: tikfouten en
-- samenstellingen tellen half mee via trigrammen. Score 0..1 (+ bonus voor trefwoorden).

create extension if not exists pg_trgm with schema extensions;

create table if not exists public.coach_kennis (
  id bigint generated always as identity primary key,
  sleutel text unique,                       -- vaste naam voor startkennis uit de repo
  onderwerp text not null,
  categorie text not null default 'algemeen',
  antwoord text not null default '',
  actie text check (actie in ('week', 'laatste', 'maand', 'vandaag', 'kleding', 'tempo', 'wedstrijd')),
  soort text not null default 'antwoord' check (soort in ('antwoord', 'buiten', 'arts')),
  trefwoorden text[] not null default '{}',
  tref_lex text[] not null default '{}',
  bron text not null default 'kadans' check (bron in ('kadans', 'claude', 'sem')),
  nakijken boolean not null default false,
  actief boolean not null default true,
  keer_gebruikt integer not null default 0,
  gemaakt timestamptz not null default now(),
  bijgewerkt timestamptz not null default now(),
  constraint coach_kennis_antwoord check (actie is not null or length(antwoord) > 0)
);

create table if not exists public.coach_vragen (
  id bigint generated always as identity primary key,
  kennis_id bigint not null references public.coach_kennis (id) on delete cascade,
  vraag text not null,
  herkomst text not null default 'verwacht' check (herkomst in ('veelgesteld', 'verwacht', 'gebruiker', 'sem')),
  lex text[] not null default '{}',
  norm text not null default ''
);
create index if not exists coach_vragen_kennis on public.coach_vragen (kennis_id);

create table if not exists public.coach_onbeantwoord (
  id bigint generated always as identity primary key,
  norm text not null unique,
  vraag text not null,
  aantal integer not null default 1,
  beste_kennis_id bigint references public.coach_kennis (id) on delete set null,
  beste_score real,
  opgelost_kennis_id bigint references public.coach_kennis (id) on delete set null,
  genegeerd boolean not null default false,
  eerst timestamptz not null default now(),
  laatst timestamptz not null default now()
);

create table if not exists public.coach_admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

-- Bron van coach-berichten: kennis, data (eigen runs/weer), claude of onbekend.
alter table public.coach_messages add column if not exists via text not null default 'claude';

-- ---------------------------------------------------------------- hulpfuncties

-- Synoniemen en spreektaal gelijktrekken vóór het stemmen (hele woorden).
create or replace function public._coach_syn(t text)
returns text language plpgsql immutable set search_path = pg_catalog as $$
declare
  s text := ' ' || lower(coalesce(t, '')) || ' ';
  p text[];
  paren text[][] := array[
    array['eet|at|gegeten|eten|maaltijd|voeding', 'eten'],
    array['drink|dronk|gedronken|drinken', 'drinken'],
    array['zeer|pijnlijk|pijntje|pijntjes|au', 'pijn'],
    array['knieen|knieën', 'knie'],
    array['km|kms|kilometers', 'kilometer'],
    array['schoenen|schoen|sneakers|loopschoenen|hardloopschoenen|runningschoenen', 'schoen'],
    array['5k|5km|vijf kilometer', '5 kilometer'],
    array['10k|10km|tien kilometer', '10 kilometer'],
    array['halve marathon|21 km|21km|21,1', 'halve'],
    array['rennen|ren|rent|jog|joggen|jogt|jogging|run|runs|rondje|hardloop|hardlopen', 'lopen'],
    array['training|trainingen|trainen|train|traint|workout', 'training'],
    array['verkouden|verkoudheid|snotneus', 'verkouden'],
    array['heet|hitte|warmte|tropisch', 'warm'],
    array['koude|vriest|vriezen|vorst', 'koud'],
    array['tempo|pace|snelheid', 'tempo'],
    array['hartslag|hartritme|bpm', 'hartslag'],
    array['abonnement|premium|pro|betalen|kosten|kost|prijs', 'premium'],
    array['horloge|watch|smartwatch|garmin|polar|coros|suunto', 'horloge'],
    array['opzeggen|stoppen met premium|annuleren', 'opzeggen'],
    array['moe|vermoeid|uitgeput|kapot', 'moe'],
    array['ademen|ademhaling|adem|lucht', 'adem'],
    array['aantrekken|aandoen|dragen|kleding|kleren', 'aantrekken'],
    array['wc|toilet|plassen|poepen', 'toilet'],
    array['hoi|hallo|hey|hee|goedemorgen|goedemiddag|goedenavond', 'hallo'],
    array['bedankt|dankjewel|dank|thanks|merci', 'bedankt']
  ];
begin
  s := regexp_replace(s, '[^a-z0-9à-ÿ ,]+', ' ', 'g');
  foreach p slice 1 in array paren loop
    s := regexp_replace(s, '(^|[ ,])(' || p[1] || ')(?=[ ,])', '\1' || p[2], 'g');
  end loop;
  return s;
end $$;

-- Woordstammen zonder stopwoorden en zonder woorden die in bijna elke vraag staan.
create or replace function public._coach_lex(t text)
returns text[] language sql immutable set search_path = public, pg_catalog as $$
  select coalesce(array_agg(distinct w), '{}')
  from unnest(tsvector_to_array(to_tsvector('pg_catalog.dutch'::regconfig, public._coach_syn(t)))) w
  where w <> all (array['lop', 'hardlop', 'loop', 'kadan', 'coach', 'eigen', 'ga', 'gan', 'gaat', 'app', 'mag', 'kun', 'goed', 'werkt', 'doen', 'moet'])
    and length(w) > 1
$$;

create or replace function public._coach_norm(t text)
returns text language sql immutable set search_path = pg_catalog as $$
  select trim(regexp_replace(regexp_replace(lower(coalesce(t, '')), '[^a-z0-9à-ÿ ]+', ' ', 'g'), '\s+', ' ', 'g'))
$$;

create or replace function public._coach_vragen_lex() returns trigger
language plpgsql set search_path = public, pg_catalog as $$
begin
  new.lex := public._coach_lex(new.vraag);
  new.norm := public._coach_norm(new.vraag);
  return new;
end $$;
drop trigger if exists coach_vragen_lex on public.coach_vragen;
create trigger coach_vragen_lex before insert or update of vraag on public.coach_vragen
  for each row execute function public._coach_vragen_lex();

create or replace function public._coach_kennis_lex() returns trigger
language plpgsql set search_path = public, pg_catalog as $$
begin
  new.tref_lex := public._coach_lex(array_to_string(new.trefwoorden, ' '));
  new.bijgewerkt := now();
  return new;
end $$;
drop trigger if exists coach_kennis_lex on public.coach_kennis;
create trigger coach_kennis_lex before insert or update on public.coach_kennis
  for each row execute function public._coach_kennis_lex();

create or replace function public._coach_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.coach_admins where user_id = auth.uid())
$$;

-- ---------------------------------------------------------------- zoeken

-- Beste onderwerpen voor een vraag. score = zachte overlap (0..1) + 0,15 als een trefwoord raakt.
create or replace function public.coach_kennis_zoek(q text, n integer default 3)
returns table (kennis_id bigint, score real, vraag text)
language sql stable security definer set search_path = public, extensions, pg_catalog as $$
  with ql as (select public._coach_lex(q) as l, public._coach_norm(q) as nq),
  per as (
    select v.kennis_id, v.vraag, k.tref_lex, v.lex,
      (select coalesce(sum(b), 0) from (
         select max(case when x = y then 1.0
                         when least(length(x), length(y)) >= 5 and least(length(x), length(y)) * 2 >= greatest(length(x), length(y))
                              and (x like y || '%' or x like '%' || y or y like x || '%' or y like '%' || x) then 0.8
                         else greatest(extensions.similarity(x, y) - 0.15, 0) / 0.85 end) as b
         from unnest(ql.l) x cross join unnest(v.lex) y group by x) s
      ) as zacht,
      extensions.similarity(v.norm, ql.nq) as hele
    from public.coach_vragen v
    join public.coach_kennis k on k.id = v.kennis_id and k.actief
    cross join ql
    where cardinality(ql.l) > 0
  ),
  scored as (
    select p.kennis_id, p.vraag,
      greatest(
        p.zacht / greatest(cardinality(ql.l) + cardinality(p.lex) - p.zacht, 1),
        p.hele
      ) + case when p.tref_lex && ql.l then 0.15 else 0 end as score
    from per p cross join ql
  )
  select distinct on (kennis_id) kennis_id, score::real, vraag
  from scored order by kennis_id, score desc
$$;

-- Bovenstaande geeft per onderwerp de beste; dit sorteert en knipt af.
create or replace function public.coach_kennis_top(q text, n integer default 3)
returns table (kennis_id bigint, score real, vraag text, onderwerp text)
language sql stable security definer set search_path = public as $$
  select z.kennis_id, z.score, z.vraag, k.onderwerp
  from public.coach_kennis_zoek(q) z join public.coach_kennis k on k.id = z.kennis_id
  order by z.score desc, k.keer_gebruikt desc limit greatest(least(n, 10), 1)
$$;

-- ---------------------------------------------------------------- server (service_role)

create or replace function public.coach_kennis_gebruikt(kid bigint)
returns void language sql security definer set search_path = public as $$
  update public.coach_kennis set keer_gebruikt = keer_gebruikt + 1 where id = kid
$$;

create or replace function public.coach_onbeantwoord_log(q text, beste bigint, score real)
returns bigint language sql security definer set search_path = public as $$
  insert into public.coach_onbeantwoord (norm, vraag, beste_kennis_id, beste_score)
  values (left(public._coach_norm(q), 300), left(q, 600), beste, score)
  on conflict (norm) do update set aantal = coach_onbeantwoord.aantal + 1, laatst = now(),
    vraag = excluded.vraag, beste_kennis_id = excluded.beste_kennis_id, beste_score = excluded.beste_score
  returning id
$$;

-- Nieuw onderwerp uit een Claude-antwoord (algemeen gemaakt). Geeft het id terug.
create or replace function public.coach_kennis_van_claude(
  onderwerp text, categorie text, antwoord text, soort text, trefwoorden text[], vragen text[], onbeantwoord_id bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare kid bigint; v text;
begin
  insert into public.coach_kennis (onderwerp, categorie, antwoord, soort, trefwoorden, bron, nakijken)
  values (left(onderwerp, 120), left(coalesce(nullif(categorie, ''), 'algemeen'), 40), left(antwoord, 4000),
          case when soort in ('antwoord', 'buiten', 'arts') then soort else 'antwoord' end,
          coalesce(trefwoorden[1:12], '{}'), 'claude', true)
  returning id into kid;
  foreach v in array coalesce(vragen[1:6], '{}') loop
    if length(trim(v)) > 3 then
      insert into public.coach_vragen (kennis_id, vraag, herkomst) values (kid, left(trim(v), 300), 'gebruiker');
    end if;
  end loop;
  if onbeantwoord_id is not null then
    update public.coach_onbeantwoord set opgelost_kennis_id = kid where id = onbeantwoord_id;
  end if;
  return kid;
end $$;

-- ---------------------------------------------------------------- beheer (alleen coach_admins)

create or replace function public.coach_is_admin() returns boolean
language sql stable security definer set search_path = public as $$ select public._coach_is_admin() $$;

-- Opslaan vanuit de beheerpagina. j = {id?, onderwerp, categorie, antwoord, actie?, soort, trefwoorden[], vragen[], actief}
create or replace function public.coach_kennis_opslaan(j jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare kid bigint := nullif(j->>'id', '')::bigint; v text;
begin
  if not public._coach_is_admin() then raise exception 'geen beheerder'; end if;
  if kid is null then
    insert into public.coach_kennis (onderwerp, categorie, antwoord, actie, soort, trefwoorden, bron, actief)
    values (j->>'onderwerp', coalesce(nullif(j->>'categorie', ''), 'algemeen'), coalesce(j->>'antwoord', ''),
            nullif(j->>'actie', ''), coalesce(nullif(j->>'soort', ''), 'antwoord'),
            coalesce(array(select jsonb_array_elements_text(j->'trefwoorden')), '{}'), 'sem',
            coalesce((j->>'actief')::boolean, true))
    returning id into kid;
  else
    update public.coach_kennis set onderwerp = j->>'onderwerp',
      categorie = coalesce(nullif(j->>'categorie', ''), 'algemeen'), antwoord = coalesce(j->>'antwoord', ''),
      actie = nullif(j->>'actie', ''), soort = coalesce(nullif(j->>'soort', ''), 'antwoord'),
      trefwoorden = coalesce(array(select jsonb_array_elements_text(j->'trefwoorden')), '{}'),
      actief = coalesce((j->>'actief')::boolean, true), bron = 'sem', nakijken = false
    where id = kid;
  end if;
  if j ? 'vragen' then
    delete from public.coach_vragen where kennis_id = kid;
    for v in select jsonb_array_elements_text(j->'vragen') loop
      if length(trim(v)) > 2 then
        insert into public.coach_vragen (kennis_id, vraag, herkomst) values (kid, left(trim(v), 300), 'sem');
      end if;
    end loop;
  end if;
  return kid;
end $$;

-- Onbeantwoorde vraag als extra voorbeeldvraag aan een onderwerp hangen.
create or replace function public.coach_vraag_koppelen(onbeantwoord_id bigint, kid bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._coach_is_admin() then raise exception 'geen beheerder'; end if;
  insert into public.coach_vragen (kennis_id, vraag, herkomst)
    select kid, vraag, 'sem' from public.coach_onbeantwoord where id = onbeantwoord_id;
  update public.coach_onbeantwoord set opgelost_kennis_id = kid where id = onbeantwoord_id;
end $$;

-- ---------------------------------------------------------------- rechten

alter table public.coach_kennis enable row level security;
alter table public.coach_vragen enable row level security;
alter table public.coach_onbeantwoord enable row level security;
alter table public.coach_admins enable row level security;

revoke all on public.coach_kennis, public.coach_vragen, public.coach_onbeantwoord, public.coach_admins from anon, authenticated;
grant select, update, delete on public.coach_kennis to authenticated;
grant select on public.coach_vragen to authenticated;
grant select, update, delete on public.coach_onbeantwoord to authenticated;

drop policy if exists coach_kennis_admin on public.coach_kennis;
create policy coach_kennis_admin on public.coach_kennis for all to authenticated
  using (public._coach_is_admin()) with check (public._coach_is_admin());
drop policy if exists coach_vragen_admin on public.coach_vragen;
create policy coach_vragen_admin on public.coach_vragen for select to authenticated
  using (public._coach_is_admin());
drop policy if exists coach_onbeantwoord_admin on public.coach_onbeantwoord;
create policy coach_onbeantwoord_admin on public.coach_onbeantwoord for all to authenticated
  using (public._coach_is_admin()) with check (public._coach_is_admin());

revoke all on function public.coach_kennis_zoek(text, integer), public.coach_kennis_top(text, integer),
  public.coach_kennis_gebruikt(bigint), public.coach_onbeantwoord_log(text, bigint, real),
  public.coach_kennis_van_claude(text, text, text, text, text[], text[], bigint),
  public.coach_is_admin(), public.coach_kennis_opslaan(jsonb), public.coach_vraag_koppelen(bigint, bigint),
  public._coach_is_admin()
  from public, anon, authenticated;
grant execute on function public.coach_kennis_top(text, integer), public.coach_is_admin(),
  public.coach_kennis_opslaan(jsonb), public.coach_vraag_koppelen(bigint, bigint), public._coach_is_admin()
  to authenticated;
grant execute on function public.coach_kennis_zoek(text, integer), public.coach_kennis_top(text, integer),
  public.coach_kennis_gebruikt(bigint), public.coach_onbeantwoord_log(text, bigint, real),
  public.coach_kennis_van_claude(text, text, text, text, text[], text[], bigint)
  to service_role;

-- Onbeantwoorde vragen niet eindeloos bewaren.
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('kadans-coach-opruimen') where exists (select 1 from cron.job where jobname = 'kadans-coach-opruimen');
    perform cron.schedule('kadans-coach-opruimen', '23 3 * * *',
      $c$delete from public.coach_onbeantwoord where laatst < now() - interval '90 days'$c$);
  end if;
end $$;
