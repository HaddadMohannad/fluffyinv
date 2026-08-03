-- FLU-28: stocktake blind count sessions + variance report + admin approval.
--
-- "the count UI never displays system_qty to the person counting" and
-- "variance report visible to admin only" are real access-control
-- requirements, not just UI polish -- RLS is the actual security boundary
-- in this app, not framework-level gating. Row-level security alone can't
-- hide individual columns (system_qty sits in the same row a
-- branch_manager legitimately needs to read to see their own saved
-- counted_qty), so v_stocktake_lines below nulls out system_qty/variance/
-- unit_cost for anyone who isn't admin/accountant, regardless of what
-- query the client sends or what stocktake status the row is in.
alter table public.stocktake_lines add column if not exists unit_cost numeric;

-- Same WITH CHECK (true) gap as transfer_lines_all (FLU-25): any
-- authenticated user could insert a stocktake_lines row against any
-- stocktake_id. Mirror the USING clause so inserts are checked too.
drop policy if exists stl_all on public.stocktake_lines;
create policy stl_all on public.stocktake_lines
  for all
  using (
    exists (
      select 1 from stocktakes s
      where s.id = stocktake_lines.stocktake_id
        and (
          my_role() = any (array['admin', 'accountant']::user_role[])
          or s.location_id = my_location()
        )
    )
  )
  with check (
    exists (
      select 1 from stocktakes s
      where s.id = stocktake_lines.stocktake_id
        and (
          my_role() = any (array['admin', 'accountant']::user_role[])
          or s.location_id = my_location()
        )
    )
  );

create or replace view public.v_stocktake_lines
with (security_invoker = true) as
select
  id,
  stocktake_id,
  product_id,
  counted_qty,
  case when my_role() = any (array['admin', 'accountant']::user_role[]) then system_qty else null end as system_qty,
  case when my_role() = any (array['admin', 'accountant']::user_role[]) then variance else null end as variance,
  case when my_role() = any (array['admin', 'accountant']::user_role[]) then unit_cost else null end as unit_cost
from public.stocktake_lines;

create or replace view public.v_stocktake_summary
with (security_invoker = true) as
select
  st.id,
  st.location_id,
  st.status,
  st.started_at,
  st.approved_at,
  sum(vl.variance * vl.unit_cost) as total_variance_value
from public.stocktakes st
left join public.v_stocktake_lines vl on vl.stocktake_id = st.id
group by st.id, st.location_id, st.status, st.started_at, st.approved_at;

grant select on public.v_stocktake_lines to authenticated;
grant select on public.v_stocktake_summary to authenticated;

create or replace function public.start_stocktake(p_location_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stocktake_id uuid;
begin
  if not coalesce(
    my_role() = any (array['admin', 'branch_manager']::user_role[])
    and (my_role() = 'admin' or p_location_id = my_location()),
    false
  ) then
    raise exception 'not authorized to start a stocktake for this location';
  end if;

  if exists (
    select 1 from stocktakes
    where location_id = p_location_id and status in ('draft', 'submitted')
  ) then
    raise exception 'this location already has an active stocktake in progress';
  end if;

  insert into stocktakes (location_id, status, started_by)
  values (p_location_id, 'draft', auth.uid())
  returning id into v_stocktake_id;

  insert into stocktake_lines (stocktake_id, product_id, system_qty)
  select
    v_stocktake_id,
    p.id,
    coalesce(vcs.qty, 0)
  from products p
  left join v_current_stock vcs on vcs.product_id = p.id and vcs.location_id = p_location_id
  where p.active and p.type in ('raw', 'processed');

  return v_stocktake_id;
end;
$$;

create or replace function public.save_stocktake_counts(p_stocktake_id uuid, p_lines jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stocktake record;
  v_line jsonb;
  v_product_id uuid;
  v_counted_qty numeric;
begin
  select * into v_stocktake from stocktakes where id = p_stocktake_id for update;

  if not found then
    raise exception 'stocktake % not found', p_stocktake_id;
  end if;
  if v_stocktake.status <> 'draft' then
    raise exception 'counts can only be saved while the stocktake is in draft (status = %)', v_stocktake.status;
  end if;
  if not coalesce(
    my_role() = 'admin'
    or (my_role() = 'branch_manager' and v_stocktake.location_id = my_location()),
    false
  ) then
    raise exception 'not authorized to record counts for this stocktake';
  end if;

  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    v_product_id := (v_line ->> 'product_id')::uuid;
    v_counted_qty := nullif(v_line ->> 'counted_qty', '')::numeric;

    if v_product_id is null then
      raise exception 'each line needs a product_id';
    end if;
    if v_counted_qty is not null and v_counted_qty < 0 then
      raise exception 'counted_qty must not be negative';
    end if;

    update stocktake_lines
    set counted_qty = v_counted_qty
    where stocktake_id = p_stocktake_id and product_id = v_product_id;
  end loop;
end;
$$;

create or replace function public.submit_stocktake(p_stocktake_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stocktake record;
begin
  select * into v_stocktake from stocktakes where id = p_stocktake_id for update;

  if not found then
    raise exception 'stocktake % not found', p_stocktake_id;
  end if;
  if v_stocktake.status <> 'draft' then
    raise exception 'only a draft stocktake can be submitted (status = %)', v_stocktake.status;
  end if;
  if not coalesce(
    my_role() = 'admin'
    or (my_role() = 'branch_manager' and v_stocktake.location_id = my_location()),
    false
  ) then
    raise exception 'not authorized to submit this stocktake';
  end if;

  -- variance is a generated column (counted_qty - system_qty), computed
  -- automatically -- only unit_cost needs an explicit snapshot here.
  update stocktake_lines sl
  set unit_cost = p.avg_cost
  from products p
  where sl.stocktake_id = p_stocktake_id and p.id = sl.product_id;

  update stocktakes set status = 'submitted' where id = p_stocktake_id;
end;
$$;

create or replace function public.approve_stocktake(p_stocktake_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stocktake record;
  v_line record;
begin
  select * into v_stocktake from stocktakes where id = p_stocktake_id for update;

  if not found then
    raise exception 'stocktake % not found', p_stocktake_id;
  end if;
  if v_stocktake.status <> 'submitted' then
    raise exception 'only a submitted stocktake can be approved (status = %)', v_stocktake.status;
  end if;
  if not coalesce(my_role() = 'admin', false) then
    raise exception 'not authorized to approve a stocktake';
  end if;

  for v_line in
    select * from stocktake_lines
    where stocktake_id = p_stocktake_id and variance is not null and variance <> 0
  loop
    insert into stock_ledger (location_id, product_id, qty, unit_cost, movement, reference_type, reference_id, created_by)
    values (v_stocktake.location_id, v_line.product_id, v_line.variance, coalesce(v_line.unit_cost, 0), 'stocktake_adjustment', 'stocktake', p_stocktake_id, auth.uid());
  end loop;

  update stocktakes
  set status = 'approved', approved_by = auth.uid(), approved_at = now()
  where id = p_stocktake_id;
end;
$$;

revoke all on function public.start_stocktake(uuid) from public, anon;
grant execute on function public.start_stocktake(uuid) to authenticated;

revoke all on function public.save_stocktake_counts(uuid, jsonb) from public, anon;
grant execute on function public.save_stocktake_counts(uuid, jsonb) to authenticated;

revoke all on function public.submit_stocktake(uuid) from public, anon;
grant execute on function public.submit_stocktake(uuid) to authenticated;

revoke all on function public.approve_stocktake(uuid) from public, anon;
grant execute on function public.approve_stocktake(uuid) to authenticated;
