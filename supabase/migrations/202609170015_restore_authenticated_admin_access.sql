-- Restore the table privileges used by the browser after an admin signs in.
-- RLS policies still decide which rows the authenticated user may access.
grant select, insert, update, delete on table public.encrypted_accounts to authenticated;
grant select, insert, update, delete on table public.inbox_logs to authenticated;
grant select, insert, update, delete on table public.admin_settings to authenticated;
grant select on table public.account_access_tokens to authenticated;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.admin_create_access_token(uuid) to authenticated;
grant execute on function public.admin_revoke_access_token(uuid) to authenticated;
