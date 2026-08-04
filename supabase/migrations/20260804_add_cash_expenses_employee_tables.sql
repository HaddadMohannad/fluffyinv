-- FLU-39: cash counts, expense tracking, employee advances/deductions.
-- A lightweight additive ledger, not a payroll system -- no wage
-- calculation, tax handling, or scheduling. Employees are a plain
-- roster (not auth.users/profiles), since kitchen/floor staff getting a
-- cash advance usually don't have a login.

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location_id uuid not null references public.locations (id),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.employees enable row level security;
create policy employees_admin_all on public.employees
  for all using (my_role() = 'admin') with check (my_role() = 'admin');
create policy employees_read on public.employees
  for select using (true);

-- One count per location per day -- the composite primary key itself
-- rejects a duplicate count, no extra RPC logic needed (mirrors
-- day_closes' shape, but a separate table: closing a day and counting
-- cash are independent actions).
create table public.cash_counts (
  location_id uuid not null references public.locations (id),
  count_date date not null,
  counted_amount numeric not null,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (location_id, count_date)
);

alter table public.cash_counts enable row level security;
create policy cash_counts_insert on public.cash_counts
  for insert with check (my_role() = 'admin' or location_id = my_location());
create policy cash_counts_select on public.cash_counts
  for select using (
    my_role() = any (array['admin', 'accountant']::user_role[])
    or location_id = my_location()
  );

-- Expense categories reuse the existing admin-configurable lookup-list
-- system (FLU-30) instead of a new enum or hardcoded array.
insert into public.lookup_lists (list_key, name_en, name_ar) values
  ('expense_category', 'Expense Categories', 'فئات المصاريف');

insert into public.lookup_values (list_key, code, name_en, name_ar, sort_order) values
  ('expense_category', 'utilities', 'Utilities', 'خدمات', 1),
  ('expense_category', 'rent', 'Rent', 'إيجار', 2),
  ('expense_category', 'repairs', 'Repairs & Maintenance', 'صيانة وإصلاحات', 3),
  ('expense_category', 'supplies', 'Supplies', 'مستلزمات', 4),
  ('expense_category', 'other', 'Other', 'أخرى', 5);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations (id),
  category text not null,
  amount numeric not null,
  description text,
  expense_date date not null,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.expenses enable row level security;
create policy expenses_insert on public.expenses
  for insert with check (my_role() = 'admin' or location_id = my_location());
create policy expenses_select on public.expenses
  for select using (
    my_role() = any (array['admin', 'accountant']::user_role[])
    or location_id = my_location()
  );

-- location_id is denormalized from the employee's location at transaction
-- time, matching this schema's consistent flat-RLS-column convention
-- (avoids an EXISTS-against-employees policy for every read/write).
create table public.employee_cash_transactions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id),
  location_id uuid not null references public.locations (id),
  type text not null check (type in ('advance', 'deduction')),
  amount numeric not null,
  note text,
  transaction_date date not null,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.employee_cash_transactions enable row level security;
create policy employee_cash_transactions_insert on public.employee_cash_transactions
  for insert with check (my_role() = 'admin' or location_id = my_location());
create policy employee_cash_transactions_select on public.employee_cash_transactions
  for select using (
    my_role() = any (array['admin', 'accountant']::user_role[])
    or location_id = my_location()
  );
