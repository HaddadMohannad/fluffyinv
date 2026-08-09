-- handle_new_auth_user is a trigger function only; it must never be
-- callable directly via PostgREST. Trigger firing does not require an
-- EXECUTE grant, so this is safe.
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
