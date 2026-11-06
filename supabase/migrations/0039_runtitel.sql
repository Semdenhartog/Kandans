-- 0039: eigen titel per run (punt 34). Leeg = automatische titel in de app.
alter table public.activities add column if not exists title text
  check (title is null or char_length(title) <= 80);
