-- FLU-38: consumption-rate reports, low-stock alerts, reorder suggestions.
-- Adds a company-wide reorder_threshold per product (nullable -- products
-- without one set never trigger a low-stock alert) and extends
-- get_smart_alerts() (FLU-35) with a fourth alert type, 'low_stock': any
-- product+location combination present in v_current_stock whose qty is at
-- or below its product's reorder_threshold.
alter table public.products add column if not exists reorder_threshold numeric;

create or replace function public.get_smart_alerts()
returns table (
  alert_type text,
  location_id uuid,
  metric_value numeric,
  threshold_value numeric,
  detail jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_waste_threshold numeric;
  v_stocktake_threshold numeric;
  v_month date;
begin
  if not coalesce(my_role() = any (array['admin', 'accountant']::user_role[]), false) then
    raise exception 'not authorized to view smart alerts';
  end if;

  select waste_alert_threshold_jod, stocktake_alert_threshold_jod
    into v_waste_threshold, v_stocktake_threshold
  from alert_settings where id = true;

  v_month := date_trunc('month', now())::date;

  return query
  select
    'hospitality'::text,
    hl.location_id,
    coalesce(sum(hr.value), 0),
    hl.limit_value,
    jsonb_build_object(
      'usage_pct', round(coalesce(sum(hr.value), 0) / hl.limit_value * 100, 1)
    )
  from hospitality_limits hl
  left join hospitality_records hr
    on hr.location_id = hl.location_id
    and hr.created_at >= v_month and hr.created_at < v_month + interval '1 month'
  where hl.month = v_month and hl.limit_value > 0
  group by hl.location_id, hl.limit_value
  having coalesce(sum(hr.value), 0) / hl.limit_value >= 0.8

  union all

  select
    'waste'::text,
    w.location_id,
    sum(w.value_lost),
    v_waste_threshold,
    jsonb_build_object('period_days', 7)
  from waste_records w
  where w.created_at >= now() - interval '7 days'
  group by w.location_id
  having sum(w.value_lost) > v_waste_threshold

  union all

  select
    'stocktake'::text,
    st.location_id,
    abs(vsl.variance * vsl.unit_cost),
    v_stocktake_threshold,
    jsonb_build_object('stocktake_id', st.id, 'product_id', vsl.product_id)
  from v_stocktake_lines vsl
  join stocktakes st on st.id = vsl.stocktake_id
  where st.status in ('submitted', 'approved')
    and vsl.variance is not null and vsl.unit_cost is not null
    and abs(vsl.variance * vsl.unit_cost) > v_stocktake_threshold

  union all

  select
    'low_stock'::text,
    vcs.location_id,
    vcs.qty,
    p.reorder_threshold,
    jsonb_build_object('product_id', p.id)
  from v_current_stock vcs
  join products p on p.id = vcs.product_id
  where p.reorder_threshold is not null
    and vcs.qty <= p.reorder_threshold;
end;
$$;

revoke all on function public.get_smart_alerts() from public, anon;
grant execute on function public.get_smart_alerts() to authenticated;
