-- Aggregate every actor-tracked action across the app into one view so the
-- Users admin page can show a per-user activity log. security_invoker=true
-- means it naturally inherits each underlying table's own RLS instead of
-- needing new security logic here.
create or replace view public.v_user_activity_log
with (security_invoker = true) as
select actor_id, created_at, source_table, action, record_id, location_id, detail
from (
  select created_by as actor_id, created_at, 'stock_ledger'::text as source_table, 'created'::text as action, id::text as record_id, location_id, note as detail from public.stock_ledger
  union all
  select created_by, created_at, 'transfers', 'created', id::text, from_location, null from public.transfers
  union all
  select created_by, created_at, 'production_batches', 'created', id::text, location_id, null from public.production_batches
  union all
  select created_by, created_at, 'waste_records', 'created', id::text, location_id, reason from public.waste_records
  union all
  select created_by, created_at, 'hospitality_records', 'created', id::text, location_id, notes from public.hospitality_records
  union all
  select created_by, created_at, 'cash_counts', 'created', (location_id::text || ':' || count_date::text), location_id, null from public.cash_counts
  union all
  select created_by, created_at, 'expenses', 'created', id::text, location_id, description from public.expenses
  union all
  select created_by, created_at, 'employee_cash_transactions', 'created', id::text, location_id, note from public.employee_cash_transactions
  union all
  select created_by, created_at, 'import_mappings', 'created', id::text, null, name from public.import_mappings
  union all
  select uploaded_by, created_at, 'import_files', 'uploaded', id::text, null, filename from public.import_files
  union all
  select uploaded_by, created_at, 'supplier_invoices', 'uploaded', id::text, location_id, invoice_no from public.supplier_invoices
  union all
  select started_by, started_at, 'stocktakes', 'started', id::text, location_id, null from public.stocktakes
  union all
  select approved_by, approved_at, 'stocktakes', 'approved', id::text, location_id, null from public.stocktakes where approved_by is not null
  union all
  select closed_by, closed_at, 'day_closes', 'closed', (location_id::text || ':' || close_date::text), location_id, null from public.day_closes
  union all
  select reopened_by, reopened_at, 'day_closes', 'reopened', (location_id::text || ':' || close_date::text), location_id, reopen_reason from public.day_closes where reopened_by is not null
  union all
  select auditor_id, created_at, 'audit_visits', 'audited', id::text, location_id, notes from public.audit_visits
  union all
  select created_by, created_at, 'corrective_actions', 'created', id::text, location_id, description from public.corrective_actions
  union all
  select updated_by, updated_at, 'alert_settings', 'updated', id::text, null, null from public.alert_settings
) log
where actor_id is not null;

grant select on public.v_user_activity_log to authenticated;
