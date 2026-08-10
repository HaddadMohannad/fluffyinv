-- audit_visits/audit_item_scores were originally append-only (no
-- UPDATE/DELETE RLS policies at all — an audit trail should be hard to
-- alter by accident). The owner explicitly wants admins to be able to
-- correct or remove a visit, so these are narrow, admin-only, and go
-- through SECURITY DEFINER RPCs rather than opening the tables up to
-- direct UPDATE/DELETE from the client.

create or replace function public.update_audit_visit(
  p_visit_id uuid,
  p_visit_date date,
  p_notes text,
  p_scores jsonb default '[]'::jsonb -- [{id, score, note}]
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

  -- Any item newly scored as a fail that doesn't already have a
  -- corrective action gets one, same as record_audit_visit does when a
  -- visit is first saved.
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

revoke all on function public.update_audit_visit(uuid, date, text, jsonb) from public, anon;
grant execute on function public.update_audit_visit(uuid, date, text, jsonb) to authenticated;

create or replace function public.delete_audit_visit(p_visit_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if my_role() <> 'admin' then
    raise exception 'Only admins can delete an audit visit';
  end if;

  -- Corrective actions are real follow-up work that may already be in
  -- progress or closed — detach rather than destroy them.
  update corrective_actions set visit_id = null where visit_id = p_visit_id;
  delete from audit_item_scores where visit_id = p_visit_id;
  delete from audit_visits where id = p_visit_id;
end;
$$;

revoke all on function public.delete_audit_visit(uuid) from public, anon;
grant execute on function public.delete_audit_visit(uuid) to authenticated;
