-- BM POS • Fresh Supabase project migration. Run once in SQL Editor.
-- No service_role key is required in the application.
begin;
create extension if not exists pgcrypto;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null default '', role text not null default 'cashier' check(role in ('owner','admin','cashier','warehouse')),
 active boolean not null default false, created_at timestamptz not null default now()
);
create function public.new_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,name) values(new.id,coalesce(new.raw_user_meta_data->>'name',split_part(new.email,'@',1))); return new; end $$;
create trigger bm_new_user after insert on auth.users for each row execute function public.new_profile();
create function public.app_role() returns text language sql stable security definer set search_path=public as $$
 select role from public.profiles where id=auth.uid() and active=true
$$;
create function public.require_role(allowed text[]) returns void language plpgsql stable security definer set search_path=public as $$
begin if auth.uid() is null or not coalesce(public.app_role()=any(allowed),false) then raise exception 'Akses ditolak atau akun belum aktif'; end if; end $$;

create table public.settings (
 id integer primary key default 1 check(id=1), store_name text not null default 'BM POS',address text not null default '',phone text not null default '',
 tax_rate numeric(5,2) not null default 0 check(tax_rate between 0 and 100),qris_url text not null default '',
 receipt_footer text not null default 'Terima kasih telah berbelanja!',receipt_width integer not null default 80 check(receipt_width in(58,80)),
 max_cashier_discount numeric(5,2) not null default 10 check(max_cashier_discount between 0 and 100)
);
insert into public.settings(id) values(1);
create table public.products (
 id uuid primary key default gen_random_uuid(),sku text not null unique check(length(trim(sku))>0),barcode text unique,
 name text not null check(length(trim(name))>0),category text not null default 'Umum',unit text not null default 'pcs',
 price numeric(18,2) not null default 0 check(price>=0),cost numeric(18,2) not null default 0 check(cost>=0),
 stock numeric(18,3) not null default 0 check(stock>=0),min_stock numeric(18,3) not null default 5 check(min_stock>=0),
 active boolean not null default true,created_at timestamptz not null default now()
);
create table public.customers(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name))>0),phone text not null default '',address text not null default '',created_at timestamptz not null default now());
create table public.suppliers(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name))>0),phone text not null default '',address text not null default '',created_at timestamptz not null default now());
create table public.shifts(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),
 opening_cash numeric(18,2) not null check(opening_cash>=0),expected_cash numeric(18,2),actual_cash numeric(18,2),difference numeric(18,2),
 opened_at timestamptz not null default now(),closed_at timestamptz
);
create unique index one_open_shift on public.shifts(user_id) where closed_at is null;
create table public.sales(
 id uuid primary key default gen_random_uuid(),number bigint generated always as identity unique,
 cashier_id uuid not null references public.profiles(id),shift_id uuid not null references public.shifts(id),customer_id uuid references public.customers(id),
 subtotal numeric(18,2) not null,discount numeric(18,2) not null,tax_rate numeric(5,2) not null,tax numeric(18,2) not null,total numeric(18,2) not null,
 paid numeric(18,2) not null default 0,tendered numeric(18,2) not null default 0,change_amount numeric(18,2) not null default 0,
 method text not null check(method in('cash','qris','transfer','credit')),status text not null check(status in('paid','credit','partial_refund','refunded')),
 idempotency uuid not null unique,created_at timestamptz not null default now()
);
create table public.sale_items(
 id uuid primary key default gen_random_uuid(),sale_id uuid not null references public.sales(id),product_id uuid not null references public.products(id),
 name text not null,sku text not null,qty numeric(18,3) not null check(qty>0),price numeric(18,2) not null,cost numeric(18,2) not null,
 line_total numeric(18,2) not null,net_total numeric(18,2) not null,returned_qty numeric(18,3) not null default 0 check(returned_qty>=0 and returned_qty<=qty),unique(sale_id,product_id)
);
create table public.payments(
 id uuid primary key default gen_random_uuid(),sale_id uuid not null references public.sales(id),shift_id uuid not null references public.shifts(id),user_id uuid not null references public.profiles(id),
 amount numeric(18,2) not null check(amount>0),method text not null check(method in('cash','qris','transfer')),verified_by uuid references public.profiles(id),created_at timestamptz not null default now()
);
create table public.sale_returns(
 id uuid primary key default gen_random_uuid(),sale_id uuid not null references public.sales(id),amount numeric(18,2) not null,
 reason text not null,restock boolean not null,created_by uuid not null references public.profiles(id),shift_id uuid not null references public.shifts(id),
 refund_method text not null check(refund_method in('cash','qris','transfer','credit')),created_at timestamptz not null default now()
);
create table public.return_items(
 id uuid primary key default gen_random_uuid(),return_id uuid not null references public.sale_returns(id),sale_item_id uuid not null references public.sale_items(id),qty numeric(18,3) not null check(qty>0),amount numeric(18,2) not null
);
create table public.stock_movements(
 id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id),qty numeric(18,3) not null,balance numeric(18,3) not null,
 kind text not null,reference_id uuid,reason text not null default '',created_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);
