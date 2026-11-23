import fs from "node:fs/promises"
import process from "node:process"
import crypto from "node:crypto"
import { createClient } from "@supabase/supabase-js"

const apply = process.argv.includes("--apply")
const backupPath = process.env.OLD_SUPABASE_BACKUP || "supabase-backup-old-20261122-201429.json"
const targetUrl = process.env.NEW_SUPABASE_URL
const serviceRoleKey = process.env.NEW_SUPABASE_SERVICE_ROLE_KEY
const adminEmail = process.env.NEW_ADMIN_EMAIL?.trim().toLowerCase()
const accountKey = process.env.OLD_ACCOUNT_KEY

if (!targetUrl || !serviceRoleKey || !adminEmail || !accountKey) {
  console.error("Set NEW_SUPABASE_URL, NEW_SUPABASE_SERVICE_ROLE_KEY, NEW_ADMIN_EMAIL, and OLD_ACCOUNT_KEY.")
  process.exit(1)
}

const backup = JSON.parse(await fs.readFile(backupPath, "utf8"))
const sourceRows = backup?.tables?.encrypted_accounts
if (!Array.isArray(sourceRows)) {
  throw new Error("Backup does not contain tables.encrypted_accounts array")
}

function validateAccountKey(row, passphrase) {
  const key = crypto.pbkdf2Sync(passphrase, Buffer.from(row.salt, "base64"), 100000, 32, "sha256")
  const ciphertext = Buffer.from(row.cipher_text, "base64")
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(row.iv, "base64"))
  decipher.setAuthTag(ciphertext.subarray(ciphertext.length - 16))
  JSON.parse(Buffer.concat([decipher.update(ciphertext.subarray(0, -16)), decipher.final()]).toString("utf8"))
}

try {
  validateAccountKey(sourceRows[0], accountKey)
} catch {
  throw new Error("OLD_ACCOUNT_KEY cannot decrypt the old account backup")
}

// Keep the most recently updated credential for each case-insensitive email.
const newestByEmail = new Map()
for (const row of sourceRows) {
  const email = String(row.email || "").trim().toLowerCase()
  if (!email) continue
  const current = newestByEmail.get(email)
  if (!current || Number(row.updated_at_ms) > Number(current.updated_at_ms)) {
    newestByEmail.set(email, row)
  }
}

const supabase = createClient(targetUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

function throwDatabaseError(error) {
  if (error?.code === "42501") {
    throw new Error(`${error.message}. Run supabase/migrations/202609170014_grant_service_role_migration_access.sql in the new project's SQL Editor.`)
  }
  throw error
}

const { data: userList, error: userError } = await supabase.auth.admin.listUsers({ perPage: 1000 })
if (userError) throw userError
const targetUser = userList.users.find((user) => user.email?.trim().toLowerCase() === adminEmail)
if (!targetUser) throw new Error(`Admin user ${adminEmail} was not found in the new Supabase Auth project`)

const { data: existingRows, error: existingError } = await supabase
  .from("encrypted_accounts")
  .select("email")
if (existingError) throwDatabaseError(existingError)

const existingEmails = new Set((existingRows || []).map((row) => row.email.trim().toLowerCase()))

const { data: keySetting, error: keySettingError } = await supabase
  .from("admin_settings")
  .select("value")
  .eq("key", "shared_access_key")
  .maybeSingle()
if (keySettingError) throwDatabaseError(keySettingError)
if (keySetting?.value && keySetting.value !== accountKey) {
  throw new Error("The new project already uses a different shared access key; import stopped to protect existing accounts")
}

const importRows = [...newestByEmail.values()]
  .filter((row) => !existingEmails.has(row.email.trim().toLowerCase()))
  .map((row) => ({
    id: row.id,
    owner_id: targetUser.id,
    email: row.email.trim(),
    client_id: row.client_id,
    cipher_text: row.cipher_text,
    iv: row.iv,
    salt: row.salt,
    created_at_ms: row.created_at_ms,
    updated_at_ms: row.updated_at_ms,
    is_admin_managed: true,
  }))

console.log(JSON.stringify({
  mode: apply ? "apply" : "dry-run",
  sourceRows: sourceRows.length,
  uniqueSourceEmails: newestByEmail.size,
  duplicatesRemoved: sourceRows.length - newestByEmail.size,
  existingTargetEmails: existingEmails.size,
  rowsToInsert: importRows.length,
  targetAdmin: adminEmail,
}, null, 2))

if (!apply) {
  console.log("Dry-run only. Re-run with --apply to insert rows into the new project.")
  process.exit(0)
}

if (!keySetting?.value) {
  const { error: keyInsertError } = await supabase
    .from("admin_settings")
    .insert({ key: "shared_access_key", value: accountKey, updated_at: new Date().toISOString() })
  if (keyInsertError) throwDatabaseError(keyInsertError)
}

for (let offset = 0; offset < importRows.length; offset += 100) {
  const batch = importRows.slice(offset, offset + 100)
  const { error } = await supabase.from("encrypted_accounts").insert(batch)
  if (error) throwDatabaseError(error)
}

const { data: verificationRows, error: verificationError } = await supabase
  .from("encrypted_accounts")
  .select("email")
  .eq("owner_id", targetUser.id)
if (verificationError) throwDatabaseError(verificationError)

const verifiedEmails = new Set((verificationRows || []).map((row) => row.email.trim().toLowerCase()))
const missingEmails = importRows
  .map((row) => row.email.trim().toLowerCase())
  .filter((email) => !verifiedEmails.has(email))

if (missingEmails.length > 0) {
  throw new Error(`Verification failed: ${missingEmails.length} imported email(s) are missing`)
}

console.log(`Import complete and verified: ${importRows.length} row(s) inserted. Old database was not modified.`)
