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
