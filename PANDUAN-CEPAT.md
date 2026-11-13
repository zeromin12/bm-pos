# Mulai BM POS

1. Ekstrak ZIP.
2. Buat proyek Supabase kosong.
3. SQL Editor: jalankan `supabase/schema.sql`.
4. Authentication → Users: buat akun owner.
5. Ganti email pada `supabase/setup-owner.sql`, lalu jalankan.
6. Upload isi folder `bm-pos` ke repository GitHub. `package.json` harus di root.
7. Vercel → Add New Project → Import repository.
8. Framework Next.js; Build `npm run build`; Install `npm ci`; Output default.
9. Tambahkan `NEXT_PUBLIC_SUPABASE_URL` dan `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
10. Deploy. Atur Site URL/Redirect URL Supabase ke URL Vercel.
11. Login → Pengaturan → Produk → Persediaan → Buka shift → Kasir.

Tidak ada password default. Buat sendiri melalui Supabase. QRIS diverifikasi manual.

**Penting:** ini versi inti untuk satu toko. Baca README untuk fitur tersedia, batasan, printer, backup, dan langkah pengujian sebelum dipakai operasional.
