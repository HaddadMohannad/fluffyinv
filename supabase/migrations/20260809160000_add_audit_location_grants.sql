-- Quality Audit multi-branch access (FLU-48): lets a branch_manager-tier
-- profile audit locations beyond their own profiles.location_id, without
-- touching the user_role enum or any of the app's other RLS policies.
--
-- A new role value was considered and rejected: every existing role-gated
-- check in this app (nav items, RLS on inventory/sales/purchasing/etc.)
-- would need auditing to decide whether it should include the new role
-- too, for a need that's actually scoped to quality audits only. A grants
-- table is additive and touches nothing outside the audit_* tables.

create table audit_location_grants (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  location_id uuid not null references locations(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (profile_id, location_id)
);

create index audit_location_grants_profile_id_idx on audit_location_grants(profile_id);

alter table audit_location_grants enable row level security;

create policy audit_location_grants_select on audit_location_grants
  for select using (
    my_role() = 'admin' or profile_id = auth.uid()
  );
create policy audit_location_grants_admin_write on audit_location_grants
  for all using (my_role() = 'admin') with check (my_role() = 'admin');

-- Centralizes "can this caller audit this location" so audit_visits,
-- audit_item_scores, corrective_actions, and record_audit_visit all check
-- the same rule instead of duplicating admin-or-own-location logic.
create or replace function has_audit_location_access(p_location_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select
    my_role() = 'admin'
    or p_location_id = my_location()
    or exists (
      select 1 from audit_location_grants
      where profile_id = auth.uid() and location_id = p_location_id
    );
$$;

revoke execute on function public.has_audit_location_access(uuid) from public;
revoke execute on function public.has_audit_location_access(uuid) from anon;
grant execute on function public.has_audit_location_access(uuid) to authenticated;

-- Replace the plain admin-or-own-location policies with the grant-aware helper.
drop policy audit_visits_select on audit_visits;
drop policy audit_visits_insert on audit_visits;
create policy audit_visits_select on audit_visits
  for select using (
    my_role() = 'accountant' or has_audit_location_access(location_id)
  );
create policy audit_visits_insert on audit_visits
  for insert with check (has_audit_location_access(location_id));

drop policy audit_item_scores_select on audit_item_scores;
drop policy audit_item_scores_insert on audit_item_scores;
create policy audit_item_scores_select on audit_item_scores
  for select using (
    exists (
      select 1 from audit_visits v
      where v.id = audit_item_scores.visit_id
        and (my_role() = 'accountant' or has_audit_location_access(v.location_id))
    )
  );
create policy audit_item_scores_insert on audit_item_scores
  for insert with check (
    exists (
      select 1 from audit_visits v
      where v.id = audit_item_scores.visit_id
        and has_audit_location_access(v.location_id)
    )
  );

drop policy corrective_actions_select on corrective_actions;
drop policy corrective_actions_insert on corrective_actions;
drop policy corrective_actions_update on corrective_actions;
create policy corrective_actions_select on corrective_actions
  for select using (
    my_role() = 'accountant' or has_audit_location_access(location_id)
  );
create policy corrective_actions_insert on corrective_actions
  for insert with check (has_audit_location_access(location_id));
create policy corrective_actions_update on corrective_actions
  for update using (has_audit_location_access(location_id));

-- record_audit_visit's own explicit check mirrors the RLS insert policy;
-- keep both in sync with the same helper.
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

  return v_visit_id;
end;
$$;

revoke execute on function public.record_audit_visit(uuid, date, text, jsonb) from public;
revoke execute on function public.record_audit_visit(uuid, date, text, jsonb) from anon;
grant execute on function public.record_audit_visit(uuid, date, text, jsonb) to authenticated;