create table public.purchases(id uuid primary key default gen_random_uuid(),supplier_id uuid references public.suppliers(id),total numeric(18,2) not null,note text not null default '',created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create table public.purchase_items(id uuid primary key default gen_random_uuid(),purchase_id uuid not null references public.purchases(id),product_id uuid not null references public.products(id),qty numeric(18,3) not null,cost numeric(18,2) not null,total numeric(18,2) not null);
create table public.cash_movements(id uuid primary key default gen_random_uuid(),shift_id uuid not null references public.shifts(id),kind text not null check(kind in('in','out','expense')),amount numeric(18,2) not null check(amount>0),note text not null,created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create table public.expenses(id uuid primary key default gen_random_uuid(),amount numeric(18,2) not null check(amount>0),note text not null,shift_id uuid not null references public.shifts(id),created_by uuid not null references public.profiles(id),created_at timestamptz not null default now());
create table public.audit_logs(id uuid primary key default gen_random_uuid(),actor_id uuid references public.profiles(id),action text not null,entity_id uuid,detail jsonb not null default '{}',created_at timestamptz not null default now());
create index sales_created_idx on public.sales(created_at desc);
create index sale_items_sale_idx on public.sale_items(sale_id);
create index payments_sale_idx on public.payments(sale_id);
create index movements_product_idx on public.stock_movements(product_id,created_at desc);
create index returns_sale_idx on public.sale_returns(sale_id);
create index products_name_idx on public.products(name);

-- API roles cannot overwrite stock; every stock update is made in an atomic RPC.
create function public.protect_stock() returns trigger language plpgsql set search_path=public as $$
begin
 if current_user in ('authenticated','anon') then
  if (TG_OP='INSERT' and new.stock<>0) or (TG_OP='UPDATE' and new.stock<>old.stock) then raise exception 'Gunakan fungsi penyesuaian stok'; end if;
 end if;
 return new;
end $$;
create trigger protect_product_stock before insert or update on public.products for each row execute function public.protect_stock();
create function public.audit_product() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'product.'||lower(TG_OP),new.id,jsonb_build_object('sku',new.sku)); return new; end $$;
create trigger audit_product_write after insert or update on public.products for each row execute function public.audit_product();

create function public.set_member_role(p_user_id uuid,p_name text,p_role text,p_active boolean) returns void language plpgsql security definer set search_path=public as $$
begin
 perform public.require_role(array['owner']);
 if p_user_id=auth.uid() and (p_role<>'owner' or not p_active) then raise exception 'Owner tidak dapat menonaktifkan dirinya sendiri'; end if;
 if p_role not in('owner','admin','cashier','warehouse') or p_active is null then raise exception 'Role tidak valid'; end if;
 update public.profiles set name=p_name,role=p_role,active=p_active where id=p_user_id;
 if not found then raise exception 'Pengguna belum dibuat di Supabase Auth'; end if;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'member.update',p_user_id,jsonb_build_object('role',p_role,'active',p_active));
end $$;
create function public.open_shift(p_opening_cash numeric) returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 perform public.require_role(array['owner','admin','cashier']);
 if p_opening_cash is null or p_opening_cash<0 or p_opening_cash>1e12 or p_opening_cash<>round(p_opening_cash,2) then raise exception 'Modal awal tidak valid'; end if;
 insert into public.shifts(user_id,opening_cash) values(auth.uid(),p_opening_cash) returning id into sid; return sid;
