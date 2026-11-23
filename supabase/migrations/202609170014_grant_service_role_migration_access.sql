-- The one-time migration script uses a service-role key. Service role bypasses
-- RLS but PostgreSQL still requires explicit table privileges.
grant select, insert on table public.encrypted_accounts to service_role;
grant select, insert on table public.admin_settings to service_role;
