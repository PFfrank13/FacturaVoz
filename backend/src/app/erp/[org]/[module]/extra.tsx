import type React from "react";
import type { workspaceContext } from "@/lib/erp/context";
import { money } from "@/lib/schemas";
import { limaDate } from "@/lib/erp/receipts";
import { byCategory, expenseCategories, type ExpenseRow } from "@/lib/erp/expenses";
import type { PosProduct, PosPromo } from "@/lib/erp/pos";
import { hasFeature } from "@/lib/erp/access";
import PosBoard, { type PayInfo } from "@/components/erp/PosBoard";
import { FiadosBoard, NoticesBoard, type Debtor, type NoticeRow } from "@/components/erp/LedgerBoards";
import { loadReceivables } from "./extra3";
import { waPhone } from "@/lib/erp/clients";
import LiveRefresh from "@/components/erp/LiveRefresh";
import { ExpenseForm, MarkAlertsRead, RestoreButton, VerifyAudit } from "@/components/erp/OwnerBoards";

type Ctx = Awaited<ReturnType<typeof workspaceContext>>;
const liveSales = ["products"] as const;
const liveFiados = ["credit_ledger", "clients"] as const;
const liveNotices = ["payment_notices"] as const;
const liveAlerts = ["owner_alerts"] as const;
const liveExpenses = ["expenses"] as const;

const dateTime = (iso: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" }).format(new Date(iso));
const dateOnly = (d: string) => new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(`${d}T12:00:00Z`));
const failed = (what: string) => <div className="fv-empty" role="alert"><h2>No pudimos cargar {what}</h2><p>Pulsa Actualizar para reintentar. No se han modificado tus datos.</p></div>;
const heading = (eyebrow: string, title: string, text: string, org: string, live?: readonly string[]) =>
  <section className="fv-heading"><div className="fv-heading-row"><p className="fv-eyebrow">{eyebrow}</p>{live && <LiveRefresh org={org} tables={live} />}</div><h1>{title}</h1><p>{text}</p></section>;

