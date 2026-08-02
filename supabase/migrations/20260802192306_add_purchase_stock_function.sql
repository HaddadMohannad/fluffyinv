-- Atomically records a purchase/goods-received event and recalculates
-- the product's company-wide weighted-average cost.
--
-- SECURITY DEFINER is required because branch_manager/warehouse_staff can
-- insert into stock_ledger for their own location but have no UPDATE
-- rights on products (admin-only per RLS) -- this function grants that one
-- narrow, validated operation without a blanket bypass. The authorization
-- check inside mirrors stock_ledger's actual INSERT policy exactly, so no
-- caller gets more access than they already have for ledger writes.
create or replace function public.purchase_stock(
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
  v_new_cost numeric;
  v_ledger_id bigint;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'qty must be a positive number';
  end if;
  if p_unit_cost is null or p_unit_cost < 0 then
    raise exception 'unit_cost must be a non-negative number';
  end if;

  if not (
    my_role() = 'admin'
    or (my_role() in ('branch_manager', 'warehouse_staff') and p_location_id = my_location())
  ) then
    raise exception 'not authorized to record a purchase for this location';
  end if;

  -- Lock the product row so concurrent purchases of the same product
  -- serialize instead of racing on the weighted-average calculation.
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

  v_new_cost := (v_old_qty * coalesce(v_old_cost, 0) + p_qty * p_unit_cost) / (v_old_qty + p_qty);

  insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, note, created_by)
  values (p_location_id, p_product_id, p_qty, p_unit_cost, 'purchase', p_note, auth.uid())
  returning id into v_ledger_id;

  update products set avg_cost = v_new_cost where id = p_product_id;

  return query select v_ledger_id, v_old_qty + p_qty, v_new_cost;
end;
$$;

revoke all on function public.purchase_stock(uuid, uuid, numeric, numeric, text) from public;
grant execute on function public.purchase_stock(uuid, uuid, numeric, numeric, text) to authenticated;
