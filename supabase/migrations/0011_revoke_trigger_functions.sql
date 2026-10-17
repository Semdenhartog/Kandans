-- Triggerfuncties hoeven niet via de API aanroepbaar te zijn.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.sync_premium_status() from public, anon, authenticated;
