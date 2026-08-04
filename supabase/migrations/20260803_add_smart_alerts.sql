-- FLU-35: smart alerts (hospitality limit, waste spikes, stocktake
-- discrepancies), computed on read via a single RPC -- no notification
-- infrastructure or background job in this pass.
--
-- Waste and stocktake thresholds are fixed JOD amounts, admin-configurable
-- via the alert_settings singleton row (hospitality reuses the existing
-- 80%-of-limit threshold already used in record_hospitality()'s own
-- warning logic, so it needs no new setting).
create table public.alert_settings (
  id boolean primary key default true,
  waste_alert_threshold_jod numeric not null default 50,
  stocktake_alert_threshold_jod numeric not null default 20,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id),
  constraint alert_settings_singleton check (id)
);

insert into public.alert_settings (id) values (true);

alter table public.alert_settings enable row level security;

create policy alert_settings_read on public.alert_settings
  for select using (true);
create policy alert_settings_admin_write on public.alert_settings
  for update using (my_role() = 'admin') with check (my_role() = 'admin');

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
  -- hospitality: current-month usage vs hospitality_limits.limit_value,
  -- flagged at >=80% -- same threshold record_hospitality() already warns at
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

  -- waste: trailing 7 days' value_lost vs the fixed JOD threshold
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

  -- stocktake: any submitted/approved line whose |variance * unit_cost|
  -- exceeds the fixed JOD threshold. v_stocktake_lines already masks
  -- variance/unit_cost to null for non-admin/accountant, matching this
  -- RPC's own admin/accountant-only gate above.
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
    and abs(vsl.variance * vsl.unit_cost) > v_stocktake_threshold;
end;
$$;

revoke all on function public.get_smart_alerts() from public, anon;
grant execute on function public.get_smart_alerts() to authenticated;

-- Explicit admin-gated RPC for the write path, rather than relying solely
-- on alert_settings_admin_write's RLS -- the sandbox's rollback-transaction
-- testing connects with rolbypassrls=true, so a pure-RLS write path can't
-- be verified here the way an RPC's own auth check can (same caveat
-- documented for FLU-29's direct-RLS location writes).
create or replace function public.save_alert_settings(
  p_waste_threshold_jod numeric,
  p_stocktake_threshold_jod numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(my_role() = 'admin', false) then
    raise exception 'not authorized to update alert settings';
  end if;
  if p_waste_threshold_jod is null or p_waste_threshold_jod < 0 then
    raise exception 'waste threshold must be a non-negative number';
  end if;
  if p_stocktake_threshold_jod is null or p_stocktake_threshold_jod < 0 then
    raise exception 'stocktake threshold must be a non-negative number';
  end if;

  update alert_settings
  set waste_alert_threshold_jod = p_waste_threshold_jod,
      stocktake_alert_threshold_jod = p_stocktake_threshold_jod,
      updated_at = now(),
      updated_by = auth.uid()
  where id = true;
end;
$$;

revoke all on function public.save_alert_settings(numeric, numeric) from public, anon;
grant execute on function public.save_alert_settings(numeric, numeric) to authenticated;
