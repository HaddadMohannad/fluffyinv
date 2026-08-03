-- Security hygiene caught by get_advisors while building FLU-25:
--
-- 1. purchase_stock/record_opening_stock were still executable by the
--    `anon` role. Supabase grants EXECUTE on new public-schema functions to
--    anon/authenticated/service_role directly (not through the `public`
--    pseudo-role), so `revoke all ... from public` in the earlier
--    migrations never actually touched anon's grant. The auth check inside
--    both functions already rejects anon (my_role() is null -> coalesced
--    to false), so this was not an active data-access hole, but an
--    unauthenticated client should not be able to invoke these at all.
revoke execute on function public.purchase_stock(uuid, uuid, numeric, numeric, text) from public, anon;
revoke execute on function public.record_opening_stock(uuid, uuid, numeric, numeric, text) from public, anon;

-- 2. transfer_lines_all's WITH CHECK was literally `true`, so any
--    authenticated user could insert a transfer_lines row against ANY
--    transfer_id regardless of role or location. Mirror the USING clause
--    (same authorization already enforced for select/update/delete) so
--    inserts are checked too.
drop policy if exists transfer_lines_all on public.transfer_lines;
create policy transfer_lines_all on public.transfer_lines
  for all
  using (
    exists (
      select 1 from transfers t
      where t.id = transfer_lines.transfer_id
        and (
          my_role() = any (array['admin', 'accountant', 'warehouse_staff']::user_role[])
          or t.from_location = my_location()
          or t.to_location = my_location()
        )
    )
  )
  with check (
    exists (
      select 1 from transfers t
      where t.id = transfer_lines.transfer_id
        and (
          my_role() = any (array['admin', 'accountant', 'warehouse_staff']::user_role[])
          or t.from_location = my_location()
          or t.to_location = my_location()
        )
    )
  );

-- FLU-25: transfer screen (warehouse<->branch, branch<->branch).
--
-- Ledger rows are only ever written on completion, never on creation --
-- a transfer cancelled before the receiving side confirms it never
-- touches stock_ledger at all, so cancellation is a plain delete
-- (transfer_lines cascades). This keeps the append-only ledger honest:
-- every row in it corresponds to stock that actually moved.
--
-- unit_cost is captured fresh at completion time (not creation), using
-- the product's current company-wide avg_cost, since a transfer can sit
-- pending for a while and a purchase could move the cost in the
-- meantime. transfer_lines.unit_cost is set at creation as a display
-- estimate and overwritten with the real value once posted.
create or replace function public.create_transfer(
  p_from_location_id uuid,
  p_to_location_id uuid,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer_id uuid;
  v_line jsonb;
  v_qty numeric;
  v_product_id uuid;
begin
  if p_from_location_id is null or p_to_location_id is null then
    raise exception 'from and to locations are required';
  end if;
  if p_from_location_id = p_to_location_id then
    raise exception 'from and to locations must differ';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'at least one line is required';
  end if;

  if not coalesce(
    my_role() = any (array['admin', 'warehouse_staff']::user_role[])
    or p_from_location_id = my_location()
    or p_to_location_id = my_location(),
    false
  ) then
    raise exception 'not authorized to create a transfer between these locations';
  end if;

  insert into transfers (from_location, to_location, status, created_by)
  values (p_from_location_id, p_to_location_id, 'pending', auth.uid())
  returning id into v_transfer_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line ->> 'product_id')::uuid;
    v_qty := (v_line ->> 'qty')::numeric;

    if v_product_id is null or v_qty is null or v_qty <= 0 then
      raise exception 'each line needs a product_id and a positive qty';
    end if;

    insert into transfer_lines (transfer_id, product_id, qty, unit_cost)
    values (
      v_transfer_id,
      v_product_id,
      v_qty,
      coalesce((select avg_cost from products where id = v_product_id), 0)
    );
  end loop;

  return v_transfer_id;
end;
$$;

create or replace function public.complete_transfer(p_transfer_id uuid)
returns table (product_id uuid, qty numeric, unit_cost numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer record;
  v_line record;
  v_cost numeric;
begin
  select * into v_transfer from transfers where id = p_transfer_id for update;

  if not found then
    raise exception 'transfer % not found', p_transfer_id;
  end if;
  if v_transfer.status <> 'pending' then
    raise exception 'transfer is not pending (status = %)', v_transfer.status;
  end if;

  if not coalesce(
    my_role() = any (array['admin', 'warehouse_staff']::user_role[])
    or v_transfer.to_location = my_location(),
    false
  ) then
    raise exception 'not authorized to confirm receipt of this transfer';
  end if;

  for v_line in select * from transfer_lines where transfer_id = p_transfer_id
  loop
    select avg_cost into v_cost from products where id = v_line.product_id for update;
    v_cost := coalesce(v_cost, 0);

    insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, reference_type, reference_id, created_by)
    values (v_transfer.from_location, v_line.product_id, -v_line.qty, v_cost, 'transfer_out', 'transfer', p_transfer_id, auth.uid());

    insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, reference_type, reference_id, created_by)
    values (v_transfer.to_location, v_line.product_id, v_line.qty, v_cost, 'transfer_in', 'transfer', p_transfer_id, auth.uid());

    update transfer_lines set unit_cost = v_cost where id = v_line.id;
  end loop;

  update transfers set status = 'completed', completed_at = now() where id = p_transfer_id;

  return query
    select tl.product_id, tl.qty, tl.unit_cost
    from transfer_lines tl
    where tl.transfer_id = p_transfer_id;
end;
$$;

create or replace function public.cancel_transfer(p_transfer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer record;
begin
  select * into v_transfer from transfers where id = p_transfer_id for update;

  if not found then
    raise exception 'transfer % not found', p_transfer_id;
  end if;
  if v_transfer.status <> 'pending' then
    raise exception 'only a pending transfer can be cancelled (status = %)', v_transfer.status;
  end if;

  if not coalesce(
    my_role() = any (array['admin', 'warehouse_staff']::user_role[])
    or v_transfer.from_location = my_location()
    or v_transfer.to_location = my_location(),
    false
  ) then
    raise exception 'not authorized to cancel this transfer';
  end if;

  -- transfer_lines cascades on delete; no ledger rows exist yet for a
  -- pending transfer, so there is nothing else to reverse.
  delete from transfers where id = p_transfer_id;
end;
$$;

revoke all on function public.create_transfer(uuid, uuid, jsonb) from public, anon;
grant execute on function public.create_transfer(uuid, uuid, jsonb) to authenticated;

revoke all on function public.complete_transfer(uuid) from public, anon;
grant execute on function public.complete_transfer(uuid) to authenticated;

revoke all on function public.cancel_transfer(uuid) from public, anon;
grant execute on function public.cancel_transfer(uuid) to authenticated;