end $$;
create function public.current_shift() returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 select id into sid from public.shifts where user_id=auth.uid() and closed_at is null for update;
 if sid is null then raise exception 'Buka shift kasir terlebih dahulu'; end if; return sid;
end $$;
create function public.close_shift(p_shift_id uuid,p_actual_cash numeric) returns void language plpgsql security definer set search_path=public as $$
declare s public.shifts; expected numeric;
begin
 perform public.require_role(array['owner','admin','cashier']);
 if p_actual_cash is null or p_actual_cash<0 or p_actual_cash>1e12 or p_actual_cash<>round(p_actual_cash,2) then raise exception 'Kas aktual tidak valid'; end if;
 select * into s from public.shifts where id=p_shift_id for update;
 if s.id is null or s.user_id<>auth.uid() or s.closed_at is not null then raise exception 'Shift tidak tersedia'; end if;
 select s.opening_cash+coalesce((select sum(amount) from public.payments where shift_id=s.id and method='cash'),0)
  +coalesce((select sum(case when kind='in' then amount else -amount end) from public.cash_movements where shift_id=s.id),0)
  -coalesce((select sum(amount) from public.sale_returns where shift_id=s.id and refund_method='cash'),0) into expected;
 update public.shifts set expected_cash=expected,actual_cash=p_actual_cash,difference=p_actual_cash-expected,closed_at=now() where id=s.id;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'shift.close',s.id,jsonb_build_object('expected',expected,'actual',p_actual_cash));
end $$;

create function public.checkout(p_items jsonb,p_discount numeric,p_tax_rate numeric,p_method text,p_paid numeric,p_customer_id uuid,p_idempotency uuid,p_verified boolean default false)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; saleid uuid; existing public.sales; r record; cfg public.settings; subtotal numeric:=0; tax numeric; total numeric; applied numeric; line numeric; net numeric; allocated numeric:=0; raw_allocated numeric:=0; counter integer:=0; cnt integer; q numeric; pr public.products;
begin
 perform public.require_role(array['owner','admin','cashier']);
 if p_idempotency is null then raise exception 'Kunci transaksi wajib diisi'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency::text,0));
 select * into existing from public.sales where idempotency=p_idempotency;
 if existing.id is not null then
  if existing.cashier_id<>auth.uid() then raise exception 'Kunci transaksi sudah digunakan'; end if; return existing.id;
 end if;
 sid:=public.current_shift();
 select * into cfg from public.settings where id=1;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 200 then raise exception 'Keranjang tidak valid'; end if;
 if p_items is null or p_discount is null or p_tax_rate is null or p_paid is null or p_method is null then raise exception 'Data pembayaran tidak lengkap'; end if;
 if p_method not in('cash','qris','transfer','credit') or p_paid<0 or p_paid>1e12 or p_paid<>round(p_paid,2) then raise exception 'Pembayaran tidak valid'; end if;
 if p_tax_rate<>cfg.tax_rate then raise exception 'Pajak telah berubah, muat ulang kasir'; end if;
 if p_method in('qris','transfer') and not coalesce(p_verified,false) then raise exception 'Verifikasi penerimaan pembayaran terlebih dahulu'; end if;
 if p_method='credit' then
  perform public.require_role(array['owner','admin']);
  if p_customer_id is null then raise exception 'Pelanggan wajib untuk piutang'; end if;
 end if;
 select count(distinct value->>'product_id') into cnt from jsonb_array_elements(p_items);
 if cnt<>jsonb_array_length(p_items) then raise exception 'Produk duplikat/tidak valid'; end if;
 -- Lock in stable order; a second till will recheck the latest stock after waiting.
 for r in select p.*, (x.value->>'qty')::numeric as requested_qty from jsonb_array_elements(p_items) x join public.products p on p.id=(x.value->>'product_id')::uuid order by p.id for update of p loop
  q:=r.requested_qty;
  if q is null or q<=0 or q>1e6 or q<>round(q,3) or not r.active or r.stock<q then raise exception 'Stok/kuantitas tidak valid: %',r.name; end if;
  subtotal:=subtotal+round(r.price*q,2); counter:=counter+1;
 end loop;
 if counter<>cnt or subtotal<=0 then raise exception 'Produk tidak ditemukan atau total nol'; end if;
 if p_discount<0 or p_discount>subtotal or p_discount<>round(p_discount,2) then raise exception 'Diskon tidak valid'; end if;
 if public.app_role()='cashier' and p_discount>round(subtotal*cfg.max_cashier_discount/100,2) then raise exception 'Diskon melebihi batas kasir'; end if;
 tax:=round((subtotal-p_discount)*p_tax_rate/100,2); total:=subtotal-p_discount+tax;
 if total<=0 then raise exception 'Total transaksi harus positif'; end if;
 if p_method='credit' then
  if p_paid<>0 then raise exception 'Penjualan kredit dibuat tanpa uang muka; catat pelunasan terpisah'; end if; applied:=0;
 else
  if p_paid<total then raise exception 'Pembayaran kurang'; end if;
  if p_method<>'cash' and p_paid<>total then raise exception 'Pembayaran nontunai harus sesuai total'; end if;
  applied:=total;
 end if;
 insert into public.sales(cashier_id,shift_id,customer_id,subtotal,discount,tax_rate,tax,total,paid,tendered,change_amount,method,status,idempotency)
 values(auth.uid(),sid,p_customer_id,subtotal,p_discount,p_tax_rate,tax,total,applied,p_paid,case when p_method='cash' then p_paid-total else 0 end,p_method,case when p_method='credit' then 'credit' else 'paid' end,p_idempotency) returning id into saleid;
 counter:=0;
 for r in select p.*, (x.value->>'qty')::numeric as requested_qty from jsonb_array_elements(p_items) x join public.products p on p.id=(x.value->>'product_id')::uuid order by p.id loop
  counter:=counter+1; q:=r.requested_qty; line:=round(r.price*q,2);
  raw_allocated:=raw_allocated+line; net:=round(raw_allocated/subtotal*total,2)-allocated; allocated:=allocated+net;
  insert into public.sale_items(sale_id,product_id,name,sku,qty,price,cost,line_total,net_total) values(saleid,r.id,r.name,r.sku,q,r.price,r.cost,line,net);
  update public.products set stock=stock-q where id=r.id;
  insert into public.stock_movements(product_id,qty,balance,kind,reference_id,created_by) values(r.id,-q,r.stock-q,'sale',saleid,auth.uid());
 end loop;
 if applied>0 then insert into public.payments(sale_id,shift_id,user_id,amount,method,verified_by) values(saleid,sid,auth.uid(),applied,p_method,case when p_method in('qris','transfer') then auth.uid() else null end); end if;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'sale.checkout',saleid,jsonb_build_object('total',total,'method',p_method,'manual_verified',p_verified));
 return saleid;
