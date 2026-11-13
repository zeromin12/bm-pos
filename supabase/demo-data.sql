-- OPSIONAL. Hanya untuk proyek demo, bukan database produksi.
-- Jalankan setelah schema.sql dan setup-owner.sql.
begin;
do $$
declare owner_id uuid; p record;
begin
 select id into owner_id from public.profiles where role='owner' and active limit 1;
 if owner_id is null then raise exception 'Aktifkan owner terlebih dahulu'; end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 insert into public.products(sku,barcode,name,category,unit,price,cost,min_stock) values
 ('KOP-001','89910001','Kopi Susu Gula Aren','Minuman','cup',18000,8500,10),
 ('ROT-001','89910002','Croissant Butter','Makanan','pcs',22000,12000,5),
 ('TEH-001','89910003','Matcha Latte','Minuman','cup',24000,11000,10),
 ('AIR-001','89910004','Air Mineral 600 ml','Minuman','botol',5000,2500,10),
 ('SNA-001','89910005','Cookies Chocolate','Snack','pcs',12000,6000,5),
 ('ROT-002','89910006','Roti Cokelat','Makanan','pcs',15000,7500,5);
 for p in select id from public.products where sku in('KOP-001','ROT-001','TEH-001','AIR-001','SNA-001','ROT-002') loop
  perform public.set_stock(p.id,30,'Stok awal DEMO');
 end loop;
 insert into public.customers(name,phone) values('Pelanggan Demo','');
 insert into public.suppliers(name,phone) values('Pemasok Demo','');
end $$;
commit;
