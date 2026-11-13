'use client';

import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { Plus, Search, Download, Upload, Pencil, Archive, Save, X, Package, Truck, ShieldCheck, RefreshCw } from 'lucide-react';

type Row = Record<string, string | number | boolean | null>;
type Form = Record<string, string>;
type Props = { tab: string; db: SupabaseClient; role: string; refresh: () => void };
const money = (v: unknown) => new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', minimumFractionDigits: 0, maximumFractionDigits: 2 }).format(Number(v || 0));
const when = (v: unknown) => new Date(String(v)).toLocaleString('id-ID', { timeZone: 'Asia/Jakarta', dateStyle: 'medium', timeStyle: 'short' });
const str = (v: unknown) => String(v ?? '');
const titles: Record<string, [string, string]> = {
  products: ['Katalog produk', 'Kelola barang, harga jual, kategori, dan barcode toko Anda.'],
  inventory: ['Persediaan', 'Pantau stok dan catat setiap penyesuaian dengan alasan yang jelas.'],
  purchases: ['Pembelian barang', 'Terima barang dari pemasok. Stok dan biaya rata-rata diperbarui bersama.'],
  customers: ['Pelanggan', 'Simpan kontak pelanggan untuk transaksi dan penjualan kredit.'],
  suppliers: ['Pemasok', 'Kelola mitra pemasok untuk pembelian berikutnya.'],
  expenses: ['Biaya operasional', 'Catat biaya tunai pada shift aktif agar saldo laci kas tetap sesuai.'],
  settings: ['Pengaturan toko', 'Identitas bisnis, pajak, QRIS, dan personalisasi struk.'],
  users: ['Tim & hak akses', 'Aktifkan anggota tim dan tentukan tanggung jawab masing-masing.'],
};

export function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], cell = '', quoted = false;
  const source = text.replace(/^\uFEFF/, '');
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if (c === '"') {
      if (quoted && source[i + 1] === '"') { cell += '"'; i++; }
      else if (cell === '' || quoted) quoted = !quoted;
      else throw new Error('Tanda kutip CSV tidak valid.');
    } else if (c === ',' && !quoted) { row.push(cell); cell = ''; }
    else if ((c === '\n' || c === '\r') && !quoted) {
      if (c === '\r' && source[i + 1] === '\n') i++;
      row.push(cell); if (row.some(x => x.trim())) rows.push(row); row = []; cell = '';
    } else cell += c;
  }
  if (quoted) throw new Error('CSV memiliki tanda kutip yang belum ditutup.');
  row.push(cell); if (row.some(x => x.trim())) rows.push(row);
  return rows;
}