end $$;

create function public.set_stock(p_product_id uuid,p_stock numeric,p_reason text) returns void language plpgsql security definer set search_path=public as $$
declare pr public.products;
begin
 perform public.require_role(array['owner','admin','warehouse']);
 if p_stock is null or p_stock<0 or p_stock>1e9 or p_stock<>round(p_stock,3) or length(trim(coalesce(p_reason,'')))<3 then raise exception 'Stok atau alasan tidak valid'; end if;
 select * into pr from public.products where id=p_product_id for update;
 if pr.id is null then raise exception 'Produk tidak ditemukan'; end if;
 update public.products set stock=p_stock where id=pr.id;
 insert into public.stock_movements(product_id,qty,balance,kind,reason,created_by) values(pr.id,p_stock-pr.stock,p_stock,'adjustment',p_reason,auth.uid());
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'stock.adjustment',pr.id,jsonb_build_object('before',pr.stock,'after',p_stock,'reason',p_reason));
end $$;
create function public.receive_purchase(p_supplier_id uuid,p_items jsonb,p_note text default '') returns uuid language plpgsql security definer set search_path=public as $$
declare pid uuid; r record; total numeric:=0; cnt integer:=0; q numeric; c numeric;
begin
 perform public.require_role(array['owner','admin','warehouse']);
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 200 then raise exception 'Item pembelian tidak valid'; end if;
 if (select count(distinct value->>'product_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'Produk duplikat'; end if;
 for r in select p.*, (x.value->>'qty')::numeric q,(x.value->>'cost')::numeric c from jsonb_array_elements(p_items) x join public.products p on p.id=(x.value->>'product_id')::uuid order by p.id for update of p loop
  if r.q is null or r.c is null or r.q<=0 or r.q>1e6 or r.q<>round(r.q,3) or r.c<0 or r.c>1e12 or r.c<>round(r.c,2) then raise exception 'Jumlah/harga beli tidak valid'; end if;
  total:=total+round(r.q*r.c,2); cnt:=cnt+1;
 end loop;
 if cnt<>jsonb_array_length(p_items) then raise exception 'Produk tidak ditemukan'; end if;
 insert into public.purchases(supplier_id,total,note,created_by) values(p_supplier_id,total,coalesce(p_note,''),auth.uid()) returning id into pid;
 for r in select p.*, (x.value->>'qty')::numeric q,(x.value->>'cost')::numeric c from jsonb_array_elements(p_items) x join public.products p on p.id=(x.value->>'product_id')::uuid order by p.id loop
  update public.products set cost=round((stock*cost+r.q*r.c)/(stock+r.q),2),stock=stock+r.q where id=r.id;
  insert into public.purchase_items(purchase_id,product_id,qty,cost,total) values(pid,r.id,r.q,r.c,round(r.q*r.c,2));
  insert into public.stock_movements(product_id,qty,balance,kind,reference_id,created_by) values(r.id,r.q,r.stock+r.q,'purchase',pid,auth.uid());
 end loop;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'purchase.receive',pid,jsonb_build_object('total',total)); return pid;
end $$;

create function public.pay_debt(p_sale_id uuid,p_amount numeric,p_method text,p_verified boolean default false) returns uuid language plpgsql security definer set search_path=public as $$
declare s public.sales; sid uuid; pid uuid;
begin
 perform public.require_role(array['owner','admin','cashier']); sid:=public.current_shift();
 select * into s from public.sales where id=p_sale_id for update;
 if s.id is null or s.method<>'credit' or s.status<>'credit' then raise exception 'Piutang tidak tersedia'; end if;
 if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>s.total-s.paid then raise exception 'Jumlah melebihi sisa piutang'; end if;
 if p_method is null or p_method not in('cash','qris','transfer') then raise exception 'Metode tidak valid'; end if;
 if p_method in('qris','transfer') and not coalesce(p_verified,false) then raise exception 'Verifikasi penerimaan dana terlebih dahulu'; end if;
 insert into public.payments(sale_id,shift_id,user_id,amount,method,verified_by) values(s.id,sid,auth.uid(),p_amount,p_method,case when p_method in('qris','transfer') then auth.uid() else null end) returning id into pid;
 update public.sales set paid=paid+p_amount,status=case when paid+p_amount=total then 'paid' else 'credit' end where id=s.id;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'debt.payment',s.id,jsonb_build_object('amount',p_amount,'method',p_method)); return pid;
