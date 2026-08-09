-- Corrective actions log (FLU-50): what needs to happen to close a gap
-- found during a quality audit visit, who owns it, by when, and what it
-- costs. Direct table writes (not an RPC) -- this is a plain owned-record
-- log like lookup_values, not a ledger with side effects like waste/stock.

create table corrective_actions (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid references audit_visits(id) on delete set null,
  item_id uuid references audit_items(id) on delete set null,
  location_id uuid not null references locations(id),
  description text not null,
  action_required text,
  owner text,
  due_date date,
  status text not null default 'open' check (status in ('open', 'in_progress', 'closed')),
  estimated_cost numeric,
  actual_cost numeric,
  recheck_date date,
  recheck_result text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  -- mirrors the pilot workbook's rule: don't close on promise, close on a
  -- verified recheck.
  constraint corrective_actions_closed_needs_recheck
    check (status <> 'closed' or recheck_result is not null)
);

create index corrective_actions_location_id_idx on corrective_actions(location_id);
create index corrective_actions_visit_id_idx on corrective_actions(visit_id);
create index corrective_actions_status_idx on corrective_actions(status);

alter table corrective_actions enable row level security;

create policy corrective_actions_select on corrective_actions
  for select using (
    my_role() in ('admin', 'accountant') or location_id = my_location()
  );
create policy corrective_actions_insert on corrective_actions
  for insert with check (
    my_role() = 'admin' or location_id = my_location()
  );
create policy corrective_actions_update on corrective_actions
  for update using (
    my_role() = 'admin' or location_id = my_location()
  );
