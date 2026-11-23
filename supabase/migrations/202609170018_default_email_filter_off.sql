-- Keep existing filter rows unchanged. This only makes future rows default to
-- no filtering when the enabled value is omitted.
alter table public.account_email_filters
  alter column enabled set default false;
