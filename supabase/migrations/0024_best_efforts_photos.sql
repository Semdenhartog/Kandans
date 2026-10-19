-- Snelste stukken binnen een run (bijv. {"1000": 245.3, "5000": 1402.0}) en foto's bij een run.
alter table public.activities add column if not exists best_efforts jsonb;
alter table public.activities add column if not exists photos text[] not null default '{}';

-- Privé opslag voor foto's bij runs: elke gebruiker alleen in de eigen map (<user_id>/...).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('run-photos', 'run-photos', false, 6291456, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "run_photos_select_own" on storage.objects for select to authenticated
  using (bucket_id = 'run-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "run_photos_insert_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'run-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "run_photos_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'run-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
