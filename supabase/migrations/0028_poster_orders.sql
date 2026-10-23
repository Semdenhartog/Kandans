-- 0028_poster_orders.sql
-- Routeposters laten drukken: producten (met prijs), bestellingen en een opslagmap voor de drukbestanden.
-- Uitvoeren: Supabase -> SQL Editor -> deze inhoud plakken -> Run.
--
-- Betalen gaat via Stripe (edge function poster-order), drukken en versturen via Gelato
-- (edge function stripe-webhook). Prijzen staan HIER, niet in de app: de server rekent altijd zelf.

-- 1) Formaten en prijzen. Pas prijzen en Gelato-productcodes aan in de Table Editor.
--    De Gelato-codes hieronder zijn een voorbeeld: controleer ze in je Gelato-dashboard
--    (Products -> Posters -> kies formaat en papier -> "Product UID").
create table if not exists public.poster_products (
  id text primary key,
  label text not null,
  width_mm integer not null check (width_mm > 0),
  height_mm integer not null check (height_mm > 0),
  price_cents integer not null check (price_cents >= 100),
  gelato_product_uid text not null,
  description text,
  active boolean not null default true,
  sort integer not null default 0
);

alter table public.poster_products enable row level security;
drop policy if exists poster_products_select on public.poster_products;
create policy poster_products_select on public.poster_products
  for select to authenticated using (active);

insert into public.poster_products (id, label, width_mm, height_mm, price_cents, gelato_product_uid, description, sort) values
  ('30x40', '30 × 40 cm', 300, 400, 2495, 'flat_300x400-mm-12x16-inch_200-gsm-80lb-uncoated_4-0_ver', 'Mat posterpapier, 200 g/m²', 1),
  ('50x70', '50 × 70 cm', 500, 700, 3495, 'flat_500x700-mm-20x28-inch_200-gsm-80lb-uncoated_4-0_ver', 'Mat posterpapier, 200 g/m²', 2)
on conflict (id) do nothing;

-- 2) Bestellingen. Schrijven alleen via de edge functions (service role); de gebruiker leest zijn eigen.
--    Bij account verwijderen blijft de bestelling bestaan zonder koppeling (fiscale bewaarplicht).
create table if not exists public.poster_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  product_id text not null references public.poster_products(id),
  price_cents integer not null,
  title text not null,
  style text not null,
  file_path text not null,
  shipping jsonb not null,
  status text not null default 'nieuw'
    check (status in ('nieuw', 'betaald', 'concept', 'in_productie', 'verzonden', 'geannuleerd', 'mislukt')),
  stripe_session_id text unique,
  gelato_order_id text,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_poster_orders_user on public.poster_orders(user_id, created_at desc);

alter table public.poster_orders enable row level security;
drop policy if exists poster_orders_select_own on public.poster_orders;
create policy poster_orders_select_own on public.poster_orders
  for select to authenticated using (user_id = (select auth.uid()));

drop trigger if exists trg_poster_orders_updated_at on public.poster_orders;
create trigger trg_poster_orders_updated_at before update on public.poster_orders
  for each row execute function set_updated_at();

-- 3) Drukbestanden: privé map, elke gebruiker alleen in zijn eigen submap (<user_id>/...).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('poster-files', 'poster-files', false, 31457280, array['image/png'])
on conflict (id) do nothing;

drop policy if exists poster_files_insert_own on storage.objects;
create policy poster_files_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'poster-files' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists poster_files_select_own on storage.objects;
create policy poster_files_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'poster-files' and (storage.foldername(name))[1] = (select auth.uid())::text);
