-- Give record_audit_visit's optional params real SQL defaults so the
-- generated TypeScript types mark them optional instead of required
-- `string` (the codegen only infers optionality from DEFAULT clauses).
create or replace function record_audit_visit(
  p_location_id uuid,
  p_visit_date date default current_date,
  p_notes text default null,
  p_scores jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_visit_id uuid;
begin
  if not coalesce(
    my_role() = 'admin' or p_location_id = my_location(),
    false
  ) then
    raise exception 'not authorized to record an audit visit for this location';
  end if;

  insert into audit_visits (location_id, auditor_id, visit_date, notes)
  values (p_location_id, auth.uid(), coalesce(p_visit_date, current_date), p_notes)
  returning id into v_visit_id;

  insert into audit_item_scores (visit_id, item_id, score, note, evidence_urls)
  select
    v_visit_id,
    (elem->>'item_id')::uuid,
    nullif(elem->>'score', '')::smallint,
    elem->>'note',
    case
      when elem->'evidence_urls' is null then null
      else array(select jsonb_array_elements_text(elem->'evidence_urls'))
    end
  from jsonb_array_elements(coalesce(p_scores, '[]'::jsonb)) as elem;

  return v_visit_id;
end;
$$;

revoke execute on function public.record_audit_visit(uuid, date, text, jsonb) from public;
revoke execute on function public.record_audit_visit(uuid, date, text, jsonb) from anon;
grant execute on function public.record_audit_visit(uuid, date, text, jsonb) to authenticated;
