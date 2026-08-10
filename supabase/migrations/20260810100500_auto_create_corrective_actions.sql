-- Auto-create an open corrective action for every failed (score=0) item
-- when an audit visit is recorded, pre-filled with the item's label as
-- the description. Previously the auditor had to re-type this by hand
-- on the corrective actions page even though the failed item and its
-- label were already known from the checklist just submitted.
create or replace function public.record_audit_visit(p_location_id uuid, p_visit_date date default current_date, p_notes text default null, p_scores jsonb default '[]'::jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_visit_id uuid;
begin
  if not has_audit_location_access(p_location_id) then
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

  insert into corrective_actions (visit_id, item_id, location_id, description, status, created_by)
  select
    v_visit_id,
    ai.id,
    p_location_id,
    ai.label,
    'open',
    auth.uid()
  from jsonb_array_elements(coalesce(p_scores, '[]'::jsonb)) as elem
  join audit_items ai on ai.id = (elem->>'item_id')::uuid
  where nullif(elem->>'score', '')::smallint = 0;

  return v_visit_id;
end;
$$;
