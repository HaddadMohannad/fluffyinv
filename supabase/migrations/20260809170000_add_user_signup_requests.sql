-- Denormalized email on profiles so the Users admin UI can show/search email
-- without needing service-role access to auth.users.
alter table public.profiles add column email text unique;

update public.profiles p
set email = u.email
from auth.users u
where p.id = u.id and p.email is null;

-- Signup requests: one row per auth.users row that has no profile yet.
-- Created automatically by a trigger on auth.users so it works the same
-- whether the user signed up with email/password or Google OAuth.
create table public.signup_requests (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  assigned_role user_role,
  assigned_location_id uuid references public.locations (id)
);

alter table public.signup_requests enable row level security;

create policy signup_requests_select on public.signup_requests
  for select
  using (id = auth.uid() or my_role() = 'admin');

create policy signup_requests_admin_update on public.signup_requests
  for update
  using (my_role() = 'admin')
  with check (my_role() = 'admin');

-- No insert policy: rows are only ever created by handle_new_auth_user()
-- below, which runs as the table owner and so bypasses RLS, matching the
-- rest of the app's SECURITY DEFINER RPC convention.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles set email = new.email where id = new.id;
  if not found then
    insert into public.signup_requests (id, email, full_name)
    values (
      new.id,
      new.email,
      coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
    )
    on conflict (id) do update set email = excluded.email;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

create trigger on_auth_user_email_updated
  after update of email on auth.users
  for each row execute function public.handle_new_auth_user();

create or replace function public.approve_signup_request(
  p_request_id uuid,
  p_role user_role,
  p_location_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if my_role() <> 'admin' then
    raise exception 'Only admins can approve signup requests';
  end if;

  update public.signup_requests
  set status = 'approved',
      decided_by = auth.uid(),
      decided_at = now(),
      assigned_role = p_role,
      assigned_location_id = p_location_id
  where id = p_request_id and status = 'pending';

  if not found then
    raise exception 'Signup request not found or already decided';
  end if;

  insert into public.profiles (id, full_name, email, role, location_id, active)
  select id, coalesce(full_name, email), email, p_role, p_location_id, true
  from public.signup_requests
  where id = p_request_id
  on conflict (id) do update
    set role = excluded.role,
        location_id = excluded.location_id,
        active = true,
        email = excluded.email;
end;
$$;

revoke all on function public.approve_signup_request(uuid, user_role, uuid) from public, anon;
grant execute on function public.approve_signup_request(uuid, user_role, uuid) to authenticated;

create or replace function public.reject_signup_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if my_role() <> 'admin' then
    raise exception 'Only admins can reject signup requests';
  end if;

  update public.signup_requests
  set status = 'rejected',
      decided_by = auth.uid(),
      decided_at = now()
  where id = p_request_id and status = 'pending';

  if not found then
    raise exception 'Signup request not found or already decided';
  end if;
end;
$$;

revoke all on function public.reject_signup_request(uuid) from public, anon;
grant execute on function public.reject_signup_request(uuid) to authenticated;
