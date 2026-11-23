-- Generated compatibility upgrade for the old Supabase project.
-- This bundle does not delete or rewrite existing encrypted_accounts rows.
-- Migration 013 is intentionally excluded because it deletes duplicate emails.
-- Run the complete file in the OLD project's Supabase SQL Editor.

begin;

-- -----------------------------------------------------------------------------
-- 202609170002_admin_and_inbox_logs.sql
-- -----------------------------------------------------------------------------
create table if not exists public.admin_users (
  email text primary key,
  created_at timestamptz not null default now()
);

create table if not exists public.inbox_logs (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.encrypted_accounts(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  account_email text not null,
  message_id text not null,
  subject text not null,
  sender text not null,
  received_at timestamptz,
  is_read boolean not null default false,
  preview text not null default '',
  logged_at timestamptz not null default now(),
  unique(account_id, message_id)
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_users
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

drop policy if exists "encrypted_accounts_select_own" on public.encrypted_accounts;
create policy "encrypted_accounts_select_own"
on public.encrypted_accounts for select
using (auth.uid() = owner_id or public.is_admin());

drop policy if exists "encrypted_accounts_delete_own" on public.encrypted_accounts;
create policy "encrypted_accounts_delete_own"
on public.encrypted_accounts for delete
using (auth.uid() = owner_id or public.is_admin());

alter table public.inbox_logs enable row level security;

drop policy if exists "inbox_logs_select_own_or_admin" on public.inbox_logs;
create policy "inbox_logs_select_own_or_admin"
on public.inbox_logs for select
using (auth.uid() = owner_id or public.is_admin());

drop policy if exists "inbox_logs_insert_own" on public.inbox_logs;
create policy "inbox_logs_insert_own"
on public.inbox_logs for insert
with check (auth.uid() = owner_id);

drop policy if exists "inbox_logs_update_own" on public.inbox_logs;
create policy "inbox_logs_update_own"
on public.inbox_logs for update
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

drop policy if exists "inbox_logs_delete_admin" on public.inbox_logs;
create policy "inbox_logs_delete_admin"
on public.inbox_logs for delete
using (public.is_admin());

create index if not exists inbox_logs_account_logged_idx
on public.inbox_logs(account_id, logged_at desc);

create index if not exists inbox_logs_owner_logged_idx
on public.inbox_logs(owner_id, logged_at desc);

-- -----------------------------------------------------------------------------
-- 202609170003_admin_rpc_access.sql
-- -----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_users
    where lower(trim(email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  );
$$;

grant execute on function public.is_admin() to authenticated;

-- -----------------------------------------------------------------------------
-- 202609170004_admin_managed_accounts_and_settings.sql
-- -----------------------------------------------------------------------------
alter table public.encrypted_accounts
add column if not exists is_admin_managed boolean not null default false;

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (key, value)
values ('vault_enabled', 'false'::jsonb)
on conflict (key) do nothing;

drop policy if exists "encrypted_accounts_select_own" on public.encrypted_accounts;
create policy "encrypted_accounts_select_own"
on public.encrypted_accounts for select
using (auth.uid() = owner_id or is_admin_managed = true or public.is_admin());

drop policy if exists "encrypted_accounts_insert_own" on public.encrypted_accounts;
create policy "encrypted_accounts_insert_own"
on public.encrypted_accounts for insert
with check (auth.uid() = owner_id or public.is_admin());

drop policy if exists "encrypted_accounts_update_own" on public.encrypted_accounts;
create policy "encrypted_accounts_update_own"
on public.encrypted_accounts for update
using (auth.uid() = owner_id or public.is_admin())
with check (auth.uid() = owner_id or public.is_admin());

alter table public.app_settings enable row level security;

drop policy if exists "app_settings_select_all" on public.app_settings;
create policy "app_settings_select_all"
on public.app_settings for select
using (true);

drop policy if exists "app_settings_modify_admin" on public.app_settings;
create policy "app_settings_modify_admin"
on public.app_settings for all
using (public.is_admin())
with check (public.is_admin());

create index if not exists encrypted_accounts_admin_managed_idx
on public.encrypted_accounts(is_admin_managed, created_at_ms);

-- -----------------------------------------------------------------------------
-- 202609170005_admin_access_key.sql
-- -----------------------------------------------------------------------------
create table if not exists public.admin_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

alter table public.admin_settings enable row level security;

drop policy if exists "admin_settings_admin_only" on public.admin_settings;
create policy "admin_settings_admin_only"
on public.admin_settings for all
using (public.is_admin())
with check (public.is_admin());

-- -----------------------------------------------------------------------------
-- 202609170007_grant_authenticated_table_access.sql
-- -----------------------------------------------------------------------------
-- PostgreSQL table privileges are checked before row-level security policies.
-- Grant only the operations used by the client; RLS still controls which rows
-- each authenticated user can read or modify.
grant select, insert, update, delete on table public.encrypted_accounts to authenticated;
grant select, insert, update, delete on table public.inbox_logs to authenticated;
grant select, insert, update, delete on table public.admin_settings to authenticated;

-- The unlock screen lists admin-managed accounts before an auth session exists.
-- The encrypted_accounts SELECT policy still exposes only admin-managed rows.
grant select on table public.encrypted_accounts to anon;

-- Keep the admin allowlist private. It is read only through the security
-- definer function, which executes with the function owner's privileges.
revoke all on table public.admin_users from anon, authenticated;

grant execute on function public.is_admin() to authenticated;

-- -----------------------------------------------------------------------------
-- 202609170008_public_access_tokens.sql
-- -----------------------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.account_access_tokens (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.encrypted_accounts(id) on delete cascade,
  token_hash text not null unique,
  token_prefix text not null,
  status text not null default 'unused' check (status in ('unused', 'waiting', 'used', 'revoked')),
  session_hash text unique,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  claimed_message_id text,
  claimed_at timestamptz,
  revoked_at timestamptz
);

create unique index if not exists account_access_tokens_claimed_message_idx
on public.account_access_tokens(account_id, claimed_message_id)
where claimed_message_id is not null;

create index if not exists account_access_tokens_queue_idx
on public.account_access_tokens(account_id, status, activated_at, id);

alter table public.account_access_tokens enable row level security;

drop policy if exists "account_access_tokens_admin_select" on public.account_access_tokens;
create policy "account_access_tokens_admin_select"
on public.account_access_tokens for select
using (public.is_admin());

revoke all on table public.account_access_tokens from anon, authenticated;
grant select on table public.account_access_tokens to authenticated;

create or replace function public.admin_create_access_token(target_account_id uuid)
returns table (id uuid, token text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  raw_token text;
  new_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  if not exists (
    select 1 from public.encrypted_accounts
    where encrypted_accounts.id = target_account_id
      and encrypted_accounts.is_admin_managed = true
  ) then
    raise exception 'Account not found';
  end if;

  raw_token := upper(encode(gen_random_bytes(16), 'hex'));

  insert into public.account_access_tokens (account_id, token_hash, token_prefix)
  values (
    target_account_id,
    encode(digest(raw_token, 'sha256'), 'hex'),
    left(raw_token, 8)
  )
  returning account_access_tokens.id into new_id;

  return query select new_id, raw_token;
end;
$$;

create or replace function public.admin_revoke_access_token(target_token_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  update public.account_access_tokens
  set status = 'revoked', revoked_at = now(), session_hash = null
  where id = target_token_id and status in ('unused', 'waiting');
end;
$$;

create or replace function public.redeem_access_token(raw_token text, session_secret text)
returns table (
  token_id uuid,
  account_id uuid,
  activated_at timestamptz,
  email text,
  client_id text,
  cipher_text text,
  iv text,
  salt text,
  access_key text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  matched public.account_access_tokens%rowtype;
begin
  if length(trim(raw_token)) < 16 or length(session_secret) < 32 then
    raise exception 'Invalid access token';
  end if;

  update public.account_access_tokens
  set status = 'waiting',
      activated_at = clock_timestamp(),
      session_hash = encode(digest(session_secret, 'sha256'), 'hex')
  where token_hash = encode(digest(upper(trim(raw_token)), 'sha256'), 'hex')
    and status = 'unused'
  returning * into matched;

  if matched.id is null then
    raise exception 'Token is invalid or has already been used';
  end if;

  return query
  select matched.id, matched.account_id, matched.activated_at,
         account.email, account.client_id, account.cipher_text, account.iv, account.salt,
         settings.value
  from public.encrypted_accounts account
  cross join public.admin_settings settings
  where account.id = matched.account_id
    and settings.key = 'shared_access_key';

  if not found then
    raise exception 'Account access key is not configured';
  end if;
end;
$$;

create or replace function public.resume_access_session(session_secret text)
returns table (
  token_id uuid,
  account_id uuid,
  status text,
  activated_at timestamptz,
  claimed_message_id text,
  email text,
  client_id text,
  cipher_text text,
  iv text,
  salt text,
  access_key text
)
language sql
security definer
set search_path = public, extensions
as $$
  select token.id, token.account_id, token.status, token.activated_at,
         token.claimed_message_id, account.email, account.client_id,
         account.cipher_text, account.iv, account.salt, settings.value
  from public.account_access_tokens token
  join public.encrypted_accounts account on account.id = token.account_id
  cross join public.admin_settings settings
  where token.session_hash = encode(digest(session_secret, 'sha256'), 'hex')
    and token.status in ('waiting', 'used')
    and settings.key = 'shared_access_key'
  limit 1;
$$;

create or replace function public.claim_access_message(
  session_secret text,
  candidate_message_id text,
  candidate_received_at timestamptz
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  current_token public.account_access_tokens%rowtype;
  first_waiting_id uuid;
begin
  select * into current_token
  from public.account_access_tokens
  where session_hash = encode(digest(session_secret, 'sha256'), 'hex')
  for update;

  if current_token.id is null then
    return 'invalid';
  end if;
  if current_token.status <> 'waiting' then
    return current_token.status;
  end if;
  if candidate_received_at <= current_token.activated_at then
    return 'waiting';
  end if;

  select id into first_waiting_id
  from public.account_access_tokens
  where account_id = current_token.account_id and status = 'waiting'
  order by activated_at asc, id asc
  limit 1
  for update;

  if first_waiting_id <> current_token.id then
    return 'waiting';
  end if;

  if exists (
    select 1 from public.account_access_tokens
    where account_id = current_token.account_id
      and claimed_message_id = candidate_message_id
  ) then
    return 'waiting';
  end if;

  update public.account_access_tokens
  set status = 'used',
      claimed_message_id = candidate_message_id,
      claimed_at = clock_timestamp()
  where id = current_token.id;

  return 'used';
end;
$$;

revoke all on function public.admin_create_access_token(uuid) from public, anon;
revoke all on function public.admin_revoke_access_token(uuid) from public, anon;
grant execute on function public.admin_create_access_token(uuid) to authenticated;
grant execute on function public.admin_revoke_access_token(uuid) to authenticated;

revoke all on function public.redeem_access_token(text, text) from public;
revoke all on function public.resume_access_session(text) from public;
revoke all on function public.claim_access_message(text, text, timestamptz) from public;
grant execute on function public.redeem_access_token(text, text) to anon, authenticated;
grant execute on function public.resume_access_session(text) to anon, authenticated;
grant execute on function public.claim_access_message(text, text, timestamptz) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 202609170009_token_message_isolation.sql
-- -----------------------------------------------------------------------------
-- Patch for existing token installations.
-- A message can belong to only one token for one account. The claim RPC also
-- rejects messages already claimed by another token before marking this token
-- as used, so a second browser must wait for a later message.

create unique index if not exists account_access_tokens_claimed_message_idx
on public.account_access_tokens(account_id, claimed_message_id)
where claimed_message_id is not null;

create or replace function public.claim_access_message(
  session_secret text,
  candidate_message_id text,
  candidate_received_at timestamptz
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  current_token public.account_access_tokens%rowtype;
  first_waiting_id uuid;
begin
  select * into current_token
  from public.account_access_tokens
  where session_hash = encode(digest(session_secret, 'sha256'), 'hex')
  for update;

  if current_token.id is null then
    return 'invalid';
  end if;
  if current_token.status <> 'waiting' then
    return current_token.status;
  end if;
  if candidate_received_at <= current_token.activated_at then
    return 'waiting';
  end if;

  select id into first_waiting_id
  from public.account_access_tokens
  where account_id = current_token.account_id and status = 'waiting'
  order by activated_at asc, id asc
  limit 1
  for update;

  if first_waiting_id <> current_token.id then
    return 'waiting';
  end if;

  -- This is the isolation boundary between browser sessions. A message that
  -- was already assigned to another token can never be assigned again.
  if exists (
    select 1
    from public.account_access_tokens
    where account_id = current_token.account_id
      and claimed_message_id = candidate_message_id
  ) then
    return 'waiting';
  end if;

  update public.account_access_tokens
  set status = 'used',
      claimed_message_id = candidate_message_id,
      claimed_at = clock_timestamp()
  where id = current_token.id and status = 'waiting';

  if not found then
    return 'waiting';
  end if;

  return 'used';
end;
$$;

revoke all on function public.claim_access_message(text, text, timestamptz) from public;
grant execute on function public.claim_access_message(text, text, timestamptz) to anon, authenticated;

create or replace function public.log_public_inbox_message(
  session_secret text,
  message_id text,
  message_subject text,
  message_sender text,
  message_received_at timestamptz,
  message_is_read boolean,
  message_preview text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  token_account_id uuid;
  token_owner_id uuid;
  token_email text;
begin
  select token.account_id, account.owner_id, account.email
  into token_account_id, token_owner_id, token_email
  from public.account_access_tokens token
  join public.encrypted_accounts account on account.id = token.account_id
  where token.session_hash = encode(extensions.digest(session_secret, 'sha256'), 'hex')
    and token.status in ('waiting', 'used')
  limit 1;

  if token_account_id is null then
    raise exception 'Invalid access session';
  end if;

  insert into public.inbox_logs (
    account_id, owner_id, account_email, message_id, subject, sender,
    received_at, is_read, preview
  )
  values (
    token_account_id, token_owner_id, token_email, message_id, message_subject,
    message_sender, message_received_at, message_is_read, message_preview
  )
  on conflict (account_id, message_id) do update set
    subject = excluded.subject,
    sender = excluded.sender,
    received_at = excluded.received_at,
    is_read = excluded.is_read,
    preview = excluded.preview;
end;
$$;

revoke all on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) from public;
grant execute on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 202609170010_fix_public_inbox_logging.sql
-- -----------------------------------------------------------------------------
-- Fix public message logging for databases that already applied migration 009.
-- pgcrypto functions are installed in the extensions schema on Supabase.

create or replace function public.log_public_inbox_message(
  session_secret text,
  message_id text,
  message_subject text,
  message_sender text,
  message_received_at timestamptz,
  message_is_read boolean,
  message_preview text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  token_account_id uuid;
  token_owner_id uuid;
  token_email text;
begin
  select token.account_id, account.owner_id, account.email
  into token_account_id, token_owner_id, token_email
  from public.account_access_tokens token
  join public.encrypted_accounts account on account.id = token.account_id
  where token.session_hash = encode(extensions.digest(session_secret, 'sha256'), 'hex')
    and token.status in ('waiting', 'used')
  limit 1;

  if token_account_id is null then
    raise exception 'Invalid access session';
  end if;

  insert into public.inbox_logs (
    account_id, owner_id, account_email, message_id, subject, sender,
    received_at, is_read, preview
  )
  values (
    token_account_id, token_owner_id, token_email, message_id, message_subject,
    message_sender, message_received_at, message_is_read, coalesce(message_preview, '')
  )
  on conflict on constraint inbox_logs_account_id_message_id_key do update set
    subject = excluded.subject,
    sender = excluded.sender,
    received_at = excluded.received_at,
    is_read = excluded.is_read,
    preview = excluded.preview;
end;
$$;

revoke all on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) from public;
grant execute on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 202609170011_fix_inbox_log_conflict.sql
-- -----------------------------------------------------------------------------
-- Fix a possible PL/pgSQL ambiguity between the message_id function argument
-- and the inbox_logs.message_id column in the ON CONFLICT clause.

create or replace function public.log_public_inbox_message(
  session_secret text,
  message_id text,
  message_subject text,
  message_sender text,
  message_received_at timestamptz,
  message_is_read boolean,
  message_preview text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  token_account_id uuid;
  token_owner_id uuid;
  token_email text;
begin
  select token.account_id, account.owner_id, account.email
  into token_account_id, token_owner_id, token_email
  from public.account_access_tokens token
  join public.encrypted_accounts account on account.id = token.account_id
  where token.session_hash = encode(extensions.digest(session_secret, 'sha256'), 'hex')
    and token.status in ('waiting', 'used')
  limit 1;

  if token_account_id is null then
    raise exception 'Invalid access session';
  end if;

  insert into public.inbox_logs (
    account_id, owner_id, account_email, message_id, subject, sender,
    received_at, is_read, preview
  )
  values (
    token_account_id, token_owner_id, token_email, message_id, message_subject,
    message_sender, message_received_at, message_is_read, coalesce(message_preview, '')
  )
  on conflict on constraint inbox_logs_account_id_message_id_key do update set
    subject = excluded.subject,
    sender = excluded.sender,
    received_at = excluded.received_at,
    is_read = excluded.is_read,
    preview = excluded.preview;
end;
$$;

revoke all on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) from public;
grant execute on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 202609170012_reliable_public_inbox_logging.sql
-- -----------------------------------------------------------------------------
-- Reliable logging patch for public token sessions.
-- Parameter names use a p_ prefix so they cannot collide with table columns.

drop function if exists public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text);

create or replace function public.log_public_inbox_message(
  p_session_secret text,
  p_message_id text,
  p_message_subject text,
  p_message_sender text,
  p_message_received_at timestamptz,
  p_message_is_read boolean,
  p_message_preview text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_account_id uuid;
  v_owner_id uuid;
  v_account_email text;
begin
  select token.account_id, account.owner_id, account.email
  into v_account_id, v_owner_id, v_account_email
  from public.account_access_tokens as token
  join public.encrypted_accounts as account on account.id = token.account_id
  where token.session_hash = encode(extensions.digest(p_session_secret, 'sha256'), 'hex')
    and token.status in ('waiting', 'used')
  limit 1;

  if v_account_id is null then
    raise exception 'Invalid access session';
  end if;

  insert into public.inbox_logs (
    account_id,
    owner_id,
    account_email,
    message_id,
    subject,
    sender,
    received_at,
    is_read,
    preview
  )
  values (
    v_account_id,
    v_owner_id,
    v_account_email,
    p_message_id,
    coalesce(p_message_subject, ''),
    coalesce(p_message_sender, ''),
    p_message_received_at,
    coalesce(p_message_is_read, false),
    coalesce(p_message_preview, '')
  )
  on conflict (account_id, message_id) do update set
    subject = excluded.subject,
    sender = excluded.sender,
    received_at = excluded.received_at,
    is_read = excluded.is_read,
    preview = excluded.preview;
end;
$$;

revoke all on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) from public;
grant execute on function public.log_public_inbox_message(text, text, text, text, timestamptz, boolean, text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 202609170015_restore_authenticated_admin_access.sql
-- -----------------------------------------------------------------------------
-- Restore the table privileges used by the browser after an admin signs in.
-- RLS policies still decide which rows the authenticated user may access.
grant select, insert, update, delete on table public.encrypted_accounts to authenticated;
grant select, insert, update, delete on table public.inbox_logs to authenticated;
grant select, insert, update, delete on table public.admin_settings to authenticated;
grant select on table public.account_access_tokens to authenticated;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.admin_create_access_token(uuid) to authenticated;
grant execute on function public.admin_revoke_access_token(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 202609170016_persist_public_refresh_token.sql
-- -----------------------------------------------------------------------------
-- Persist rotated Microsoft refresh tokens from an active public session.
-- The caller must prove possession of the session secret for the same account.
create or replace function public.update_public_account_credential(
  session_secret text,
  next_cipher_text text,
  next_iv text,
  next_salt text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target_account_id uuid;
begin
  if length(session_secret) < 32
    or length(next_cipher_text) < 16
    or length(next_iv) < 8
    or length(next_salt) < 8 then
    return false;
  end if;

  select account_id into target_account_id
  from public.account_access_tokens
  where session_hash = encode(digest(session_secret, 'sha256'), 'hex')
    and status = 'waiting'
  limit 1;

  if target_account_id is null then
    return false;
  end if;

  update public.encrypted_accounts
  set cipher_text = next_cipher_text,
      iv = next_iv,
      salt = next_salt,
      updated_at_ms = floor(extract(epoch from clock_timestamp()) * 1000)::bigint,
      updated_at = clock_timestamp()
  where id = target_account_id;

  return found;
end;
$$;

revoke all on function public.update_public_account_credential(text, text, text, text) from public;
grant execute on function public.update_public_account_credential(text, text, text, text) to anon, authenticated;

-- Existing rows in the old project are managed through the admin dashboard.
-- This changes metadata only; encrypted credential fields remain untouched.
update public.encrypted_accounts
set is_admin_managed = true
where is_admin_managed = false;

commit;

-- Required manual steps after this transaction:
-- 1. Add the admin email to public.admin_users.
-- 2. Add shared_access_key to public.admin_settings using the same account key
--    that encrypted the existing rows. Do not commit that secret to Git.
