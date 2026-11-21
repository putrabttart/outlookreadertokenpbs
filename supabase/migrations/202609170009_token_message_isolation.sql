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
