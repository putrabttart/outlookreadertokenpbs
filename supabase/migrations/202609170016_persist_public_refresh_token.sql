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
