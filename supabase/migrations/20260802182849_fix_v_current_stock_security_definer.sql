-- Fixes a security bug flagged by Supabase's advisor (ERROR level): the
-- v_current_stock view was defined with the default SECURITY DEFINER
-- behavior, so it ran with the view creator's permissions instead of the
-- querying user's -- bypassing stock_ledger's RLS and letting any
-- authenticated user see every location's stock, not just their own.
--
-- Note: this is the first migration tracked in this repo. The original
-- schema.sql and migrations 002/003 referenced in the project handoff doc
-- were applied directly to the Supabase project and were never committed
-- to this repository's git history.

ALTER VIEW public.v_current_stock SET (security_invoker = true);
