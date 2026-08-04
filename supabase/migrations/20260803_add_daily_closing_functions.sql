-- FLU-34: daily closing report + close/reopen workflow.
--
-- day_closes only stores the close/reopen event (location_id, close_date
-- as its composite primary key); the report itself is computed live from
-- stock_ledger / hospitality_records / waste_records / sales_lines for the
-- date range, per the BRD's formula:
--   Opening + Received - Sold - Waste - Hospitality = Expected Closing
--
-- The day boundary uses the location's day_close_cutoff_time (FLU-29),
-- falling back to midnight if unset. sales_orders.order_date is a plain
-- date (no time-of-day, since it comes from Talabat/Careem CSV imports
-- with daily granularity only) -- so "Sold" is matched by calendar date
-- equality, not the cutoff-time range that the other ledger-based
-- movements use.
--
-- This story ships the report plus close/reopen tracking only. Per the
-- BRD, write-blocking enforcement on a closed day is explicitly optional
-- ("اختياري") and deferred to a follow-up story once it's clear which
-- operations should be gated and whether admin bypasses it.

create or replace function public.close_day(
  p_location_id uuid,
  p_close_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(my_role() = any (array['admin', 'accountant']::user_role[]), false) then
    raise exception 'not authorized to close a day';
  end if;

  if exists (
    select 1 from day_closes
    where location_id = p_location_id and close_date = p_close_date
  ) then
    raise exception 'this day is already closed for this location';
  end if;

  insert into day_closes (location_id, close_date, closed_by, closed_at)
  values (p_location_id, p_close_date, auth.uid(), now());
end;
$$;

revoke all on function public.close_day(uuid, date) from public, anon;
grant execute on function public.close_day(uuid, date) to authenticated;

create or replace function public.reopen_day(
  p_location_id uuid,
  p_close_date date,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(my_role() = 'admin', false) then
    raise exception 'not authorized to reopen a day';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'a reason is required to reopen a closed day';
  end if;

  if not exists (
    select 1 from day_closes
    where location_id = p_location_id and close_date = p_close_date
  ) then
    raise exception 'no close record found for this location and date';
  end if;

  update day_closes
  set reopened_by = auth.uid(), reopened_at = now(), reopen_reason = p_reason
  where location_id = p_location_id and close_date = p_close_date;
end;
$$;

revoke all on function public.reopen_day(uuid, date, text) from public, anon;
grant execute on function public.reopen_day(uuid, date, text) to authenticated;

create or replace function public.get_daily_closing_report(
  p_location_id uuid,
  p_close_date date
)
returns table (
  product_id uuid,
  opening_qty numeric,
  received_qty numeric,
  sold_qty numeric,
  waste_qty numeric,
  hospitality_qty numeric,
  expected_closing_qty numeric,
  current_qty numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cutoff time;
  v_day_start timestamp;
  v_day_end timestamp;
begin
  if not coalesce(
    my_role() = any (array['admin', 'accountant']::user_role[])
    or p_location_id = my_location(),
    false
  ) then
    raise exception 'not authorized to view this location''s closing report';
  end if;

  select l.day_close_cutoff_time into v_cutoff from locations l where l.id = p_location_id;
  v_day_start := p_close_date::timestamp + coalesce(v_cutoff, time '00:00');
  v_day_end := v_day_start + interval '1 day';

  return query
  with per_product as (
    select
      p.id as product_id,
      coalesce((
        select sum(sl.qty) from stock_ledger sl
        where sl.product_id = p.id and sl.location_id = p_location_id and sl.created_at < v_day_start
      ), 0) as opening_qty,
      coalesce((
        select sum(sl.qty) from stock_ledger sl
        where sl.product_id = p.id and sl.location_id = p_location_id
          and sl.movement in ('purchase', 'transfer_in', 'production_in')
          and sl.created_at >= v_day_start and sl.created_at < v_day_end
      ), 0) as received_qty,
      coalesce((
        select sum(sli.qty) from sales_lines sli
        join sales_orders so on so.id = sli.order_id
        where sli.product_id = p.id and so.location_id = p_location_id and so.order_date = p_close_date
      ), 0) as sold_qty,
      coalesce((
        select sum(w.qty) from waste_records w
        where w.product_id = p.id and w.location_id = p_location_id
          and w.created_at >= v_day_start and w.created_at < v_day_end
      ), 0) as waste_qty,
      coalesce((
        select sum(h.qty) from hospitality_records h
        where h.product_id = p.id and h.location_id = p_location_id
          and h.created_at >= v_day_start and h.created_at < v_day_end
      ), 0) as hospitality_qty,
      coalesce((
        select sum(sl.qty) from stock_ledger sl
        where sl.product_id = p.id and sl.location_id = p_location_id
      ), 0) as current_qty
    from products p
    where p.active = true
  )
  select
    per_product.product_id,
    per_product.opening_qty,
    per_product.received_qty,
    per_product.sold_qty,
    per_product.waste_qty,
    per_product.hospitality_qty,
    per_product.opening_qty + per_product.received_qty - per_product.sold_qty
      - per_product.waste_qty - per_product.hospitality_qty as expected_closing_qty,
    per_product.current_qty
  from per_product;
end;
$$;

revoke all on function public.get_daily_closing_report(uuid, date) from public, anon;
grant execute on function public.get_daily_closing_report(uuid, date) to authenticated;
