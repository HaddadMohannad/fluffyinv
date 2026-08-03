-- FLU-26: waste entry. Writes one stock_ledger row (movement = 'waste',
-- negative qty, cost = current weighted-average cost) and one
-- waste_records row atomically, mirroring the same shape as
-- record_hospitality/purchase_stock/record_opening_stock.
create or replace function public.record_waste(
  p_location_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_reason text
)
returns table (record_id uuid, ledger_id bigint, value_lost numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avg_cost numeric;
  v_value numeric;
  v_record_id uuid;
  v_ledger_id bigint;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'qty must be a positive number';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason is required';
  end if;

  if not coalesce(
    my_role() = 'admin'
    or (my_role() = 'branch_manager' and p_location_id = my_location()),
    false
  ) then
    raise exception 'not authorized to record waste for this location';
  end if;

  select avg_cost into v_avg_cost from products where id = p_product_id;
  if not found then
    raise exception 'product % not found', p_product_id;
  end if;
  v_value := p_qty * coalesce(v_avg_cost, 0);

  insert into waste_records (location_id, product_id, qty, reason, value_lost, created_by)
  values (p_location_id, p_product_id, p_qty, p_reason, v_value, auth.uid())
  returning id into v_record_id;

  insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, reference_type, reference_id, created_by)
  values (p_location_id, p_product_id, -p_qty, coalesce(v_avg_cost, 0), 'waste', 'waste', v_record_id, auth.uid())
  returning id into v_ledger_id;

  return query select v_record_id, v_ledger_id, v_value;
end;
$$;

revoke all on function public.record_waste(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.record_waste(uuid, uuid, numeric, text) to authenticated;
