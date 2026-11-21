-- Prevent the same Outlook email from being added more than once.
-- Existing duplicate rows are collapsed by keeping the oldest account row.

delete from public.encrypted_accounts duplicate_account
using public.encrypted_accounts kept_account
where duplicate_account.id <> kept_account.id
  and lower(trim(duplicate_account.email)) = lower(trim(kept_account.email))
  and (
    duplicate_account.created_at_ms > kept_account.created_at_ms
    or (
      duplicate_account.created_at_ms = kept_account.created_at_ms
      and duplicate_account.id::text > kept_account.id::text
    )
  );

create unique index if not exists encrypted_accounts_email_ci_unique_idx
on public.encrypted_accounts (lower(trim(email)));
