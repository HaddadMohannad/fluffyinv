-- Per-user nav customization on top of the role-based default. Absence of
-- any rows for a profile means "use the role default" (existing
-- behavior, unchanged); once an admin grants at least one row here, that
-- becomes the exact visible-module set for that user.
--
-- This only controls what shows in navigation — it does not change what
-- the role's RLS policies allow, so granting a module here that the
-- user's role has no underlying data access to will show the tab but
-- the actions on it will still fail. Widening real permissions still
-- requires changing role or RLS, same as before.
create table public.profile_module_grants (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  module_href text not null,
  primary key (profile_id, module_href)
);

alter table public.profile_module_grants enable row level security;

create policy profile_module_grants_select on public.profile_module_grants
  for select
  using (my_role() = 'admin' or profile_id = auth.uid());

create policy profile_module_grants_admin_write on public.profile_module_grants
  for all
  using (my_role() = 'admin')
  with check (my_role() = 'admin');
