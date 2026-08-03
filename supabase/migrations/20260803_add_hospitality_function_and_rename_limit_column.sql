-- FLU-27: hospitality entry + monthly limit enforcement.
--
-- Per the issue's own flagged ambiguity: hospitality_limits.limit_kg is
-- renamed to limit_value and treated as a JOD monetary cap, not a literal
-- weight -- products are measured in either kg or pcs (products.unit), so
-- summing raw qty across mixed units has no coherent meaning, while
-- summing hospitality_records.value (already a JOD column) works
-- uniformly regardless of product unit. Confirmed with the client.
alter table public.hospitality_limits rename column limit_kg to limit_value;

-- Writes one stock_ledger row (movement = 'hospitality', negative qty)
-- and one hospitality_records row, atomically, after checking the
-- location's current-month usage against hospitality_limits.
--
-- Below 80%: submits normally, no warning.
-- 80-99%: submits normally; usage_pct is returned so the UI can show a
-- non-blocking warning ("you're at 85% of this month's limit").
-- >=100%: for a non-admin caller, blocks with a CONFIRMATION_REQUIRED
-- exception (no rows written) unless p_confirm_over_limit is true, so
-- the UI can show a blocking confirm dialog and resubmit once
-- acknowledged. Admins always bypass the block (the "admin override"
-- the issue calls for), matching my_role()-based checks used elsewhere
-- in this app (purchase_stock, record_opening_stock, transfers,
-- stocktakes) rather than a framework-level gate.
create or replace function public.record_hospitality(
  p_location_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_h_type hospitality_type,
  p_note text default null,
  p_confirm_over_limit boolean default false
)
returns table (
  record_id uuid,
  ledger_id bigint,
  value numeric,
  month_usage numeric,
  limit_value numeric,
  usage_pct numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avg_cost numeric;
  v_value numeric;
  v_month date;
  v_prior_usage numeric;
  v_new_usage numeric;
  v_limit numeric;
  v_pct numeric;
  v_record_id uuid;
  v_ledger_id bigint;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'qty must be a positive number';
  end if;

  if not coalesce(
    my_role() = 'admin'
    or (my_role() = 'branch_manager' and p_location_id = my_location()),
    false
  ) then
    raise exception 'not authorized to record hospitality for this location';
  end if;

  select avg_cost into v_avg_cost from products where id = p_product_id;
  if not found then
    raise exception 'product % not found', p_product_id;
  end if;
  v_value := p_qty * coalesce(v_avg_cost, 0);

  v_month := date_trunc('month', now())::date;

  select coalesce(sum(hospitality_records.value), 0) into v_prior_usage
  from hospitality_records
  where location_id = p_location_id
    and created_at >= v_month
    and created_at < v_month + interval '1 month';

  v_new_usage := v_prior_usage + v_value;

  select hospitality_limits.limit_value into v_limit
  from hospitality_limits
  where location_id = p_location_id and month = v_month;

  if v_limit is not null and v_limit > 0 then
    v_pct := v_new_usage / v_limit * 100;
    if v_pct >= 100 and my_role() <> 'admin' and not p_confirm_over_limit then
      raise exception 'CONFIRMATION_REQUIRED: this would bring the location to % percent of this month''s hospitality limit (% of % JOD)',
        round(v_pct, 1), round(v_new_usage, 3), round(v_limit, 3);
    end if;
  else
    v_pct := null;
  end if;

  insert into hospitality_records (location_id, product_id, qty, h_type, notes, value, created_by)
  values (p_location_id, p_product_id, p_qty, p_h_type, p_note, v_value, auth.uid())
  returning id into v_record_id;

  insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, reference_type, reference_id, created_by)
  values (p_location_id, p_product_id, -p_qty, coalesce(v_avg_cost, 0), 'hospitality', 'hospitality', v_record_id, auth.uid())
  returning id into v_ledger_id;

  return query select v_record_id, v_ledger_id, v_value, v_new_usage, v_limit, v_pct;
end;
$$;

revoke all on function public.record_hospitality(uuid, uuid, numeric, hospitality_type, text, boolean) from public, anon;
grant execute on function public.record_hospitality(uuid, uuid, numeric, hospitality_type, text, boolean) to authenticated;
