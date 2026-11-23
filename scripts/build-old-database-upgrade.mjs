import fs from "node:fs/promises"

const migrations = [
  "202609170002_admin_and_inbox_logs.sql",
  "202609170003_admin_rpc_access.sql",
  "202609170004_admin_managed_accounts_and_settings.sql",
  "202609170005_admin_access_key.sql",
  "202609170007_grant_authenticated_table_access.sql",
  "202609170008_public_access_tokens.sql",
  "202609170009_token_message_isolation.sql",
  "202609170010_fix_public_inbox_logging.sql",
  "202609170011_fix_inbox_log_conflict.sql",
  "202609170012_reliable_public_inbox_logging.sql",
  "202609170015_restore_authenticated_admin_access.sql",
  "202609170016_persist_public_refresh_token.sql",
]

const sections = await Promise.all(migrations.map(async (name) => {
  const sql = await fs.readFile(new URL(`../supabase/migrations/${name}`, import.meta.url), "utf8")
  return `\n-- -----------------------------------------------------------------------------\n-- ${name}\n-- -----------------------------------------------------------------------------\n${sql.trim()}\n`
}))

const header = `-- Generated compatibility upgrade for the old Supabase project.
-- This bundle does not delete or rewrite existing encrypted_accounts rows.
-- Migration 013 is intentionally excluded because it deletes duplicate emails.
-- Run the complete file in the OLD project's Supabase SQL Editor.

begin;
`

const footer = `
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
`

const output = `${header}${sections.join("")}${footer}`
await fs.writeFile(new URL("../supabase/old-database-compatibility-upgrade.sql", import.meta.url), output)
console.log(`Generated supabase/old-database-compatibility-upgrade.sql from ${migrations.length} migrations.`)
