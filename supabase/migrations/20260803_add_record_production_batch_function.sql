-- FLU-33: production batches (raw -> output conversion). Writes one
-- production_batches row plus two stock_ledger rows (negative input at
-- 'production_out', positive output at 'production_in') atomically, and
-- updates the output product's company-wide weighted-average avg_cost
-- the same way purchase_stock() does -- production is effectively
-- creating new stock at a cost basis, same as a purchase. The input
-- product's avg_cost is unaffected; only its quantity drops.
create or replace function public.record_production_batch(
  p_location_id uuid,
  p_input_product_id uuid,
  p_input_qty numeric,
  p_output_product_id uuid,
  p_output_qty numeric,
  p_total_cost numeric
)
returns table (
  batch_id uuid,
  input_ledger_id bigint,
  output_ledger_id bigint,
  yield_pct numeric,
  cost_per_unit numeric,
  new_output_avg_cost numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_input_avg_cost numeric;
  v_output_old_qty numeric;
  v_output_old_cost numeric;
  v_output_new_cost numeric;
  v_cost_per_unit numeric;
  v_yield_pct numeric;
  v_batch_id uuid;
  v_input_ledger_id bigint;
  v_output_ledger_id bigint;
begin
  if p_input_qty is null or p_input_qty <= 0 then
    raise exception 'input qty must be a positive number';
  end if;
  if p_output_qty is null or p_output_qty <= 0 then
    raise exception 'output qty must be a positive number';
  end if;
  if p_total_cost is null or p_total_cost < 0 then
    raise exception 'total cost must be a non-negative number';
  end if;
  if p_input_product_id = p_output_product_id then
    raise exception 'input and output products must differ';
  end if;

  -- Production is warehouse_staff's job per the vendor BRD, not
  -- branch_manager's -- unrestricted by location, same as create_transfer.
  if not coalesce(
    my_role() = any (array['admin', 'warehouse_staff']::user_role[]),
    false
  ) then
    raise exception 'not authorized to record a production batch';
  end if;

  select avg_cost into v_input_avg_cost from products where id = p_input_product_id;
  if not found then
    raise exception 'input product % not found', p_input_product_id;
  end if;

  select avg_cost into v_output_old_cost
  from products
  where id = p_output_product_id
  for update;
  if not found then
    raise exception 'output product % not found', p_output_product_id;
  end if;

  select coalesce(sum(qty), 0) into v_output_old_qty
  from stock_ledger
  where product_id = p_output_product_id;

  v_cost_per_unit := p_total_cost / p_output_qty;
  v_output_new_cost := (v_output_old_qty * coalesce(v_output_old_cost, 0) + p_output_qty * v_cost_per_unit)
    / (v_output_old_qty + p_output_qty);

  -- yield_pct is a generated column (round(output_qty / input_qty * 100, 2))
  insert into production_batches (
    location_id, input_product_id, input_qty, output_product_id, output_qty, total_cost, created_by
  ) values (
    p_location_id, p_input_product_id, p_input_qty, p_output_product_id, p_output_qty, p_total_cost, auth.uid()
  ) returning id, production_batches.yield_pct into v_batch_id, v_yield_pct;

  insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, reference_type, reference_id, created_by)
  values (p_location_id, p_input_product_id, -p_input_qty, coalesce(v_input_avg_cost, 0), 'production_out', 'production', v_batch_id, auth.uid())
  returning id into v_input_ledger_id;

  insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, reference_type, reference_id, created_by)
  values (p_location_id, p_output_product_id, p_output_qty, v_cost_per_unit, 'production_in', 'production', v_batch_id, auth.uid())
  returning id into v_output_ledger_id;

  update products set avg_cost = v_output_new_cost where id = p_output_product_id;

  return query select v_batch_id, v_input_ledger_id, v_output_ledger_id, v_yield_pct, v_cost_per_unit, v_output_new_cost;
end;
$$;

revoke all on function public.record_production_batch(uuid, uuid, numeric, uuid, numeric, numeric) from public, anon;
grant execute on function public.record_production_batch(uuid, uuid, numeric, uuid, numeric, numeric) to authenticated;
