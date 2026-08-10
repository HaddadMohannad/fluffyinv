-- Match record_audit_visit's fix: without SQL defaults, PostgREST's
-- generated types mark every param required, so p_notes couldn't be
-- omitted/undefined from the client without a TS error.
create or replace function public.update_audit_visit(
  p_visit_id uuid,
  p_visit_date date default null,
  p_notes text default null,
  p_scores jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  elem jsonb;
begin
  if my_role() <> 'admin' then
    raise exception 'Only admins can edit an audit visit';
  end if;

  update audit_visits
  set visit_date = coalesce(p_visit_date, visit_date),
      notes = p_notes
  where id = p_visit_id;

  if not found then
    raise exception 'Audit visit not found';
  end if;

  for elem in select * from jsonb_array_elements(coalesce(p_scores, '[]'::jsonb))
  loop
    update audit_item_scores
    set score = nullif(elem->>'score', '')::smallint,
        note = elem->>'note'
    where id = (elem->>'id')::uuid and visit_id = p_visit_id;
  end loop;

  insert into corrective_actions (visit_id, item_id, location_id, description, status, created_by)
  select
    p_visit_id,
    ais.item_id,
    av.location_id,
    ai.label,
    'open',
    auth.uid()
  from audit_item_scores ais
  join audit_visits av on av.id = ais.visit_id
  join audit_items ai on ai.id = ais.item_id
  where ais.visit_id = p_visit_id
    and ais.score = 0
    and not exists (
      select 1 from corrective_actions ca
      where ca.visit_id = p_visit_id and ca.item_id = ais.item_id
    );
end;
$$;
