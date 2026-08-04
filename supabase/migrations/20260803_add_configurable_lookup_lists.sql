-- FLU-30: admin-configurable bilingual lookup lists, replacing the
-- hardcoded waste-reason array and the hospitality_type Postgres enum.
--
-- One generic (list_key, code) design serves both lists and is
-- extensible to future ones without a new table per list.
create table public.lookup_lists (
  list_key text primary key,
  name_en text not null,
  name_ar text not null,
  created_at timestamptz not null default now()
);

create table public.lookup_values (
  id uuid primary key default gen_random_uuid(),
  list_key text not null references public.lookup_lists (list_key) on delete cascade,
  code text not null,
  name_en text not null,
  name_ar text not null,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (list_key, code)
);

alter table public.lookup_lists enable row level security;
alter table public.lookup_values enable row level security;

-- Read is open to every authenticated user -- any branch_manager
-- submitting a waste/hospitality entry needs the active option list.
-- Writes are admin-only, mirroring the existing hospitality_limits
-- admin-only write pattern.
create policy lookup_lists_read on public.lookup_lists
  for select using (true);
create policy lookup_lists_admin_write on public.lookup_lists
  for all using (my_role() = 'admin') with check (my_role() = 'admin');

create policy lookup_values_read on public.lookup_values
  for select using (true);
create policy lookup_values_admin_write on public.lookup_values
  for all using (my_role() = 'admin') with check (my_role() = 'admin');

insert into public.lookup_lists (list_key, name_en, name_ar) values
  ('waste_reason', 'Waste Reasons', 'أسباب الهدر'),
  ('hospitality_type', 'Hospitality Types', 'أنواع الضيافة');

insert into public.lookup_values (list_key, code, name_en, name_ar, sort_order) values
  ('waste_reason', 'expired', 'Expired', 'منتهي الصلاحية', 1),
  ('waste_reason', 'damaged', 'Damaged', 'تالف', 2),
  ('waste_reason', 'prep_error', 'Prep error', 'خطأ تحضير', 3),
  ('waste_reason', 'other', 'Other', 'أخرى', 4),
  ('hospitality_type', 'vip', 'VIP', 'كبار الشخصيات', 1),
  ('hospitality_type', 'complaint', 'Complaint', 'شكوى', 2),
  ('hospitality_type', 'staff', 'Staff', 'موظفين', 3);

-- Migrate hospitality_records.h_type off the native enum onto plain text,
-- validated at the application/RPC layer against lookup_values instead of
-- a hard Postgres type. Existing rows keep their current values verbatim.
alter table public.hospitality_records add column h_type_new text;
update public.hospitality_records set h_type_new = h_type::text;
alter table public.hospitality_records alter column h_type_new set not null;
alter table public.hospitality_records drop column h_type;
alter table public.hospitality_records rename column h_type_new to h_type;

-- record_hospitality's p_h_type changes from the enum to text, so this is
-- a new overload -- drop the old signature explicitly first.
drop function if exists public.record_hospitality(uuid, uuid, numeric, hospitality_type, text, boolean);

create or replace function public.record_hospitality(
  p_location_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_h_type text,
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

  if not exists (
    select 1 from lookup_values
    where list_key = 'hospitality_type' and code = p_h_type and active = true
  ) then
    raise exception 'invalid hospitality type: %', p_h_type;
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

revoke all on function public.record_hospitality(uuid, uuid, numeric, text, text, boolean) from public, anon;
grant execute on function public.record_hospitality(uuid, uuid, numeric, text, text, boolean) to authenticated;

-- record_waste's p_reason was already text (never an enum) -- just
-- strengthen validation from "non-empty" to "a real active lookup value".
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

  if not exists (
    select 1 from lookup_values
    where list_key = 'waste_reason' and code = p_reason and active = true
  ) then
    raise exception 'invalid waste reason: %', p_reason;
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
