-- Allow multiple independent filters per account while preserving every
-- existing filter row. Account and credential data are not modified.
alter table public.account_email_filters
  add column if not exists id uuid default gen_random_uuid();

update public.account_email_filters
set id = gen_random_uuid()
where id is null;

alter table public.account_email_filters
  alter column id set not null;

alter table public.account_email_filters
  drop constraint if exists account_email_filters_pkey;

alter table public.account_email_filters
  add constraint account_email_filters_pkey primary key (id);

create index if not exists account_email_filters_account_id_idx
  on public.account_email_filters(account_id);

-- Return every active rule for the account tied to the active public session.
-- The application accepts a message when any returned rule matches.
create or replace function public.get_public_email_filter(session_secret text)
returns table (
  enabled boolean,
  sender text,
  subject_contains text,
  body_contains text
)
language sql
security definer
set search_path = public, extensions
as $$
  select
    filter.enabled,
    filter.sender,
    filter.subject_contains,
    filter.body_contains
  from public.account_access_tokens token
  join public.account_email_filters filter on filter.account_id = token.account_id
  where token.session_hash = encode(digest(session_secret, 'sha256'), 'hex')
    and token.status = 'waiting'
    and filter.enabled = true;
$$;

revoke all on function public.get_public_email_filter(text) from public;
grant execute on function public.get_public_email_filter(text) to anon, authenticated;
