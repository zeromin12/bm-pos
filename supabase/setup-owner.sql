-- Jalankan SETELAH schema.sql dan SETELAH membuat pengguna di Authentication > Users.
-- Ganti email di bawah dengan email yang Anda buat. Bukan password.
do $$
declare owner_id uuid;
begin
 select id into owner_id from auth.users where lower(email)=lower('GANTI-EMAIL-OWNER@contoh.com');
 if owner_id is null then raise exception 'Email belum ditemukan. Buat user di Authentication dahulu.'; end if;
 insert into public.profiles(id,name,role,active) values(owner_id,'Owner BM POS','owner',true)
 on conflict(id) do update set role='owner',active=true;
end $$;
