-- Patch: perbaikan "permission denied for table inbox_logs"
-- Jalankan seluruh file ini satu kali melalui Supabase Dashboard > SQL Editor.
-- Aman dijalankan ulang karena GRANT dan REVOKE bersifat idempotent.

begin;

-- Role API memerlukan akses ke schema sebelum dapat mengakses tabel/fungsi.
grant usage on schema public to anon, authenticated;

-- Pengguna terautentikasi membutuhkan privilege tabel terlebih dahulu.
-- Row Level Security (RLS) tetap menentukan baris yang boleh diakses.
grant select, insert, update, delete
on table public.encrypted_accounts
to authenticated;

grant select, insert, update, delete
on table public.inbox_logs
to authenticated;

grant select, insert, update, delete
on table public.admin_settings
to authenticated;

-- Halaman pembuka membaca daftar akun yang dikelola admin sebelum pengguna
-- memiliki sesi. Policy RLS encrypted_accounts tetap membatasi hasilnya ke
-- akun dengan is_admin_managed = true.
grant select
on table public.encrypted_accounts
to anon;

-- Daftar admin tidak boleh dibaca langsung dari browser. Pemeriksaannya hanya
-- dilakukan melalui fungsi SECURITY DEFINER public.is_admin().
revoke all
on table public.admin_users
from anon, authenticated;

grant execute
on function public.is_admin()
to authenticated;

commit;

-- Verifikasi opsional setelah patch berhasil dijalankan:
-- 1. Logout dari halaman admin lalu login kembali.
-- 2. Jalankan query berikut untuk memastikan email admin sudah terdaftar:
--
-- select email, created_at from public.admin_users order by created_at;