/** Web modules added in v3.8 (same data and rules as the mobile app). Returns null for any other module. */
export async function renderExtra(id: string, c: Ctx, org: string, title: string) {
  const cur = c.organization.currency || "PEN";
  const fmt = (v: number) => money(v, cur);
  const name = c.organization.name;

  if (id === "vender") {
    const pricing = hasFeature(c.license, "precios");
    const [prods, codes, fiscal, promoRes, paySet] = await Promise.all([
      c.db.from("products").select("id,name,unit_price,unit,stock,barcode,icbper,category,image_path,wholesale_price,wholesale_min_qty").eq("org_id", org).eq("active", true).neq("unit", "ZZ").order("name").limit(5000),
      c.db.from("product_barcodes").select("code,product_id").eq("org_id", org).limit(20000),
      c.db.from("fiscal_companies").select("org_id").eq("org_id", org).maybeSingle(),
      pricing ? c.db.from("promotions").select("id,name,kind,value,product_ids,min_qty,starts_on,ends_on,active").eq("org_id", org).eq("active", true).limit(300) : Promise.resolve({ data: [] }),
      c.db.from("org_pay_settings").select("yape_phone,plin_phone,yape_qr_path,plin_qr_path,bank_name,bank_account,bank_cci,account_holder").eq("org_id", org).maybeSingle(),
    ]);
    const ps = (paySet.data ?? null) as Record<string, string | null> | null;
    const qrPaths = [ps?.yape_qr_path, ps?.plin_qr_path].filter((x): x is string => !!x);
    const qrSigned = qrPaths.length ? await c.db.storage.from("org-media").createSignedUrls(qrPaths, 3600) : { data: [] };
    const qrUrl = (path: string | null | undefined) => (path ? (qrSigned.data ?? []).find(x => x.path === path)?.signedUrl ?? null : null);
    const pay: PayInfo | null = ps ? { yape: ps.yape_phone ?? "", plin: ps.plin_phone ?? "", yape_qr: qrUrl(ps.yape_qr_path), plin_qr: qrUrl(ps.plin_qr_path), bank_name: ps.bank_name ?? "",
      bank_account: ps.bank_account ?? "", bank_cci: ps.bank_cci ?? "", holder: ps.account_holder ?? "" } : null;
    if (prods.error) return <>{heading(`VENDER / ${name}`, title, "", org)}{failed("los productos")}</>;
    type Raw = Omit<PosProduct, "image_url" | "unit_price" | "stock" | "wholesale_price" | "wholesale_min_qty"> & { unit_price: number | string; stock: number | string | null; image_path: string | null; wholesale_price: number | string | null; wholesale_min_qty: number | string | null };
    const rows = (prods.data ?? []) as Raw[];
    const paths = rows.map(r => r.image_path).filter((p): p is string => !!p).slice(0, 400);
    const signed = paths.length ? await c.db.storage.from("org-media").createSignedUrls(paths, 3600) : { data: [] };
    const urls = new Map((signed.data ?? []).map(s => [s.path, s.signedUrl] as const));
    const products: PosProduct[] = rows.map(r => ({ id: r.id, name: r.name, unit_price: Number(r.unit_price), unit: r.unit, stock: r.stock == null ? null : Number(r.stock),
      barcode: r.barcode, icbper: !!r.icbper, category: r.category, image_url: r.image_path ? urls.get(r.image_path) ?? null : null,
      wholesale_price: r.wholesale_price == null ? null : Number(r.wholesale_price), wholesale_min_qty: r.wholesale_min_qty == null ? null : Number(r.wholesale_min_qty) }));
    type RawPromo = Omit<PosPromo, "value" | "min_qty" | "product_ids"> & { value: number | string; min_qty: number | string | null; product_ids: string[] | null };
    const promos: PosPromo[] = ((promoRes.data ?? []) as RawPromo[]).map(p => ({ ...p, value: Number(p.value), min_qty: p.min_qty == null ? null : Number(p.min_qty), product_ids: (p.product_ids ?? []).map(String) }));
    const extraCodes = Object.fromEntries(((codes.data ?? []) as { code: string; product_id: string }[]).map(x => [x.code, x.product_id]));
    return <>{heading(`VENDER / ${name}`, title, "Conecta tu lector de códigos USB y escanea: cada producto entra al carrito con su nombre y precio. También funciona con las etiquetas de la balanza.", org, liveSales)}
      <PosBoard org={org} products={products} extraCodes={extraCodes} currency={cur} taxRate={Number(c.organization.default_tax_rate ?? 18)} canEmit={!!fiscal.data} promos={promos} pricing={pricing} today={limaDate(new Date())} pay={pay} />
    </>;
  }

  if (id === "fiados") {
    const [res, moves, cls] = await Promise.all([
      c.db.rpc("credit_balances", { p_org: org }),
      c.db.from("credit_ledger").select("id,client_id,kind,amount,description,created_at,method").eq("org_id", org).order("created_at", { ascending: false }).limit(3000),
      c.db.from("clients").select("id,name").eq("org_id", org).order("name").limit(3000),
    ]);
    type Bal = { client_id: string; client_name: string; phone: string | null; balance: number | string; last_move: string | null; oldest_due: string | null; credit_limit: number | string | null };
    const rows = ((res.data ?? []) as Bal[]).map(r => ({ ...r, balance: Number(r.balance), credit_limit: r.credit_limit == null ? null : Number(r.credit_limit) })).filter(r => r.balance > 0.004).sort((a, b) => b.balance - a.balance);
    const today = limaDate(new Date());
    const total = rows.reduce((s, r) => s + r.balance, 0);
    const late = rows.filter(r => r.oldest_due && r.oldest_due < today).length;
    const over = rows.filter(r => r.credit_limit != null && r.credit_limit > 0 && r.balance > r.credit_limit).length;
    type Mv = { id: string; client_id: string; kind: string; amount: number | string; description: string | null; created_at: string; method: string | null };
    const byClient = new Map<string, Debtor["moves"]>();
    for (const m of (moves.data ?? []) as Mv[]) byClient.set(m.client_id, [...(byClient.get(m.client_id) ?? []), { ...m, amount: Number(m.amount) }]);
    const debtors: Debtor[] = rows.map(r => ({ client_id: r.client_id, name: r.client_name, phone: waPhone(r.phone), balance: r.balance, limit: r.credit_limit, oldest_due: r.oldest_due, moves: (byClient.get(r.client_id) ?? []).slice(0, 60) }));
    return <>{heading(`LIBRETA / ${name}`, title, "Anota lo que fías y los abonos. Ve la cuenta de cada cliente y mándasela por WhatsApp. Es la misma libreta del móvil.", org, liveFiados)}
      {res.error ? failed("la libreta") : <>
        <div className="fv-kpis">
          <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Te deben</span><strong>{fmt(total)}</strong><small>{rows.length} {rows.length === 1 ? "cliente" : "clientes"}</small></div>
          <div style={{ "--tone": "#ff8aa8" } as React.CSSProperties}><span>Vencidos</span><strong>{late}</strong><small>con fecha de pago pasada</small></div>
          <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Pasaron su límite</span><strong>{over}</strong><small>según el crédito de cada uno</small></div>
        </div>
        <FiadosBoard org={org} debtors={debtors} clients={(cls.data ?? []) as { id: string; name: string }[]} currency={cur} business={name} today={today} />
      </>}
    </>;
  }

  if (id === "avisos") {
    const [res, rec] = await Promise.all([
      c.db.from("payment_notices").select("id,app,amount,payer,operation_code,received_at,status,invoice:invoices(number)").eq("org_id", org).order("received_at", { ascending: false }).limit(500),
      loadReceivables(c, org),
    ]);
    type Raw = { id: string; app: string; amount: number | string; payer: string | null; operation_code: string | null; received_at: string; status: string; invoice: unknown };
    const rows: NoticeRow[] = ((res.data ?? []) as Raw[]).map(r => { const inv = (Array.isArray(r.invoice) ? r.invoice[0] : r.invoice) as { number: string } | null; return { ...r, amount: Number(r.amount), invoice: inv?.number ?? null }; });
    const today = limaDate(new Date());
    const todays = rows.filter(r => limaDate(new Date(r.received_at)) === today && r.status !== "descartado");
    const pending = rows.filter(r => r.status === "nuevo").length;
    return <>{heading(`COBROS / ${name}`, title, "Comprueba que el dinero llegó antes de entregar: pega el aviso de Yape, Plin o tu banco y regístralo. Aquí está el historial completo.", org, liveNotices)}
      {res.error ? failed("los avisos") : <>
        <div className="fv-kpis">
          <div style={{ "--tone": "#a98bff" } as React.CSSProperties}><span>Recibido hoy</span><strong>{fmt(todays.reduce((s, r) => s + r.amount, 0))}</strong><small>{todays.length} avisos</small></div>
          <div style={{ "--tone": "#ffb35c" } as React.CSSProperties}><span>Sin asociar</span><strong>{pending}</strong><small>asígnalos a un comprobante o descártalos</small></div>
          <div style={{ "--tone": "#3ee6b0" } as React.CSSProperties}><span>Este mes</span><strong>{fmt(rows.filter(r => r.received_at.slice(0, 7) === today.slice(0, 7) && r.status !== "descartado").reduce((s, r) => s + r.amount, 0))}</strong><small>por Yape, Plin y banco</small></div>
        </div>
        <NoticesBoard org={org} rows={rows} currency={cur} open={rec.rows.filter(r => r.currency === cur).map(r => ({ id: r.id, number: r.number, client: r.client, balance: r.balance }))} />
      </>}
    </>;
  }

  if (id === "gastos") {
    const today = limaDate(new Date());
    const monthStart = `${today.slice(0, 7)}-01`;
    const res = await c.db.from("expenses").select("id,spent_on,category,description,supplier_name,doc_number,total,source").eq("org_id", org).gte("spent_on", monthStart).order("spent_on", { ascending: false }).limit(500);
    const rows = (res.data ?? []) as ExpenseRow[];
    const total = rows.reduce((s, r) => s + Number(r.total), 0);
    const cats = byCategory(rows);
    return <>{heading(`DINERO / ${name}`, title, "Lo que gasta tu negocio este mes: mercadería, luz, alquiler, sueldos… Las compras recibidas se suman solas.", org, liveExpenses)}
      <ExpenseForm org={org} today={today} />
      {res.error ? failed("los gastos") : <>
        <div className="fv-kpis">
          <div style={{ "--tone": "#ff8aa8" } as React.CSSProperties}><span>Gastado este mes</span><strong>{fmt(total)}</strong><small>{rows.length} gastos</small></div>
          {cats.slice(0, 2).map((x, i) => <div key={x.category} style={{ "--tone": i ? "#6fb7ff" : "#ffb35c" } as React.CSSProperties}><span>{x.label}</span><strong>{fmt(x.total)}</strong><small>{total ? Math.round(x.total / total * 100) : 0}% del mes</small></div>)}
        </div>
        {!rows.length ? <div className="fv-empty"><h2>Sin gastos este mes</h2><p>Registra aquí tus gastos o escanéalos con el móvil.</p></div>
          : <div className="fv-table-scroll fv-data"><table><thead><tr><th>Fecha</th><th>Categoría</th><th>Detalle</th><th>Proveedor</th><th>Importe</th></tr></thead><tbody>
            {rows.map(r => <tr key={r.id}><td>{dateOnly(r.spent_on)}</td><td>{expenseCategories[r.category] ?? r.category}</td><td>{r.description ?? "—"}{r.doc_number ? <small className="fv-muted"> · {r.doc_number}</small> : null}</td><td>{r.supplier_name ?? "—"}</td><td><b>{fmt(Number(r.total))}</b></td></tr>)}
          </tbody></table></div>}
      </>}
    </>;
  }

  if (id === "alertas") {
    const res = await c.db.from("owner_alerts").select("id,kind,severity,title,body,created_at,read_at").eq("org_id", org).order("created_at", { ascending: false }).limit(200);
    type Alert = { id: string; kind: string; severity: string; title: string; body: string | null; created_at: string; read_at: string | null };
    const rows = (res.data ?? []) as Alert[];
    const unread = rows.filter(r => !r.read_at).length;
    return <>{heading(`CONTROL / ${name}`, title, "Anulaciones, descuentos grandes, caja que no cuadra, cobros borrados y nuevos integrantes: te enteras al momento, estés donde estés.", org, liveAlerts)}
      <MarkAlertsRead org={org} unread={unread} />
      {res.error ? failed("las alertas") : !rows.length ? <div className="fv-empty"><h2>Todo en orden</h2><p>Cuando pase algo que debas saber, aparecerá aquí y en tu celular.</p></div>
        : <ul className="fv-alerts">{rows.map(r => <li key={r.id} className={`is-${r.severity}${r.read_at ? "" : " is-new"}`}>
          <i aria-hidden="true" /><div><strong>{r.title}</strong>{r.body && <p>{r.body}</p>}<small>{dateTime(r.created_at)}{r.read_at ? "" : " · nueva"}</small></div>
        </li>)}</ul>}
    </>;
  }

  if (id === "bitacora") {
    const [res, members] = await Promise.all([
      c.db.from("audit_log").select("id,action,entity,data,created_at,user_id").eq("org_id", org).order("id", { ascending: false }).limit(300),
      c.db.from("organization_members").select("user_id,display_name").eq("org_id", org),
    ]);
    type Entry = { id: number; action: string; entity: string | null; data: Record<string, unknown> | null; created_at: string; user_id: string | null };
    const names = new Map(((members.data ?? []) as { user_id: string; display_name: string | null }[]).map(m => [m.user_id, m.display_name] as const));
    const rows = (res.data ?? []) as Entry[];
    const label = (a: string) => ({ "pin.cambiado": "Cambió el PIN del dueño", "pin.desactivado": "Quitó el PIN del dueño", "pin.fallido": "PIN del dueño incorrecto" } as Record<string, string>)[a] ?? a.replace(/[._]/g, " ");
    return <>{heading(`CONTROL / ${name}`, title, "Quién hizo qué y cuándo. Cada registro está encadenado al anterior: si alguien lo altera, se nota.", org)}
      <VerifyAudit org={org} />
      {res.error ? failed("la bitácora") : !rows.length ? <div className="fv-empty"><h2>Sin registros aún</h2><p>Anulaciones, cambios de precio, de PIN y de equipo quedarán anotados aquí.</p></div>
        : <div className="fv-table-scroll fv-data"><table><thead><tr><th>Cuándo</th><th>Quién</th><th>Qué hizo</th><th>Detalle</th></tr></thead><tbody>
          {rows.map(r => <tr key={r.id}><td>{dateTime(r.created_at)}</td><td>{(r.user_id && names.get(r.user_id)) || "Sistema"}</td><td>{label(r.action)}</td>
            <td><small className="fv-muted">{[r.data?.["numero"], r.data?.["monto"] != null ? `S/ ${r.data["monto"]}` : null, r.data?.["nombre"]].filter(Boolean).join(" · ") || r.entity || ""}</small></td></tr>)}
        </tbody></table></div>}
    </>;
  }

  if (id === "papelera") {
    const res = await c.db.from("trash").select("id,table_name,label,deleted_at").eq("org_id", org).is("restored_at", null).order("deleted_at", { ascending: false }).limit(300);
    type Item = { id: string; table_name: string; label: string | null; deleted_at: string };
    const rows = (res.data ?? []) as Item[];
    const kind = (t: string) => ({ products: "Producto", clients: "Cliente", payments: "Cobro", expenses: "Gasto", invoices: "Comprobante", jobs: "Trabajo", credit_ledger: "Fiado" } as Record<string, string>)[t] ?? t;
    return <>{heading(`CONTROL / ${name}`, title, "Lo borrado en los últimos 30 días. Recupéralo con un clic: vuelve igual que estaba.", org)}
      {res.error ? failed("la papelera") : !rows.length ? <div className="fv-empty"><h2>La papelera está vacía</h2><p>Lo que se borre en el móvil o aquí se guarda 30 días por si te arrepientes.</p></div>
        : <div className="fv-table-scroll fv-data"><table><thead><tr><th>Borrado</th><th>Tipo</th><th>Qué era</th><th /></tr></thead><tbody>
          {rows.map(r => <tr key={r.id}><td>{dateTime(r.deleted_at)}</td><td>{kind(r.table_name)}</td><td>{r.label ?? "—"}</td><td><RestoreButton org={org} id={r.id} /></td></tr>)}
        </tbody></table></div>}
    </>;
  }

  return null;
}

