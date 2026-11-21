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
