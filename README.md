# BM POS — Paket Vercel + Supabase

**Kasir praktis, bisnis terkendali.** Aplikasi Next.js berbahasa Indonesia untuk satu toko dengan database PostgreSQL, autentikasi Supabase, dan role Owner, Admin, Kasir, Admin Gudang.

Paket ini adalah implementasi operasional inti, bukan seluruh roadmap ERP pada prompt awal. Lihat batasan di bagian akhir. Tidak ada password default atau kredensial yang disertakan. Tidak perlu service-role key di Vercel.

## 1. Isi paket

- `app/`, `components/`, `lib/`: aplikasi Next.js dan antarmuka responsive.
- `supabase/schema.sql`: tabel, fungsi transaksi atomik, RLS, dan audit.
- `supabase/setup-owner.sql`: aktivasi owner pertama.
- `supabase/demo-data.sql`: produk contoh opsional untuk database demo.
- `.env.example`: dua environment variable publik yang dibutuhkan.
- `tests/database.test.mjs`: pengujian integrasi SQL lokal.
- `PANDUAN-CEPAT.md`: langkah pemasangan singkat.

Database menyimpan transaksi permanen. Browser hanya menyimpan sesi login, tema, dan draft keranjang. Pembayaran, stok, harga, dan izin divalidasi ulang oleh fungsi PostgreSQL pada server Supabase, bukan dipercaya dari browser.

## 2. Buat database Supabase

1. Buat proyek baru di https://supabase.com/dashboard. Gunakan proyek terpisah untuk demo dan produksi.
2. Buka **SQL Editor → New query**, salin seluruh isi `supabase/schema.sql`, lalu **Run**.
3. Jalankan schema hanya sekali pada proyek kosong. Jika sudah terpasang, jangan menjalankan ulang atau menghapus database berisi transaksi.
4. Di **Authentication → Users**, gunakan **Add user / Create new user**. Masukkan email owner dan password kuat minimal 8 karakter. Konfirmasikan email sesuai opsi dashboard.
5. Edit `supabase/setup-owner.sql`: ganti `GANTI-EMAIL-OWNER@contoh.com` dengan email tersebut. Jalankan script ini melalui SQL Editor. Script harus berhasil, bukan hanya membuat akun Auth.
6. Jika hanya mencoba aplikasi, jalankan `supabase/demo-data.sql` sekali. Jangan menjalankannya pada toko produksi. Demo dapat mencampur data laporan dan akan ditolak jika SKU yang sama sudah ada.
7. Ambil **Project URL** dan **publishable key** atau legacy **anon key** dari pengaturan API proyek. Jangan mengambil `service_role` atau secret key.
8. Matikan pendaftaran pengguna publik jika tidak digunakan. Aplikasi tidak menyediakan formulir pendaftaran; pengguna baru selalu tidak aktif hingga owner menyetujui.

## 3. Upload ke GitHub

Vercel mengimpor **repository Git**, bukan ZIP melalui menu Import Git Repository.

1. Ekstrak ZIP. Di dalamnya ada folder `bm-pos`.
2. Buat repository GitHub pribadi, misalnya `bm-pos`.
3. Unggah **isi folder bm-pos**, sehingga `package.json` berada di root repository. Sertakan folder app, components, lib, public, supabase, tests, serta package-lock.json, tsconfig.json, next.config.ts dan file konfigurasi lainnya.
4. Jangan mengunggah `node_modules`, `.next`, atau `.env.local`.
5. Jika seluruh folder `bm-pos` diunggah sebagai subfolder, nanti isi Root Directory Vercel dengan `bm-pos`.

Alternatif melalui terminal pada folder proyek:

```bash
npm ci
cp .env.example .env.local
# Isi .env.local dengan URL dan publishable/anon key Supabase Anda.
npm run dev
```

Windows PowerShell menggunakan `Copy-Item .env.example .env.local`. Buka alamat yang ditampilkan terminal. Gunakan Node.js LTS 22 atau 24.

## 4. Import ke Vercel