function downloadCSV(name: string, columns: string[], rows: Row[]) {
  const quote = (v: unknown) => {
    let s = str(v);
    if (/^[=+@\-\t\r]/.test(s)) s = `'${s}`;
    return `"${s.replaceAll('"', '""')}"`;
  };
  const blob = new Blob(['\uFEFF' + [columns, ...rows.map(r => columns.map(c => r[c]))].map(r => r.map(quote).join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob), a = document.createElement('a'); a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="field"><span>{label}</span>{children}</label>;
}

export default function Management({ tab, db, role, refresh }: Props) {
  const [rows, setRows] = useState<Row[]>([]);
  const [products, setProducts] = useState<Row[]>([]);
  const [suppliers, setSuppliers] = useState<Row[]>([]);
  const [movements, setMovements] = useState<Row[]>([]);
  const [form, setForm] = useState<Form>({});
  const [editing, setEditing] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [lines, setLines] = useState<{ product_id: string; qty: string; cost: string }[]>([{ product_id: '', qty: '1', cost: '0' }]);
  const [csvPreview, setCsvPreview] = useState<Row[] | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const admin = role === 'owner' || role === 'admin';
  const inventoryAllowed = admin || role === 'warehouse';
  const allowed = ['products', 'inventory', 'purchases', 'suppliers'].includes(tab) ? inventoryAllowed : tab === 'users' || tab === 'settings' ? role === 'owner' : tab === 'customers' ? admin || role === 'cashier' : admin;
  const title = titles[tab] ?? ['Data toko', ''];
  const set = (key: string, value: string) => setForm(f => ({ ...f, [key]: value }));

  const load = useCallback(async () => {
    if (!allowed) { setLoading(false); return; }
    setLoading(true);
    try {
      const table = tab === 'inventory' || tab === 'products' ? (admin ? 'products' : 'products_public') : tab === 'users' ? 'profiles' : tab;
      // Explicit pagination avoids Supabase's default 1,000-row truncation.
      const all: Row[] = [];
      for (let offset = 0; ; offset += 500) {
        const { data, error: e } = await db.from(table).select('*').order(tab === 'settings' ? 'id' : 'created_at', { ascending: false }).range(offset, offset + 499);
        if (e) throw e;
        all.push(...(data as Row[]));
        if (!data || data.length < 500) break;
      }
      setRows(all);
      if (tab === 'settings' && all[0]) setForm(Object.fromEntries(Object.entries(all[0]).map(([k, v]) => [k, str(v)])));
      if (tab === 'inventory') {
        const { data, error: e } = await db.from('stock_movements').select('*').order('created_at', { ascending: false }).limit(100);
        if (e) throw e; setMovements(data as Row[]);
      }
      if (tab === 'purchases') {
        const collect = async (tableName: string) => {
          const output: Row[] = [];
          for (let offset = 0; ; offset += 500) {
            const { data, error: e } = await db.from(tableName).select('*').order('name').range(offset, offset + 499);
            if (e) throw e; output.push(...data as Row[]); if (data.length < 500) return output;
          }
        };
        const [ps, ss] = await Promise.all([collect(admin ? 'products' : 'products_public'), collect('suppliers')]);
        setProducts(ps.filter(p => p.active)); setSuppliers(ss);
      }
    } catch (e) { setError(e instanceof Error ? e.message : str((e as { message?: string }).message || e)); }
    finally { setLoading(false); }
  }, [db, tab, admin, allowed]);

  useEffect(() => { setRows([]); setQuery(''); setPage(0); setShowForm(false); setEditing(null); setForm({}); setError(''); setNotice(''); setCsvPreview(null); void load(); }, [load]);
  async function act(fn: () => Promise<void>, message = 'Perubahan berhasil disimpan.') {
    if (busy) return;
    setBusy(true); setError(''); setNotice('');
    try { await fn(); setNotice(message); await load(); refresh(); }
    catch (e) { setError(e instanceof Error ? e.message : str((e as { message?: string }).message || e)); }
    finally { setBusy(false); }
  }
  const check = (e: { message: string } | null) => { if (e) throw new Error(e.message); };
  function edit(row?: Row) {
    setEditing(row ? str(row.id) : null);
    setForm(row ? Object.fromEntries(Object.entries(row).map(([k, v]) => [k, str(v)])) : { category: 'Umum', unit: 'pcs', price: '', cost: '', min_stock: '5', active: 'true' });
    setShowForm(true); setError(''); setNotice('');
  }
  const filtered = rows.filter(r => Object.values(r).some(v => str(v).toLowerCase().includes(query.toLowerCase())));
  const visible = filtered.slice(page * 20, page * 20 + 20);

  async function submit(e: FormEvent) {
    e.preventDefault();
    await act(async () => {
      if (tab === 'products') {
        const payload = { sku: form.sku.trim(), barcode: form.barcode?.trim() || null, name: form.name.trim(), category: form.category?.trim() || 'Umum', unit: form.unit?.trim() || 'pcs', price: Number(form.price), cost: Number(form.cost), min_stock: Number(form.min_stock), active: form.active !== 'false' };
        const result = editing ? await db.from('products').update(payload).eq('id', editing).select('id').single() : await db.from('products').insert(payload).select('id').single();
        check(result.error);
      } else if (tab === 'customers' || tab === 'suppliers') {
        const payload = { name: form.name.trim(), phone: form.phone?.trim() || '', address: form.address?.trim() || '' };
        const result = editing ? await db.from(tab).update(payload).eq('id', editing).select('id').single() : await db.from(tab).insert(payload).select('id').single();
        check(result.error);
      } else if (tab === 'inventory') {
        const { error } = await db.rpc('set_stock', { p_product_id: editing, p_stock: Number(form.stock), p_reason: form.reason.trim() }); check(error);
      } else if (tab === 'expenses') {
        const { error } = await db.rpc('add_cash_movement', { p_amount: Number(form.amount), p_kind: 'expense', p_note: form.note.trim() }); check(error);
      } else if (tab === 'users') {
        const { error } = await db.rpc('set_member_role', { p_user_id: editing, p_name: form.name.trim(), p_role: form.role, p_active: form.active === 'true' }); check(error);
      }
      setShowForm(false); setEditing(null);
    });
  }

  async function inspectCSV(file?: File) {
    setError(''); setCsvPreview(null);
    try {
      if (!file) return;
      if (file.size > 2 * 1024 * 1024) throw new Error('Maksimal ukuran CSV 2 MB.');
      const matrix = parseCSV(await file.text());
      if (matrix.length < 2) throw new Error('CSV harus memiliki header dan minimal satu produk.');
      const headers = matrix[0].map(x => x.trim().toLowerCase());
      for (const key of ['sku', 'name', 'price', 'cost']) if (!headers.includes(key)) throw new Error(`Kolom ${key} wajib ada.`);
      if (matrix.length > 501) throw new Error('Maksimal 500 produk per impor.');
      const seen = new Set<string>();
      const preview = matrix.slice(1).map((cells, i) => {
        if (cells.length !== headers.length) throw new Error(`Baris ${i + 2}: jumlah kolom tidak sesuai.`);
        const r = Object.fromEntries(headers.map((h, j) => [h, cells[j].trim()]));
        if (!r.sku || !r.name || seen.has(r.sku)) throw new Error(`Baris ${i + 2}: SKU/nama kosong atau SKU duplikat.`);
        seen.add(r.sku);
        for (const key of ['price', 'cost']) if (r[key] === '' || !Number.isFinite(Number(r[key])) || Number(r[key]) < 0) throw new Error(`Baris ${i + 2}: ${key} harus angka positif atau nol, tanpa Rp/titik ribuan.`);
        if (r.min_stock && (!Number.isFinite(Number(r.min_stock)) || Number(r.min_stock) < 0)) throw new Error(`Baris ${i + 2}: min_stock tidak valid.`);
        return { sku: r.sku, name: r.name, barcode: r.barcode || null, category: r.category || 'Umum', unit: r.unit || 'pcs', price: Number(r.price), cost: Number(r.cost), min_stock: Number(r.min_stock || 5), active: r.active !== 'false' };
      });
      setCsvPreview(preview);
    } catch (e) { setError(e instanceof Error ? e.message : str(e)); }
    if (fileInput.current) fileInput.current.value = '';
  }

  if (!allowed) return <section className="panel"><ShieldCheck size={32} /><h2>Akses dibatasi</h2><p className="muted">Menu ini tidak tersedia untuk peran Anda.</p></section>;
  return <section className="management">
    <div className="toolbar"><div><h1>{title[0]}</h1><p className="muted">{title[1]}</p></div><button className="btn" onClick={() => void load()} disabled={loading || busy} aria-label="Muat ulang"><RefreshCw size={17} /> Muat ulang</button></div>
    {error && <div role="alert" className="panel" style={{ borderColor: '#fca5a5', color: '#b91c1c', marginBottom: 16 }}>{error}</div>}
    {notice && <div role="status" className="panel" style={{ borderColor: '#86efac', color: '#15803d', marginBottom: 16 }}>{notice}</div>}

    {tab === 'settings' ? <form className="panel" onSubmit={e => { e.preventDefault(); void act(async () => {
      if (form.qris_url && !/^https:\/\//i.test(form.qris_url)) throw new Error('Alamat gambar QRIS harus diawali https://.');
      const { error } = await db.from('settings').update({ store_name: form.store_name.trim(), address: form.address || '', phone: form.phone || '', tax_rate: Number(form.tax_rate), qris_url: form.qris_url || '', receipt_footer: form.receipt_footer || '', receipt_width: Number(form.receipt_width || 80), max_cashier_discount: Number(form.max_cashier_discount || 10) }).eq('id', 1).select('id').single(); check(error);
    }); }}><div className="form-grid">
      <Field label="Nama toko"><input required value={form.store_name || ''} onChange={e => set('store_name', e.target.value)} /></Field>
      <Field label="Nomor telepon"><input value={form.phone || ''} onChange={e => set('phone', e.target.value)} /></Field>
      <Field label="Alamat"><textarea value={form.address || ''} onChange={e => set('address', e.target.value)} /></Field>
      <Field label="Pajak penjualan (%)"><input type="number" min="0" max="100" step="0.01" required value={form.tax_rate || '0'} onChange={e => set('tax_rate', e.target.value)} /></Field>
      <Field label="URL gambar QRIS (HTTPS)"><input type="url" placeholder="https://…/qris.png" value={form.qris_url || ''} onChange={e => set('qris_url', e.target.value)} /></Field>
      <Field label="Lebar struk"><select value={form.receipt_width || '80'} onChange={e => set('receipt_width', e.target.value)}><option value="58">58 mm</option><option value="80">80 mm</option></select></Field>
      <Field label="Pesan penutup struk"><textarea value={form.receipt_footer || ''} onChange={e => set('receipt_footer', e.target.value)} /></Field>
      <Field label="Batas diskon kasir (%)"><input type="number" min="0" max="100" step="0.01" value={form.max_cashier_discount || '10'} onChange={e => set('max_cashier_discount', e.target.value)} /></Field>
    </div><p className="muted">Gunakan gambar QRIS resmi usaha Anda. Pembayaran QRIS dan transfer diperiksa secara manual. Pajak dihitung setelah diskon.</p><button className="btn primary" disabled={busy || loading}><Save size={17} /> {busy ? 'Menyimpan…' : 'Simpan pengaturan'}</button></form> : <>

    <div className="toolbar" style={{ marginBottom: 18 }}><div style={{ display: 'flex', alignItems: 'center', gap: 8 }}><Search size={18} /><input aria-label="Cari data" placeholder="Cari nama, SKU, atau catatan…" value={query} onChange={e => { setQuery(e.target.value); setPage(0); }} /></div><div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
      <button className="btn" onClick={() => downloadCSV(`BM-POS-${tab}.csv`, tab === 'products' ? ['sku', 'barcode', 'name', 'category', 'unit', 'price', ...(admin ? ['cost'] : []), 'stock', 'min_stock', 'active'] : rows.length ? Object.keys(rows[0]) : ['id'], filtered)} disabled={!rows.length}><Download size={16} /> Ekspor CSV</button>
      {tab === 'products' && admin && <><button className="btn" onClick={() => downloadCSV('template-produk.csv', ['sku', 'barcode', 'name', 'category', 'unit', 'price', 'cost', 'min_stock', 'active'], [{ sku: 'BRG-001', barcode: '', name: 'Contoh Produk', category: 'Umum', unit: 'pcs', price: 15000, cost: 10000, min_stock: 5, active: true }])}>Template CSV</button><button className="btn" onClick={() => fileInput.current?.click()}><Upload size={16} /> Impor CSV</button><input ref={fileInput} type="file" accept=".csv,text/csv" hidden onChange={e => void inspectCSV(e.target.files?.[0])} /></>}
      {((tab === 'products' && admin) || tab === 'customers' || (tab === 'suppliers' && inventoryAllowed) || tab === 'expenses') && <button className="btn primary" onClick={() => edit()}><Plus size={17} /> {tab === 'expenses' ? 'Catat biaya' : 'Tambah data'}</button>}
    </div></div>

    {tab === 'users' && <div className="panel" style={{ marginBottom: 18 }}><ShieldCheck size={22} /><strong>Tambah pengguna melalui Supabase Auth</strong><p className="muted">Buka Authentication → Users → Add user pada dashboard Supabase. Setelah dibuat, pengguna tampil di sini dalam keadaan nonaktif. Tetapkan peran lalu aktifkan. Gunakan kata sandi unik dan kirimkan secara pribadi.</p></div>}

    {csvPreview && <div className="panel" style={{ marginBottom: 18 }}><h3>Pratinjau impor · {csvPreview.length} produk</h3><p className="muted">SKU yang sudah ada akan diperbarui. Stok tidak diubah; gunakan menu Persediaan. Seluruh baris divalidasi sebelum disimpan.</p><div className="table-wrap"><table><thead><tr><th>SKU</th><th>Produk</th><th>Harga jual</th><th>Modal</th></tr></thead><tbody>{csvPreview.slice(0, 10).map(r => <tr key={str(r.sku)}><td>{r.sku}</td><td>{r.name}</td><td>{money(r.price)}</td><td>{money(r.cost)}</td></tr>)}</tbody></table></div>{csvPreview.length > 10 && <p className="muted">Menampilkan 10 baris pertama.</p>}<div className="toolbar"><button className="btn" disabled={busy} onClick={() => setCsvPreview(null)}>Batal</button><button className="btn primary" disabled={busy} onClick={() => void act(async () => { const { error } = await db.from('products').upsert(csvPreview, { onConflict: 'sku' }); check(error); setCsvPreview(null); }, 'Impor produk berhasil.')}>{busy ? 'Mengimpor…' : 'Konfirmasi impor'}</button></div></div>}

    {showForm && <form className="panel" style={{ marginBottom: 18 }} onSubmit={submit}><div className="toolbar"><h3>{editing ? 'Ubah data' : 'Tambah data'}</h3><button type="button" className="btn" aria-label="Tutup formulir" onClick={() => setShowForm(false)}><X size={18} /></button></div><div className="form-grid">
      {tab === 'products' && <>
        <Field label="Nama produk"><input required maxLength={150} value={form.name || ''} onChange={e => set('name', e.target.value)} /></Field>
        <Field label="SKU"><input required value={form.sku || ''} onChange={e => set('sku', e.target.value)} /></Field>
        <Field label="Barcode (opsional)"><input value={form.barcode || ''} onChange={e => set('barcode', e.target.value)} /></Field>
        <Field label="Kategori"><input required value={form.category || ''} onChange={e => set('category', e.target.value)} /></Field>
        <Field label="Satuan"><input required value={form.unit || ''} onChange={e => set('unit', e.target.value)} /></Field>
        {['price', 'cost', 'min_stock'].map((key, i) => <Field key={key} label={['Harga jual (Rp)', 'Biaya modal per unit (Rp)', 'Stok minimum'][i]}><input type="number" min="0" step={key === 'min_stock' ? '0.001' : '0.01'} required value={form[key] || ''} onChange={e => set(key, e.target.value)} /></Field>)}
        <Field label="Status"><select value={form.active || 'true'} onChange={e => set('active', e.target.value)}><option value="true">Aktif</option><option value="false">Diarsipkan</option></select></Field>
      </>}
      {(tab === 'customers' || tab === 'suppliers') && <><Field label="Nama"><input required value={form.name || ''} onChange={e => set('name', e.target.value)} /></Field><Field label="Telepon"><input value={form.phone || ''} onChange={e => set('phone', e.target.value)} /></Field><Field label="Alamat"><textarea value={form.address || ''} onChange={e => set('address', e.target.value)} /></Field></>}
      {tab === 'inventory' && <><Field label="Produk"><input value={form.name || ''} disabled /></Field><Field label="Stok fisik terbaru"><input type="number" min="0" step="0.001" required value={form.stock || '0'} onChange={e => set('stock', e.target.value)} /></Field><Field label="Alasan penyesuaian"><textarea required minLength={3} placeholder="Contoh: hasil stok opname 12 November" value={form.reason || ''} onChange={e => set('reason', e.target.value)} /></Field></>}
      {tab === 'expenses' && <><Field label="Jumlah biaya tunai (Rp)"><input type="number" min="1" step="1" required value={form.amount || ''} onChange={e => set('amount', e.target.value)} /></Field><Field label="Keterangan"><textarea required minLength={3} placeholder="Contoh: pembelian kantong belanja" value={form.note || ''} onChange={e => set('note', e.target.value)} /></Field></>}
      {tab === 'users' && <><Field label="Nama anggota"><input required value={form.name || ''} onChange={e => set('name', e.target.value)} /></Field><Field label="Peran"><select value={form.role || 'cashier'} onChange={e => set('role', e.target.value)}><option value="owner">Owner</option><option value="admin">Admin</option><option value="cashier">Kasir</option><option value="warehouse">Admin Gudang</option></select></Field><Field label="Akses"><select value={form.active || 'false'} onChange={e => set('active', e.target.value)}><option value="true">Aktif</option><option value="false">Nonaktif</option></select></Field></>}
    </div>{tab === 'products' && <p className="muted">Produk baru dimulai dari stok 0. Tambahkan stok melalui pembelian atau penyesuaian persediaan.</p>}<button className="btn primary" disabled={busy}><Save size={17} /> {busy ? 'Menyimpan…' : 'Simpan'}</button></form>}

    {tab === 'purchases' && <form className="panel" style={{ marginBottom: 20 }} onSubmit={e => { e.preventDefault(); void act(async () => {
      if (new Set(lines.map(l => l.product_id)).size !== lines.length) throw new Error('Produk yang sama tidak boleh diulang. Gabungkan jumlahnya.');
      const { error } = await db.rpc('receive_purchase', { p_supplier_id: form.supplier_id || null, p_items: lines.map(l => ({ product_id: l.product_id, qty: Number(l.qty), cost: Number(l.cost) })), p_note: form.note || '' }); check(error); setLines([{ product_id: '', qty: '1', cost: '0' }]); setForm({});
    }, 'Penerimaan berhasil. Stok dan biaya modal sudah diperbarui.'); }}><h3><Truck size={19} /> Terima barang</h3><div className="form-grid"><Field label="Pemasok"><select value={form.supplier_id || ''} onChange={e => set('supplier_id', e.target.value)}><option value="">Tanpa pemasok</option>{suppliers.map(s => <option key={str(s.id)} value={str(s.id)}>{s.name}</option>)}</select></Field><Field label="Catatan / nomor faktur"><input value={form.note || ''} onChange={e => set('note', e.target.value)} /></Field></div>
      {lines.map((line, i) => <div key={i} className="form-grid" style={{ borderTop: '1px solid var(--border, #e2e8f0)', paddingTop: 12, marginTop: 12 }}><Field label={`Produk ${i + 1}`}><select required value={line.product_id} onChange={e => { const id = e.target.value; setLines(ls => ls.map((l, index) => index === i ? { ...l, product_id: id, cost: str(products.find(p => p.id === id)?.cost || 0) } : l)); }}><option value="">Pilih produk</option>{products.map(p => <option key={str(p.id)} value={str(p.id)}>{p.sku} · {p.name}</option>)}</select></Field><Field label="Jumlah diterima"><input type="number" required min="0.001" step="0.001" value={line.qty} onChange={e => setLines(ls => ls.map((l, index) => index === i ? { ...l, qty: e.target.value } : l))} /></Field><Field label="Biaya per unit (Rp)"><input type="number" required min="0" step="0.01" value={line.cost} onChange={e => setLines(ls => ls.map((l, index) => index === i ? { ...l, cost: e.target.value } : l))} /></Field>{lines.length > 1 && <button className="btn danger" type="button" onClick={() => setLines(ls => ls.filter((_, index) => index !== i))}>Hapus baris</button>}</div>)}
      <div className="toolbar" style={{ marginTop: 18 }}><button type="button" className="btn" onClick={() => setLines(ls => [...ls, { product_id: '', qty: '1', cost: '0' }])}><Plus size={17} /> Tambah item</button><strong>Total {money(lines.reduce((s, l) => s + Number(l.qty) * Number(l.cost), 0))}</strong><button className="btn primary" disabled={busy || !products.length}>{busy ? 'Memproses…' : 'Konfirmasi penerimaan'}</button></div><p className="muted">Penerimaan ini mencatat stok dan nilai pembelian. Pembayaran ke pemasok dan utang pemasok belum dikelola pada versi ini.</p></form>}

    <div className="panel" style={{ padding: 0 }}><div className="table-wrap"><table><thead><tr>
      {(tab === 'products' || tab === 'inventory') && <><th>Produk</th><th>SKU / kategori</th><th>Stok</th><th>{tab === 'products' ? 'Harga jual' : 'Minimum'}</th>{tab === 'products' && admin && <th>Modal/unit</th>}<th>Status</th><th>Aksi</th></>}
      {(tab === 'customers' || tab === 'suppliers') && <><th>Nama</th><th>Telepon</th><th>Alamat</th><th>Aksi</th></>}
      {tab === 'purchases' && <><th>Tanggal</th><th>Pemasok</th><th>Catatan</th><th>Total</th></>}
      {tab === 'expenses' && <><th>Tanggal</th><th>Catatan</th><th>Jumlah</th></>}
      {tab === 'users' && <><th>Nama</th><th>Peran</th><th>Status</th><th>Aksi</th></>}
    </tr></thead><tbody>{loading ? <tr><td colSpan={7} style={{ padding: 32 }}>Memuat data…</td></tr> : !visible.length ? <tr><td colSpan={7} style={{ padding: 32, textAlign: 'center' }}><Package size={28} /><p>Belum ada data yang sesuai.</p></td></tr> : visible.map(r => <tr key={str(r.id)}>
      {(tab === 'products' || tab === 'inventory') && <><td><strong>{r.name}</strong><div className="muted">{r.barcode || 'Tanpa barcode'}</div></td><td>{r.sku}<div className="muted">{r.category}</div></td><td><strong style={{ color: Number(r.stock) <= Number(r.min_stock) ? '#d97706' : undefined }}>{r.stock}</strong> <span className="muted">{r.unit}</span></td><td>{tab === 'products' ? money(r.price) : r.min_stock}</td>{tab === 'products' && admin && <td>{money(r.cost)}</td>}<td><span className="badge">{!r.active ? 'Arsip' : Number(r.stock) === 0 ? 'Habis' : Number(r.stock) <= Number(r.min_stock) ? 'Menipis' : 'Tersedia'}</span></td><td><div style={{ display: 'flex', gap: 6 }}>{(admin || tab === 'inventory') && <button className="btn" aria-label={`Ubah ${r.name}`} onClick={() => edit(r)}><Pencil size={15} />{tab === 'inventory' ? 'Sesuaikan' : ''}</button>}{tab === 'products' && admin && r.active && <button className="btn" aria-label={`Arsipkan ${r.name}`} disabled={busy} onClick={() => { if (window.confirm(`Arsipkan ${r.name}? Riwayat transaksi tetap tersimpan.`)) void act(async () => { const { error } = await db.from('products').update({ active: false }).eq('id', r.id).select('id').single(); check(error); }); }}><Archive size={15} /></button>}</div></td></>}
      {(tab === 'customers' || tab === 'suppliers') && <><td><strong>{r.name}</strong></td><td>{r.phone || '—'}</td><td>{r.address || '—'}</td><td>{(admin || tab === 'suppliers') && <button className="btn" onClick={() => edit(r)} aria-label={`Ubah ${r.name}`}><Pencil size={15} /> Ubah</button>}</td></>}
      {tab === 'purchases' && <><td>{when(r.created_at)}</td><td>{suppliers.find(s => s.id === r.supplier_id)?.name || 'Tanpa pemasok'}</td><td>{r.note || '—'}</td><td><strong>{money(r.total)}</strong></td></>}
      {tab === 'expenses' && <><td>{when(r.created_at)}</td><td>{r.note}</td><td><strong>{money(r.amount)}</strong></td></>}
      {tab === 'users' && <><td><strong>{r.name || 'Anggota baru'}</strong><div className="muted" style={{ fontSize: 10 }}>{r.id}</div></td><td>{({ owner: 'Owner', admin: 'Admin', cashier: 'Kasir', warehouse: 'Admin Gudang' } as Record<string, string>)[str(r.role)]}</td><td><span className="badge">{r.active ? 'Aktif' : 'Nonaktif'}</span></td><td><button className="btn" onClick={() => edit(r)}><Pencil size={15} /> Ubah akses</button></td></>}
    </tr>)}</tbody></table></div><div className="toolbar" style={{ padding: 16 }}><span className="muted">{filtered.length} data · halaman {page + 1} dari {Math.max(1, Math.ceil(filtered.length / 20))}</span><div style={{ display: 'flex', gap: 8 }}><button className="btn" disabled={page === 0} onClick={() => setPage(p => p - 1)}>Sebelumnya</button><button className="btn" disabled={(page + 1) * 20 >= filtered.length} onClick={() => setPage(p => p + 1)}>Berikutnya</button></div></div></div>

    {tab === 'inventory' && <div className="panel" style={{ marginTop: 20 }}><h3>Mutasi stok terbaru</h3><p className="muted">100 mutasi terakhir. Seluruh mutasi tetap tersimpan dalam database.</p><div className="table-wrap"><table><thead><tr><th>Waktu</th><th>Produk</th><th>Perubahan</th><th>Jenis / alasan</th></tr></thead><tbody>{movements.length ? movements.map(m => <tr key={str(m.id)}><td>{when(m.created_at)}</td><td>{rows.find(p => p.id === m.product_id)?.name || m.product_id}</td><td>{Number(m.qty ?? m.quantity ?? m.delta) > 0 ? '+' : ''}{m.qty ?? m.quantity ?? m.delta}</td><td>{m.kind ?? m.type}<div className="muted">{m.reason ?? m.note}</div></td></tr>) : <tr><td colSpan={4}>Belum ada mutasi stok.</td></tr>}</tbody></table></div></div>}
    </>}
  </section>;
}
