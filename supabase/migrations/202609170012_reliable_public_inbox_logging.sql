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
