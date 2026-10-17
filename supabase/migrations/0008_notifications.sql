-- ============================================================
-- 0008_notifications.sql
-- Pushmeldingen: device tokens + verstuurlog (dedup/debug)
-- ============================================================

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null,
  platform text not null check (platform in ('ios', 'android')),
  created_at timestamptz not null default now(),
  unique (fcm_token)
);

create index idx_device_tokens_user_id on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

create policy "device_tokens_all_own"
  on public.device_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ------------------------------------------------------------
create table public.notifications_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null check (
    notification_type in ('optimal_window_soon', 'better_than_usual', 'race_reminder', 'sync_error')
  ),
  title text not null,
  body text not null,
  related_route_id uuid references public.routes(id) on delete set null,
  sent_at timestamptz not null default now()
);

comment on table public.notifications_log is 'Log van verstuurde pushmeldingen; voorkomt dubbele meldingen binnen dezelfde dag/venster.';

create index idx_notifications_log_user_type_date
  on public.notifications_log(user_id, notification_type, sent_at desc);

alter table public.notifications_log enable row level security;

create policy "notifications_log_select_own"
  on public.notifications_log for select
  using (auth.uid() = user_id);

-- Schrijven uitsluitend via Edge Function (push-notify) met service_role.
