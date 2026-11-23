-- Per-account email delivery rules. This is an isolated table and does not
-- alter existing account, token, or inbox-log columns/data.
create table if not exists public.account_email_filters (
  account_id uuid primary key references public.encrypted_accounts(id) on delete cascade,
  enabled boolean not null default false,
  description text not null default '',
  sender text not null default '',
  subject_contains text not null default 'Kode akses sementara Netflix-mu',
  body_contains text not null default 'kode akses sementara',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.account_email_filters enable row level security;

drop policy if exists "account_email_filters_admin_all" on public.account_email_filters;
create policy "account_email_filters_admin_all"
on public.account_email_filters for all to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on table public.account_email_filters from anon, authenticated;
grant select on table public.account_email_filters to authenticated;
grant insert, update, delete on table public.account_email_filters to authenticated;

-- Public clients can only retrieve the filter for an active token session.
-- They cannot enumerate filters or request another account's configuration.
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
  limit 1;
$$;

revoke all on function public.get_public_email_filter(text) from public;
grant execute on function public.get_public_email_filter(text) to anon, authenticated;
