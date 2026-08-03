-- FLU-23 shipped opening stock as a plain insert into stock_ledger, which
-- never touched products.avg_cost. That leaves the very first batch of a
-- product's stock priced at 0, and since purchase_stock() folds existing
-- ledger qty into its weighted-average calculation using products.avg_cost
-- as the "old cost", every subsequent purchase for that product would
-- permanently understate its average cost (the opening qty acts as free
-- stock in the denominator forever).
--
-- This mirrors purchase_stock()'s structure (same authorization check as
-- stock_ledger's actual INSERT policy, same row lock, same weighted-average
-- formula) but allows negative quantities so the existing "Reverse" button
-- can also keep avg_cost consistent instead of only inserting an offsetting
-- ledger row.
create or replace function public.record_opening_stock(
  p_location_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_unit_cost numeric,
  p_note text default null
)
returns table (ledger_id bigint, new_qty numeric, new_avg_cost numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_qty numeric;
  v_old_cost numeric;
  v_new_total_qty numeric;
  v_new_cost numeric;
  v_ledger_id bigint;
begin
  if p_qty is null or p_qty = 0 then
    raise exception 'qty must be nonzero';
  end if;
  if p_unit_cost is null or p_unit_cost < 0 then
    raise exception 'unit_cost must be a non-negative number';
  end if;

  if not coalesce(
    my_role() = 'admin'
    or (my_role() in ('branch_manager', 'warehouse_staff') and p_location_id = my_location()),
    false
  ) then
    raise exception 'not authorized to record opening stock for this location';
  end if;

  select avg_cost into v_old_cost
  from products
  where id = p_product_id
  for update;

  if not found then
    raise exception 'product % not found', p_product_id;
  end if;

  select coalesce(sum(qty), 0) into v_old_qty
  from stock_ledger
  where product_id = p_product_id;

  v_new_total_qty := v_old_qty + p_qty;

  -- Fully reversed back to zero stock -- no quantity left to price, so
  -- there's no meaningful weighted average left to compute.
  if v_new_total_qty = 0 then
    v_new_cost := 0;
  else
    v_new_cost := (v_old_qty * coalesce(v_old_cost, 0) + p_qty * p_unit_cost) / v_new_total_qty;
  end if;

  insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, note, created_by)
  values (p_location_id, p_product_id, p_qty, p_unit_cost, 'opening', p_note, auth.uid())
  returning id into v_ledger_id;

  update products set avg_cost = v_new_cost where id = p_product_id;

  return query select v_ledger_id, v_new_total_qty, v_new_cost;
end;
$$;

revoke all on function public.record_opening_stock(uuid, uuid, numeric, numeric, text) from public;
grant execute on function public.record_opening_stock(uuid, uuid, numeric, numeric, text) to authenticated;
