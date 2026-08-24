-- The Sales Dashboard pulled every matching sales_orders row into the
-- browser and summed them client-side. That silently broke once real
-- Foodics volume landed (~97k rows): Supabase's PostgREST caps any
-- unpaginated query at 1000 rows, so "Orders: 1000" was a truncated
-- partial sum, not the real total, for any filter matching more than
-- 1000 rows (almost any date range now). Fix: aggregate server-side --
-- GROUP BY day happens in Postgres, so only one row per day in the
-- selected range crosses the wire, never one row per order. SECURITY
-- INVOKER (the default) so the existing sales_select RLS policy still
-- applies under the caller's own role/location.
CREATE FUNCTION sales_dashboard_summary(
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT NULL,
  p_location_id uuid DEFAULT NULL,
  p_source sales_source DEFAULT NULL
)
RETURNS TABLE (
  day date,
  orders bigint,
  gross numeric,
  commission numeric,
  net numeric
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    order_date AS day,
    count(*) AS orders,
    coalesce(sum(gross), 0) AS gross,
    coalesce(sum(commission), 0) AS commission,
    coalesce(sum(net), 0) AS net
  FROM sales_orders
  WHERE (p_date_from IS NULL OR order_date >= p_date_from)
    AND (p_date_to IS NULL OR order_date <= p_date_to)
    AND (p_location_id IS NULL OR location_id = p_location_id)
    AND (p_source IS NULL OR source = p_source)
  GROUP BY order_date
  ORDER BY order_date DESC;
$$;
