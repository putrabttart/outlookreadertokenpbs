# Menghubungkan Aplikasi ke Supabase Lama

## Kesimpulan

Project dapat memakai database lama setelah schema lama di-upgrade. Data `encrypted_accounts` lama tidak perlu dipindahkan dan tidak akan dihapus.

URL dan anon key saja tidak dapat menjalankan DDL, menambah policy/RPC, atau membuat user Auth. Anda harus mempunyai salah satu akses berikut untuk project lama:

- Supabase Dashboard dan SQL Editor
- Database password/direct connection
- Service-role key untuk operasi data, ditambah jalur SQL untuk DDL

## Perbedaan Schema

Database lama yang dapat dipastikan melalui REST hanya mempunyai `encrypted_accounts` dengan 85 row. Endpoint tabel berikut belum tersedia (`404`):

- `admin_users`
- `inbox_logs`
- `admin_settings`
- `account_access_tokens`

Kode terbaru juga membutuhkan RPC admin dan public-token, termasuk persistensi refresh token hasil rotasi.

## Upgrade Non-Destruktif

Generate ulang bundle bila migration sumber berubah:

```powershell
corepack pnpm migration:build-old-upgrade
```

Jalankan seluruh isi file berikut di SQL Editor **project lama**:

```text
supabase/old-database-compatibility-upgrade.sql
```

Bundle sengaja tidak menyertakan migration `202609170013_unique_managed_account_email.sql`, karena migration tersebut menghapus 11 row email duplikat. Bundle juga tidak mengubah ciphertext 85 akun lama.

## Konfigurasi Admin Lama

User admin harus dibuat atau sudah tersedia di Supabase Auth project lama. Setelah itu jalankan di SQL Editor lama, dengan mengganti dua placeholder:

```sql
insert into public.admin_users (email)
values ('EMAIL_ADMIN_ANDA')
on conflict (email) do nothing;

insert into public.admin_settings (key, value)
values ('shared_access_key', 'KUNCI_AKUN_LAMA')
on conflict (key) do update
set value = excluded.value,
    updated_at = now();
```

`KUNCI_AKUN_LAMA` harus sama dengan kunci yang mengenkripsi 85 akun lama. Jangan menyimpan nilai asli di file Git.

## Arahkan Frontend

Ubah `.env` lokal:

```dotenv
VITE_USE_OAUTH_PROXY=true
VITE_SUPABASE_URL=https://PROJECT-LAMA.supabase.co
VITE_SUPABASE_ANON_KEY=ANON_KEY_PROJECT_LAMA
VITE_ADMIN_ACCOUNT_KEY=KUNCI_AKUN_LAMA
```

Untuk deployment Vercel, ubah environment variables yang sama lalu lakukan redeploy. Jangan pernah memasukkan service-role key ke environment frontend.

## Verifikasi

1. Login admin menggunakan user Auth yang berada di project lama.
2. Pastikan halaman Akun memuat 85 row lama.
3. Generate satu token akses untuk satu akun uji.
4. Redeem token pada browser lain.
5. Pastikan `/api/token` merespons dan inbox dapat dipolling.
6. Pastikan `updated_at_ms` akun berubah bila Microsoft mengembalikan refresh token baru.

Jangan menguji seluruh akun sekaligus karena exchange massal dapat merotasi banyak refresh token.
