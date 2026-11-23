# Migrasi Supabase Lama

Proses ini hanya membaca backup lama dan menambahkan akun yang belum ada ke project baru. Database lama tidak diubah atau dihapus.

## Ringkasan Backup

- Sumber: `supabase-backup-old-20261122-201429.json`
- Row lama: 85
- Email unik: 74
- Duplikat: 11, dipilih berdasarkan `updated_at_ms` terbaru
- Owner: seluruh akun dipetakan ke satu user admin baru

File backup dan file `env-lama.txt` diabaikan Git.

## Persiapan

Dari Supabase project baru, siapkan:

- Project URL
- Service role key dari Project Settings > API
- Email user admin yang sudah terdaftar di Supabase Auth project baru
- Kunci akses akun lama yang digunakan untuk mengenkripsi credential

Jangan masukkan service role key ke `.env` frontend atau Vercel. Gunakan hanya sebagai environment variable terminal lokal.

## Dry Run

Jalankan migration berikut satu kali di SQL Editor project baru:

```text
supabase/migrations/202609170014_grant_service_role_migration_access.sql
```

Migration ini memberi `service_role` hak minimum `SELECT` dan `INSERT` hanya pada tabel yang diperlukan proses import.

```powershell
$env:NEW_SUPABASE_URL="https://PROJECT.supabase.co"
$env:NEW_SUPABASE_SERVICE_ROLE_KEY="SERVICE_ROLE_KEY"
$env:NEW_ADMIN_EMAIL="admin@example.com"
$env:OLD_ACCOUNT_KEY="KUNCI_AKUN_LAMA"
pnpm migrate:old-supabase
```

Dry-run tidak menulis data. Periksa nilai `rowsToInsert`.

## Jalankan Import

```powershell
pnpm migrate:old-supabase -- --apply
```

Skrip akan:

1. Memastikan email admin ada di Supabase Auth baru.
2. Memilih credential terbaru untuk setiap email lama.
3. Melewati email yang sudah ada di database baru.
4. Mengganti `owner_id` lama dengan ID user admin baru.
5. Memvalidasi bahwa kunci lama dapat mendekripsi credential lama.
6. Mengisi shared access key baru bila belum ada, atau berhenti jika key baru berbeda.
7. Menambahkan data dalam batch tanpa mengubah database lama.
8. Membaca ulang database baru dan memverifikasi semua email hasil import.

Setelah selesai, hapus environment variable sensitif dari terminal:

```powershell
Remove-Item Env:NEW_SUPABASE_SERVICE_ROLE_KEY
Remove-Item Env:OLD_ACCOUNT_KEY
```

Data credential tetap terenkripsi. Skrip menguji kunci lama sebelum import agar akun hasil migrasi dapat didekripsi di project baru.
