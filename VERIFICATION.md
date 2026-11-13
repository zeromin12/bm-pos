# Status verifikasi BM POS 1.0

Tanggal: 12 November 2026.

- `npm run typecheck`: lulus.
- `npm run lint`: lulus tanpa error/warning.
- `npm test`: 19 kelompok uji integrasi SQL lokal lulus.
- `npm run build`: build produksi Next.js lulus tanpa environment Supabase; aplikasi menyediakan layar konfigurasi dan pratinjau saat belum terhubung.
- Data contoh dan owner bootstrap: disertakan sebagai SQL terpisah; perlu dijalankan pada proyek Supabase Anda.

Pengujian SQL memakai PostgreSQL PGlite dengan role dan Auth stub. Validasi RLS dan fungsi bisnis benar-benar dijalankan, tetapi bukan login Supabase melalui jaringan, API PostgREST nyata, atau stress test dua koneksi bersamaan.

Browser visual QA belum diverifikasi: preview environment menyuntikkan flag --host/--strictPort yang tidak kompatibel dengan next dev. Build aplikasi tetap berhasil. Tidak mengklaim screenshot, pengujian mobile browser nyata, atau pencetakan fisik telah dilakukan.

Belum di-deploy ke akun Vercel pengguna. Tidak ada database eksternal, akun owner, atau pembayaran riil yang dibuat oleh paket ini. Ikuti README untuk memasang dan lakukan UAT sebelum dipakai operasional.