end $$;
create function public.add_cash_movement(p_amount numeric,p_kind text,p_note text) returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; mid uuid;
begin
 perform public.require_role(array['owner','admin','cashier']); sid:=public.current_shift();
 if p_amount is null or p_amount<=0 or p_amount>1e12 or p_amount<>round(p_amount,2) or p_kind is null or p_kind not in('in','out','expense') or length(trim(coalesce(p_note,'')))<3 then raise exception 'Mutasi kas tidak valid'; end if;
 insert into public.cash_movements(shift_id,kind,amount,note,created_by) values(sid,p_kind,p_amount,p_note,auth.uid()) returning id into mid;
 if p_kind='expense' then insert into public.expenses(id,amount,note,shift_id,created_by) values(mid,p_amount,p_note,sid,auth.uid()); end if;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'cash.'||p_kind,mid,jsonb_build_object('amount',p_amount,'note',p_note)); return mid;
end $$;

-- Refunds are paid manually by the operator using original payment method.
-- Credit returns are intentionally rejected to avoid silently netting partial debt payments.
create function public.return_sale(p_sale_id uuid,p_items jsonb,p_reason text,p_restock boolean default true) returns uuid language plpgsql security definer set search_path=public as $$
declare s public.sales; sid uuid; rid uuid; r record; q numeric; refund_amount numeric:=0; line_refund numeric; cnt integer:=0; refunded_before numeric; balance numeric;
begin
 perform public.require_role(array['owner','admin']); sid:=public.current_shift();
 select * into s from public.sales where id=p_sale_id for update;
 if s.id is null or s.status not in('paid','partial_refund') or s.method='credit' then raise exception 'Retur hanya untuk penjualan tunai/nontunai yang dibayar penuh'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 200 or length(trim(coalesce(p_reason,'')))<3 or p_restock is null then raise exception 'Data retur tidak valid'; end if;
 if (select count(distinct value->>'sale_item_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'Item retur duplikat'; end if;
 for r in select i.*, (x.value->>'qty')::numeric q from jsonb_array_elements(p_items) x join public.sale_items i on i.id=(x.value->>'sale_item_id')::uuid where i.sale_id=s.id order by i.product_id for update of i loop
  if r.q is null or r.q<=0 or r.q<>round(r.q,3) or r.q>r.qty-r.returned_qty then raise exception 'Jumlah retur melebihi sisa item'; end if;
  cnt:=cnt+1;
 end loop;
 if cnt<>jsonb_array_length(p_items) then raise exception 'Item retur tidak ditemukan'; end if;
 -- All product locks are acquired before any updates, matching checkout order.
 perform p.id from public.products p join public.sale_items i on i.product_id=p.id join jsonb_array_elements(p_items) x on i.id=(x.value->>'sale_item_id')::uuid where i.sale_id=s.id order by p.id for update of p;
 insert into public.sale_returns(sale_id,amount,reason,restock,created_by,shift_id,refund_method) values(s.id,0,p_reason,p_restock,auth.uid(),sid,s.method) returning id into rid;
 for r in select i.*, (x.value->>'qty')::numeric q from jsonb_array_elements(p_items) x join public.sale_items i on i.id=(x.value->>'sale_item_id')::uuid where i.sale_id=s.id order by i.product_id loop
  -- Cumulative rounding makes split refunds sum to the exact original paid amount.
  line_refund:=round(r.net_total*(r.returned_qty+r.q)/r.qty,2)-round(r.net_total*r.returned_qty/r.qty,2); refund_amount:=refund_amount+line_refund;
  insert into public.return_items(return_id,sale_item_id,qty,amount) values(rid,r.id,r.q,line_refund);
  update public.sale_items set returned_qty=returned_qty+r.q where id=r.id;
  if p_restock then
   update public.products set cost=round((stock*cost+r.q*r.cost)/(stock+r.q),2),stock=stock+r.q where id=r.product_id returning stock into balance;
   insert into public.stock_movements(product_id,qty,balance,kind,reference_id,reason,created_by) values(r.product_id,r.q,balance,'return',rid,p_reason,auth.uid());
  end if;
 end loop;
 update public.sale_returns set amount=refund_amount where id=rid;
 update public.sales set status=case when not exists(select 1 from public.sale_items where sale_id=s.id and returned_qty<qty) then 'refunded' else 'partial_refund' end where id=s.id;
 insert into public.audit_logs(actor_id,action,entity_id,detail) values(auth.uid(),'sale.return',rid,jsonb_build_object('amount',refund_amount,'restock',p_restock,'refund_manual',true)); return rid;
end $$;

create function public.audit_settings() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.audit_logs(actor_id,action,detail) values(auth.uid(),'settings.update',jsonb_build_object('before',to_jsonb(old),'after',to_jsonb(new)));
 return new;
end $$;
create trigger audit_settings_write after update on public.settings for each row execute function public.audit_settings();

-- RLS: no direct financial writes; privileged RPCs validate auth and roles.
do $$ declare t text; begin
 foreach t in array array['profiles','settings','products','customers','suppliers','shifts','sales','sale_items','payments','sale_returns','return_items','stock_movements','purchases','purchase_items','cash_movements','expenses','audit_logs'] loop
  execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.app_role() in('owner','admin'));
create policy settings_read on public.settings for select to authenticated using(public.app_role() is not null);
create policy settings_update on public.settings for update to authenticated using(public.app_role()='owner') with check(public.app_role()='owner');
create policy products_read on public.products for select to authenticated using(public.app_role() in('owner','admin'));
create policy products_insert on public.products for insert to authenticated with check(public.app_role() in('owner','admin') and stock=0);
create policy products_update on public.products for update to authenticated using(public.app_role() in('owner','admin')) with check(public.app_role() in('owner','admin'));
create policy customers_read on public.customers for select to authenticated using(public.app_role() in('owner','admin','cashier'));
create policy customers_insert on public.customers for insert to authenticated with check(public.app_role() in('owner','admin','cashier'));
create policy customers_update on public.customers for update to authenticated using(public.app_role() in('owner','admin')) with check(public.app_role() in('owner','admin'));
create policy suppliers_read on public.suppliers for select to authenticated using(public.app_role() in('owner','admin','warehouse'));
create policy suppliers_insert on public.suppliers for insert to authenticated with check(public.app_role() in('owner','admin','warehouse'));
create policy suppliers_update on public.suppliers for update to authenticated using(public.app_role() in('owner','admin','warehouse')) with check(public.app_role() in('owner','admin','warehouse'));
create policy shifts_read on public.shifts for select to authenticated using((public.app_role() in('owner','admin','cashier') and user_id=auth.uid()) or public.app_role() in('owner','admin'));
create policy sales_read on public.sales for select to authenticated using(public.app_role() in('owner','admin') or (public.app_role()='cashier' and cashier_id=auth.uid()));
create policy items_read on public.sale_items for select to authenticated using(public.app_role() in('owner','admin'));
create policy payments_read on public.payments for select to authenticated using(public.app_role() in('owner','admin') or (public.app_role()='cashier' and user_id=auth.uid()));
create policy returns_read on public.sale_returns for select to authenticated using(public.app_role() in('owner','admin') or (public.app_role()='cashier' and exists(select 1 from public.sales s where s.id=sale_returns.sale_id and s.cashier_id=auth.uid())));
create policy return_items_read on public.return_items for select to authenticated using(public.app_role() in('owner','admin'));
create policy stock_read on public.stock_movements for select to authenticated using(public.app_role() in('owner','admin','warehouse'));
create policy purchases_read on public.purchases for select to authenticated using(public.app_role() in('owner','admin','warehouse'));
create policy purchase_items_read on public.purchase_items for select to authenticated using(public.app_role() in('owner','admin','warehouse'));
create policy cash_read on public.cash_movements for select to authenticated using(public.app_role() in('owner','admin') or (public.app_role()='cashier' and created_by=auth.uid()));
create policy expenses_read on public.expenses for select to authenticated using(public.app_role() in('owner','admin') or (public.app_role()='cashier' and created_by=auth.uid()));
create policy audit_read on public.audit_logs for select to authenticated using(public.app_role() in('owner','admin'));

-- Definer views intentionally omit cost; their explicit role predicate is essential.
create view public.products_public with (security_barrier=true) as
 select id,sku,barcode,name,category,unit,price,stock,min_stock,active,created_at from public.products where public.app_role() is not null;
create view public.sale_items_public with (security_barrier=true) as
 select i.id,i.sale_id,i.product_id,i.name,i.sku,i.qty,i.price,i.line_total,i.net_total,i.returned_qty from public.sale_items i join public.sales s on s.id=i.sale_id
 where public.app_role() in('owner','admin') or (public.app_role()='cashier' and s.cashier_id=auth.uid());

revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.settings,public.products,public.products_public,public.customers,public.suppliers,public.shifts,public.sales,public.sale_items,public.sale_items_public,public.payments,public.sale_returns,public.return_items,public.stock_movements,public.purchases,public.purchase_items,public.cash_movements,public.expenses,public.audit_logs to authenticated;
grant insert,update on public.products,public.customers,public.suppliers to authenticated;
grant update on public.settings to authenticated;
revoke all on all functions in schema public from public,anon,authenticated;
grant execute on function public.app_role() to authenticated;
grant execute on function public.set_member_role(uuid,text,text,boolean),public.open_shift(numeric),public.close_shift(uuid,numeric),public.checkout(jsonb,numeric,numeric,text,numeric,uuid,uuid,boolean),public.set_stock(uuid,numeric,text),public.receive_purchase(uuid,jsonb,text),public.pay_debt(uuid,numeric,text,boolean),public.add_cash_movement(numeric,text,text),public.return_sale(uuid,jsonb,text,boolean) to authenticated;
commit;

-- AFTER creating your owner through Supabase Authentication > Users > Add user:
-- update public.profiles set role='owner',active=true,name='Owner BM POS'
-- where id=(select id from auth.users where email='YOUR_OWNER_EMAIL');
-- New users are INACTIVE until activated by owner in the app.