1. Masuk https://vercel.com/new dan hubungkan GitHub.
2. Pilih repository `bm-pos`, klik **Import**.
3. Framework Preset: **Next.js**.
4. Root Directory: `.` bila package.json ada di root; jika tidak, pilih folder yang memuat package.json.
5. Build Command: `npm run build`.
6. Install Command: `npm ci`.
7. Output Directory: biarkan default Next.js, jangan isi `dist` atau `out`.
8. Gunakan Node.js 22.x atau 24.x yang tersedia pada Vercel.
9. Tambahkan Environment Variables berikut sebelum Deploy:

| Nama | Nilai |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | URL proyek, misalnya `https://xxxx.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Publishable key atau legacy anon key proyek yang sama |

10. Deploy. Setelah berhasil, buka URL `.vercel.app` yang diberikan Vercel.
11. Di Supabase → Authentication → URL Configuration, isi **Site URL** dengan URL produksi dan tambahkan URL produksi ke daftar Redirect URLs agar reset password kembali ke aplikasi.
12. Untuk preview branch, gunakan proyek Supabase demo terpisah melalui environment Preview. Daftarkan URL preview yang diperlukan secara spesifik. Jangan menghubungkan pengujian destruktif ke produksi.
13. Setelah mengubah environment variables berawalan NEXT_PUBLIC, lakukan **Redeploy** karena nilainya masuk ke build frontend.

Tidak perlu mengunggah SQL ke Vercel untuk dijalankan: SQL dijalankan di Supabase pada langkah 2. Vercel menyajikan aplikasi; Supabase menyediakan Auth, database, dan transaksi server. Kunci publishable memang boleh berada di browser; akses dilindungi RLS dan validasi RPC.

## 5. Langkah pertama setelah login

1. Owner membuka Pengaturan: nama toko, alamat, telepon, pajak, batas diskon kasir, pesan struk, lebar 58/80 mm, URL gambar QRIS.
2. Tambah produk: SKU, nama, kategori, satuan, harga modal/jual, batas minimum stok. Variasi ukuran/rasa dapat dimasukkan sebagai SKU terpisah.
3. Tambahkan stok awal melalui Persediaan → Sesuaikan, masukkan **saldo stok akhir** dan alasan. Jangan memasukkan jumlah tambahan ke kolom saldo akhir.
4. Pembelian → Terima barang digunakan untuk stok masuk dari pemasok, sekaligus memperbarui biaya rata-rata tertimbang.
5. Kasir membuka Shift & Kas, masukkan modal awal laci.
6. Buka Kasir, pilih produk atau scan barcode, tentukan jumlah, pelanggan, dan diskon.
7. Klik Bayar sekarang. Pilih metode dan masukkan nominal yang diterima.
8. Cetak struk melalui dialog browser atau simpan sebagai PDF.
9. Saat selesai, hitung uang fisik dan tutup shift. Selisih ditampilkan pada riwayat shift.

### Pembayaran dan retur

- **Tunai:** uang diterima harus memenuhi total; kembalian dihitung.
- **QRIS / transfer:** petugas memeriksa dana masuk di aplikasi merchant/bank, mencentang verifikasi, dan mengisi nominal tepat. BM POS tidak memverifikasi bank secara otomatis.
- **Piutang:** hanya owner/admin, wajib pelanggan; dibuat tanpa uang muka (nominal 0). Pelunasan tunai bertahap melalui Laporan → Piutang dan membutuhkan shift aktif.
- QRIS menggunakan URL HTTPS gambar QRIS usaha Anda. Upload gambar melalui storage/hosting milik Anda dahulu. URL yang dapat diakses publik harus hanya berisi QRIS merchant, bukan bukti bayar atau data sensitif.
- Retur melalui Transaksi → Detail → Retur barang, hanya owner/admin dengan shift aktif. Isi jumlah, alasan dan apakah stok dikembalikan.
- Pengembalian dana dilakukan manual dengan metode asal; sistem hanya mencatat. Periksa dan lakukan pengembalian dana sebelum konfirmasi. Retur penjualan kredit belum didukung.
- Barang retur rusak tidak kembali ke stok. Biayanya tetap dimasukkan sebagai biaya/kerugian dalam laporan operasional.

## 6. Tim dan hak akses

Buat user baru melalui dashboard Supabase Authentication, kemudian owner mengaktifkan dan menetapkan role melalui Tim & Akses. Jangan membagikan akun owner untuk seluruh tim.

| Role | Akses utama |
| --- | --- |
| Owner | Seluruh modul, pengaturan toko, aktivasi/role pengguna |
| Admin | Produk, harga/modal, kasir, pembelian, pelanggan, stok, retur, laporan, biaya |
| Kasir | Kasir, transaksi miliknya, pelanggan, shift dan kas sendiri; harga modal tersembunyi |
| Admin Gudang | Katalog tanpa modal, stok dan mutasi, penerimaan pembelian, pemasok |

Admin Gudang dapat memasukkan dan melihat biaya pembelian untuk tugas penerimaan barang, tetapi tidak mendapat kolom modal produk. Akun tidak aktif tidak dapat menjalankan transaksi. Owner tidak bisa menonaktifkan atau menurunkan role dirinya sendiri melalui UI.

Reset password: isi email pada login lalu Lupa password. Supabase mengirim tautan sesuai konfigurasi email; untuk operasional, konfigurasikan SMTP yang sesuai. Jangan menganggap pengiriman email berhasil sebelum diuji pada proyek Anda.

## 7. Import dan ekspor produk

Menu Produk menyediakan template CSV, upload, preview, validasi dan import. SKU yang sudah ada diperbarui; SKU baru ditambahkan. Import tidak mengubah stok. Gunakan Persediaan untuk stok awal.

Kolom template: lihat tombol **Template CSV** pada aplikasi. Gunakan UTF-8, pemisah koma, nominal tanpa `Rp`/pemisah ribuan. Simpan barcode sebagai teks agar angka nol awal tidak hilang. Ekspor CSV mengamankan karakter formula spreadsheet.

## 8. Printer

Gunakan printer thermal 58/80 mm yang sudah terpasang driver atau tersedia melalui layanan cetak perangkat. Pada dialog cetak: pilih ukuran kertas yang benar, margin minimum, skala 100%, matikan header/footer browser.

Lebar isi mengikuti pengaturan struk; periksa hasil pada printer sebelum operasional. Untuk Android, mungkin perlu aplikasi/layanan cetak vendor. Bluetooth langsung dari browser tidak didukung universal dan paket ini tidak menyertakan driver atau bridge ESC/POS. PDF tersedia melalui **Save as PDF** pada dialog cetak. Laporan juga dapat dicetak/PDF.

## 9. Perhitungan dan konsistensi

- Uang disimpan sebagai PostgreSQL `numeric(18,2)`, kuantitas `numeric(18,3)`. UI menampilkan maksimal dua angka desimal agar angka pecahan tidak tersembunyi.
- Subtotal adalah jumlah nilai item yang dibulatkan 2 desimal. Diskon nominal transaksi dikurangkan sebelum pajak; pajak eksklusif ditambahkan dan dibulatkan 2 desimal.
- Harga dan biaya item disalin saat checkout. Perubahan harga sesudahnya tidak mengubah transaksi lama.
- Pembelian memakai biaya rata-rata tertimbang dari stok dan biaya sebelumnya.
- Checkout mengunci produk dalam urutan stabil; stok, pembayaran, item, dan transaksi disimpan dalam satu transaksi SQL.
- Idempotency key mencegah permintaan checkout yang sama mencatat transaksi dua kali.
- Retur dibatasi kuantitas asli yang belum diretur; pembulatan kumulatif mencegah kelebihan pengembalian.
- Kas seharusnya = modal + penerimaan tunai + kas masuk − kas keluar/biaya − refund tunai pada shift tersebut. QRIS/transfer tidak menambah laci.
- Laporan memakai tanggal Jakarta. Penjualan neto mengecualikan pajak dan retur; retur dialokasikan pada transaksi asal. Estimasi laba dikurangi biaya operasional yang tercatat. Ini bukan laporan akuntansi formal atau laporan pajak.
- Data dibaca bertahap melalui pagination; layar transaksi menampilkan 25 baris per halaman. Volume sangat besar perlu agregasi/reporting di database untuk performa.

## 10. Mode pratinjau dan PWA

Tanpa environment Supabase, aplikasi tetap menampilkan halaman setup/login dan pratinjau kasir. Data pratinjau tidak disimpan dan checkout tidak aktif.

Manifest dan ikon tersedia untuk pemasangan sesuai dukungan browser. Service worker tidak menyimpan data transaksi sensitif. Saat offline, simpan keranjang sebagai draft; login/checkout memerlukan internet. Ini bukan POS offline penuh. Draft tersimpan per akun pada perangkat yang sama, bukan sinkronisasi antarperangkat.

## 11. Backup dan pemulihan

- Ekspor CSV untuk laporan/pertukaran data, bukan backup database lengkap.
- Gunakan fasilitas backup Supabase sesuai paket Anda atau `pg_dump` melalui koneksi yang disarankan Supabase.
- Simpan backup terenkripsi di lokasi terpisah; uji restore ke proyek nonproduksi.
- Pengguna Supabase Auth juga perlu strategi backup/migrasi terpisah yang sesuai dokumentasi penyedia.
- Jangan membagikan password database, service key, atau dump berisi data pelanggan melalui repository publik.

## 12. Pengujian

```bash
npm ci
npm run typecheck
npm run lint
npm test
npm run build
```

`npm test` menjalankan 19 kelompok uji integrasi PostgreSQL lokal melalui PGlite: checkout atomik, idempotency, stok kurang/rollback, QRIS, pajak, biaya rata-rata, retur parsial/penuh/batas/pembulatan, piutang, tutup shift, dan RLS untuk kasir/gudang/nonaktif/anonim.

PGlite menggunakan simulasi Auth; tidak menggantikan pengujian Supabase Auth/PostgREST nyata dan stress test dua koneksi bersamaan. Lakukan UAT menggunakan data demo: login setiap role, transaksi kecil, retur, tutup shift, struk di printer Anda, dan reset password. Database menggunakan penguncian SQL, namun uji kompetisi koneksi produksi tetap harus dilakukan pada lingkungan staging.

## 13. Batasan versi 1.0

Tersedia: satu toko, empat role, kasir, diskon transaksi, pajak eksklusif, draft, tunai/QRIS/transfer manual/piutang, struk, produk/barcode satuan/timbang, CSV, stok/mutasi, penerimaan pembelian, pemasok/pelanggan, retur nonkredit, shift, biaya, laporan, pengaturan, audit database.

Belum termasuk: multicabang/transfer stok antar lokasi, pembayaran gabungan, PO dan penerimaan parsial berdasarkan PO, utang pemasok, loyalty/member/grosir otomatis, batch/expired, dapur/meja, diskon per item, service charge, pajak inklusif, upload gambar produk/QRIS melalui UI, label barcode cetak, XLSX langsung, invoice A4 khusus, audit viewer UI, automation/notifikasi, dan offline checkout. Tidak ada tombol palsu untuk fitur tersebut.

Fitur-fitur itu memerlukan migrasi lanjutan, bukan sekadar mengaktifkan menu. Paket ini **tidak mengklaim seluruh roadmap awal telah selesai**. Biaya serta kuota Vercel, Supabase, SMTP, dan storage mengikuti akun/paket penyedia; pilih paket yang mengizinkan penggunaan bisnis Anda.

## 14. Pemecahan masalah

- **Masih terlihat konfigurasi Supabase:** cek kedua environment variable, scope Production, dan redeploy.
- **Akun belum aktif:** jalankan setup-owner untuk owner atau minta owner mengaktifkan anggota.
- **Relation/function does not exist:** pastikan schema.sql selesai sukses pada proyek yang sama dengan URL aplikasi.
- **Buka shift terlebih dahulu:** setiap kasir/admin harus membuka shift miliknya, termasuk untuk retur dan pelunasan.
- **Stok tidak valid:** periksa saldo, qty, status produk dan muat ulang. Jangan ubah stok langsung di tabel produksi.
- **Pajak berubah:** refresh aplikasi untuk mengambil pengaturan baru.
- **Reset password tidak tiba:** cek email, Site URL, Redirect URLs, log Auth, SMTP dan folder spam.
- **Import Vercel gagal:** pastikan package.json ada pada Root Directory, gunakan npm ci dan Node 22/24, lalu baca Build Logs.

Referensi resmi: https://vercel.com/docs/frameworks/full-stack/nextjs · https://supabase.com/docs/guides/auth · https://supabase.com/docs/guides/database/postgres/row-level-security
