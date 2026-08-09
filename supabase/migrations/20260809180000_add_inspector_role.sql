-- Inspectors audit multiple branches without being a branch's day-to-day
-- operational manager. has_audit_location_access() was already
-- role-agnostic (admin/own-location/grant), so this only needed a new
-- enum value plus updating the frontend role gates that hardcoded
-- 'branch_manager' for audit access.
alter type public.user_role add value 'inspector';
