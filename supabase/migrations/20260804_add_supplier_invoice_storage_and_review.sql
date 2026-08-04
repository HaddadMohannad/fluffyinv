-- FLU-36: supplier & invoice management. suppliers/supplier_invoices
-- tables + their row RLS already exist from the initial schema
-- (currently empty, no UI, no storage bucket). This adds:
--   - a private "invoices" Storage bucket for uploaded invoice files,
--     path convention {location_id}/{uuid}.{ext}
--   - storage.objects RLS mirroring supplier_invoices' own row policies
--     (admin/accountant unrestricted, others scoped to their own
--     location's folder)
--   - review_supplier_invoice() RPC for the approve/reject action, with
--     its own explicit admin/accountant auth check -- fully testable via
--     rollback-transaction, unlike the plain-RLS insert paths (supplier
--     CRUD, invoice upload) that this story otherwise relies on and
--     which the sandbox's rolbypassrls=true connection can't verify
--     (same caveat already documented for FLU-29's direct-RLS writes).

insert into storage.buckets (id, name, public)
values ('invoices', 'invoices', false);

create policy invoices_select on storage.objects
  for select
  using (
    bucket_id = 'invoices'
    and (
      my_role() = any (array['admin', 'accountant']::user_role[])
      or (storage.foldername(name))[1] = my_location()::text
    )
  );

create policy invoices_insert on storage.objects
  for insert
  with check (
    bucket_id = 'invoices'
    and (
      my_role() = 'admin'
      or (storage.foldername(name))[1] = my_location()::text
    )
  );

create or replace function public.review_supplier_invoice(
  p_invoice_id uuid,
  p_status invoice_status,
  p_review_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(my_role() = any (array['admin', 'accountant']::user_role[]), false) then
    raise exception 'not authorized to review supplier invoices';
  end if;

  if p_status not in ('approved', 'rejected') then
    raise exception 'status must be approved or rejected';
  end if;

  if not exists (select 1 from supplier_invoices where id = p_invoice_id) then
    raise exception 'invoice % not found', p_invoice_id;
  end if;

  update supplier_invoices
  set status = p_status, review_note = p_review_note, reviewed_by = auth.uid()
  where id = p_invoice_id;
end;
$$;

revoke all on function public.review_supplier_invoice(uuid, invoice_status, text) from public, anon;
grant execute on function public.review_supplier_invoice(uuid, invoice_status, text) to authenticated;
