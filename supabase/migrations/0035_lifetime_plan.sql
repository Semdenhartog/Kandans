-- ============================================================
-- 0035_lifetime_plan.sql
-- Premium kan nu ook eenmalig "voor altijd" (product lifetime in RevenueCat).
-- ('promo' komt uit 0032.) De webhook zet dan plan = 'lifetime' met current_period_end = 2999-12-31.
-- ============================================================

alter table public.subscriptions drop constraint if exists subscriptions_plan_check;
alter table public.subscriptions
  add constraint subscriptions_plan_check check (plan in ('monthly', 'yearly', 'promo', 'lifetime'));
