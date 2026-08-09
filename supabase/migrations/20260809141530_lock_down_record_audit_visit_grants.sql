-- record_audit_visit was created with the default PUBLIC/anon EXECUTE
-- grants; every other RPC in this app (e.g. record_waste) explicitly
-- restricts to authenticated only. Match that convention.
revoke execute on function public.record_audit_visit(uuid, date, text, jsonb) from public;
revoke execute on function public.record_audit_visit(uuid, date, text, jsonb) from anon;
grant execute on function public.record_audit_visit(uuid, date, text, jsonb) to authenticated;
