-- FLU-13: Talabat "Order Items" cell parser needs to (a) map raw item
-- names to products, remembering confirmed mappings for reuse, and (b)
-- atomically replace a sales_order's sales_lines on re-import (idempotent
-- import). sales_lines currently has no UPDATE/DELETE RLS policy at all
-- (only SELECT/INSERT), so both operations go through SECURITY DEFINER
-- RPCs rather than widening direct table RLS.

create table public.product_aliases (
  id uuid primary key default gen_random_uuid(),
  raw_name text not null unique,
  product_id uuid not null references public.products(id),
  created_at timestamptz not null default now()
);

alter table public.product_aliases enable row level security;

create policy admin_all_product_aliases on public.product_aliases
  for all to authenticated
  using (my_role() = 'admin')
  with check (my_role() = 'admin');

create policy ref_read_product_aliases on public.product_aliases
  for select to authenticated
  using (true);

-- Replaces all sales_lines for each order in the batch. p_batch shape:
-- [{ "order_id": uuid, "lines": [{ "product_id": uuid|null, "qty": numeric, "raw_item_name": text }] }, ...]
create or replace function public.replace_sales_lines(p_batch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order jsonb;
  v_line jsonb;
  v_order_id uuid;
begin
  if not coalesce(my_role() = any (array['admin', 'accountant']), false) then
    raise exception 'not authorized to replace sales lines';
  end if;

  for v_order in select * from jsonb_array_elements(p_batch)
  loop
    v_order_id := (v_order ->> 'order_id')::uuid;

    delete from sales_lines where order_id = v_order_id;

    for v_line in select * from jsonb_array_elements(v_order -> 'lines')
    loop
      insert into sales_lines (order_id, product_id, qty, raw_item_name)
      values (
        v_order_id,
        nullif(v_line ->> 'product_id', '')::uuid,
        (v_line ->> 'qty')::numeric,
        v_line ->> 'raw_item_name'
      );
    end loop;
  end loop;
end;
$$;

revoke all on function public.replace_sales_lines(jsonb) from public, anon;
grant execute on function public.replace_sales_lines(jsonb) to authenticated;

-- Upserts a raw-name -> product mapping and backfills any existing
-- unmatched sales_lines rows sharing that raw_item_name. Returns the
-- number of rows backfilled.
create or replace function public.apply_product_alias(p_raw_name text, p_product_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_backfilled integer;
begin
  if not coalesce(my_role() = 'admin', false) then
    raise exception 'not authorized to manage product aliases';
  end if;

  if p_raw_name is null or length(trim(p_raw_name)) = 0 then
    raise exception 'raw_name is required';
  end if;

  insert into product_aliases (raw_name, product_id)
  values (p_raw_name, p_product_id)
  on conflict (raw_name) do update set product_id = excluded.product_id;

  update sales_lines
  set product_id = p_product_id
  where raw_item_name = p_raw_name
    and product_id is null;
  get diagnostics v_backfilled = row_count;

  return v_backfilled;
end;
$$;

revoke all on function public.apply_product_alias(text, uuid) from public, anon;
grant execute on function public.apply_product_alias(text, uuid) to authenticated;
