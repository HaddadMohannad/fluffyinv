-- Evidence photos for failed audit items. Mirrors the existing
-- 'invoices' bucket pattern (private bucket, path = <location_id>/<uuid>.<ext>,
-- viewed via signed URLs) but gated on has_audit_location_access() so it
-- follows the same admin/own-location/grant rule as the rest of the
-- audit feature instead of plain my_location().
insert into storage.buckets (id, name, public) values ('audit-evidence', 'audit-evidence', false);

create policy audit_evidence_insert on storage.objects
  for insert
  with check (
    bucket_id = 'audit-evidence'
    and has_audit_location_access((storage.foldername(name))[1]::uuid)
  );

create policy audit_evidence_select on storage.objects
  for select
  using (
    bucket_id = 'audit-evidence'
    and (my_role() = 'accountant' or has_audit_location_access((storage.foldername(name))[1]::uuid))
  );
