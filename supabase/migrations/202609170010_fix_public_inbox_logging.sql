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
