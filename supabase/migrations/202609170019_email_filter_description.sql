-- Optional admin-facing label for identifying each account's filter.
-- Existing filter rows and account data remain unchanged.
alter table public.account_email_filters
  add column if not exists description text not null default '';
