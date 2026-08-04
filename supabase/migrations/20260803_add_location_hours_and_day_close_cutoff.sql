-- FLU-29: branch management needs operating hours and a day-close cutoff
-- time per location. All nullable -- a branch without a configured cutoff
-- falls back to midnight (handled in application logic, not here) for the
-- future Daily Closing Report (FLU-34).
alter table public.locations
  add column if not exists open_time time,
  add column if not exists close_time time,
  add column if not exists day_close_cutoff_time time;
