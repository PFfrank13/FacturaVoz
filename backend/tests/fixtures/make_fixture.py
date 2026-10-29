"""Genera un libro SINTÉTICO con la misma estructura que facturas_clientes_migracion_1500.xlsx
(hojas LEEME, Clientes, Facturas, Detalle_Facturas, Catalogo). Datos inventados SOLO para pruebas.
Uso: python3 make_fixture.py  -> crea migracion_1500_sintetico.xlsx y migracion_1500_esperado.json
"""
import json, random, datetime, os
from openpyxl import Workbook

R = random.Random(20261029)
HERE = os.path.dirname(os.path.abspath(__file__))

def ruc_dv(base10):
    w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
    s = sum(int(d) * w[i] for i, d in enumerate(base10))
    r = 11 - (s % 11)
    return str({10: 0, 11: 1}.get(r, r))

def make_ruc(prefix):
    b = prefix + "".join(str(R.randint(0, 9)) for _ in range(8))
    return b + ruc_dv(b)

NOMBRES = ["Ana", "Luis", "María", "José", "Rosa", "Carlos", "Lucía", "Jorge", "Elena", "Pedro", "Sofía", "Miguel", "Carmen", "Raúl", "Julia"]
APELL = ["Quispe", "Flores", "Huamán", "Rojas", "Mendoza", "Torres", "Vargas", "Castillo", "Ramos", "Chávez", "Díaz", "Gutiérrez", "Paredes", "Salazar"]
EMP = ["Comercial", "Inversiones", "Distribuidora", "Servicios Generales", "Constructora", "Ferretería", "Agroindustrias", "Textil", "Grupo", "Corporación"]
EMP2 = ["Los Andes", "Del Sur", "Pacífico", "San Martín", "El Sol", "Nueva Era", "Santa Rosa", "Inca", "Amazonas", "Lima Norte", "Miraflores", "Callao"]
DIST = ["Lima", "Miraflores", "San Juan de Lurigancho", "Ate", "Comas", "Surco", "Los Olivos", "Callao", "Arequipa", "Trujillo"]

clients = []
for i in range(1, 251):
    cid = f"CLI-{i:04d}"
    if i % 3 == 0:
        name = f"{R.choice(EMP)} {R.choice(EMP2)} S.A.C."
        tdoc, doc = "RUC", make_ruc(R.choice(["20", "20", "10"]))
    else:
        name = f"{R.choice(NOMBRES)} {R.choice(APELL)} {R.choice(APELL)}"
        tdoc, doc = "DNI", "".join(str(R.randint(0, 9)) for _ in range(8))
    if i in (7, 77, 177):
        tdoc, doc = "DNI", "TESTDNI0000"  # documento inválido a propósito
    clients.append(dict(id=cid, tdoc=tdoc, doc=doc, name=name, addr=f"Av. {R.choice(APELL)} {R.randint(100, 2999)}",
                        dist=R.choice(DIST), phone=f"9{R.randint(10000000, 99999999)}", mail=f"cliente{i}@ejemplo.pe"))

catalog = []
ITEMS = [("Instalación de internet", "Servicios", "ZZ", 120.0), ("Plan mensual 50 Mbps", "Servicios", "ZZ", 79.9),
         ("Plan mensual 100 Mbps", "Servicios", "ZZ", 99.9), ("Router WiFi doble banda", "Equipos", "NIU", 159.0),
         ("Cable UTP Cat6 (metro)", "Materiales", "NIU", 2.5), ("Conector RJ45", "Materiales", "NIU", 1.2),
         ("Visita técnica", "Servicios", "ZZ", 50.0), ("Antena exterior", "Equipos", "NIU", 245.0),
         ("Switch 8 puertos", "Equipos", "NIU", 135.5), ("Reconexión de servicio", "Servicios", "ZZ", 30.0),
         ("Cámara IP", "Equipos", "NIU", 189.9), ("Mantenimiento preventivo", "Servicios", "ZZ", 90.0),
         ("Canaleta 2 m", "Materiales", "NIU", 8.0), ("Soporte remoto (hora)", "Servicios", "ZZ", 40.0)]
for k, (d, cat, u, p) in enumerate(ITEMS, 1):
    catalog.append(dict(code=f"ITM-{k:03d}", desc=d, cat=cat, unit=u, price=p))

# 1500 comprobantes: 1168 facturas, 274 boletas, 58 notas de crédito
kinds = ["Factura"] * 1168 + ["Boleta"] * 274 + ["Nota de crédito"] * 58
R.shuffle(kinds)
# 3738 líneas repartidas (mínimo 1 por comprobante)
nlines = [1] * 1500
extra = 3738 - 1500
while extra > 0:
    j = R.randrange(1500)
    if nlines[j] < 6:
        nlines[j] += 1; extra -= 1

start = datetime.date(2025, 1, 2)
seq = {"F001": 0, "B001": 0, "FC01": 0, "BC01": 0}
docs, lines = [], []
emitted = []  # (tipo, serie-num) facturas/boletas para referenciar en NC
lid = 0
for n in range(1500):
    kind = kinds[n]
    c = R.choice(clients)
    if kind == "Factura" and c["tdoc"] != "RUC":
        c = R.choice([x for x in clients if x["tdoc"] == "RUC"])
    issue = start + datetime.timedelta(days=int(n * 640 / 1500))
    cur = "USD" if R.random() < 0.05 else "PEN"
    ref = None
    if kind == "Nota de crédito":
        base_doc = R.choice(emitted)
        serie = "FC01" if base_doc[0] == "Factura" else "BC01"
        ref = base_doc[1]
        c = base_doc[2]
        cur = base_doc[3]
    else:
        serie = "F001" if kind == "Factura" else "B001"
    seq[serie] += 1
    num = seq[serie]
    fid = f"FAC-{n + 1:05d}"
    gross = 0.0; disc = 0.0
    for k in range(nlines[n]):
        it = R.choice(catalog)
        q = R.choice([1, 1, 1, 2, 3, 5, 10]) if it["unit"] == "NIU" else 1
        price = it["price"] if cur == "PEN" else round(it["price"] / 3.75, 2)
        dl = round(q * price * 0.05, 2) if R.random() < 0.1 else 0.0
        lt = round(q * price - dl, 2)
        lb = round(lt / 1.18, 2)
        lid += 1
        lines.append(dict(id=f"DET-{lid:05d}", fid=fid, line=k + 1, code=it["code"], desc=it["desc"], unit=it["unit"], q=q,
                          price=price, disc=dl, sub=lb, igv=round(lt - lb, 2), total=lt))
        gross += q * price; disc += dl
    gross = round(gross, 2); disc = round(disc, 2)
    total = round(gross - disc, 2)
    base = round(total / 1.18, 2)
    igv = round(total - base, 2)
    due = issue + datetime.timedelta(days=R.choice([0, 15, 30]))
    if kind == "Nota de crédito":
        estado = "Anulada" if R.random() < 0.05 else "Emitida"
        pagado, saldo = 0.0, 0.0
    else:
        r = R.random()
        estado = "Pagada" if r < .55 else "Parcial" if r < .65 else "Pendiente" if r < .80 else "Vencida" if r < .92 else "Anulada"
        if estado == "Pagada": pagado, saldo = total, 0.0
        elif estado == "Parcial":
            pagado = round(total * R.choice([.2, .5, .7]), 2); saldo = round(total - pagado, 2)
        elif estado == "Anulada": pagado, saldo = 0.0, 0.0
        else: pagado, saldo = 0.0, total
        if estado == "Vencida":
            due = issue + datetime.timedelta(days=15)
        emitted.append((kind, f"{serie}-{num:08d}", c, cur))
    name = c["name"] if n % 25 else ""  # algunas filas sin nombre: se toma de la hoja Clientes
    docs.append(dict(fid=fid, kind=kind, serie=serie, num=num, issue=issue, due=due, cid=c["id"], cname=name, tdoc=c["tdoc"],
                     doc=c["doc"], addr=c["addr"], mail=c["mail"], cur=cur, sub=gross, disc=disc, base=base, igv=igv,
                     total=total, estado=estado, pagado=pagado, saldo=saldo, ref=ref,
                     metodo=R.choice(["Efectivo", "Yape", "Transferencia", "Plin", ""]) if pagado else ""))

wb = Workbook()
ws = wb.active; ws.title = "LEEME"
ws.append(["Migración de facturas — archivo de ejemplo"])
ws.append([])
ws.append(["Hoja", "Columna", "Descripción"])
for h, col, d in [("Clientes", "id_cliente", "Código interno del cliente"), ("Clientes", "cliente_nombre_razon_social", "Nombre o razón social"),
                  ("Facturas", "id_factura", "Código interno del comprobante"), ("Facturas", "tipo_comprobante", "Factura, Boleta o Nota de crédito"),
                  ("Facturas", "estado", "Pagada, Parcial, Pendiente, Vencida o Anulada"), ("Facturas", "total", "Importe total con IGV"),
                  ("Detalle_Facturas", "codigo_item", "Código del producto"), ("Catalogo", "precio_unitario_con_igv", "Precio con IGV")]:
    ws.append([h, col, d])

ws = wb.create_sheet("Clientes")
ws.append(["id_cliente", "tipo_documento", "numero_documento", "cliente_nombre_razon_social", "direccion", "distrito", "telefono", "correo"])
for c in clients:
    ws.append([c["id"], c["tdoc"], c["doc"], c["name"], c["addr"], c["dist"], c["phone"], c["mail"]])

ws = wb.create_sheet("Facturas")
ws.append(["id_factura", "tipo_comprobante", "serie", "numero", "fecha_emision", "fecha_vencimiento", "id_cliente",
           "cliente_nombre_razon_social", "cliente_tipo_doc", "cliente_ruc_dni", "cliente_direccion", "cliente_correo", "moneda",
           "subtotal", "descuento", "base_imponible", "igv", "total", "estado", "pagado", "saldo", "metodo_pago", "doc_referencia"])
for d in docs:
    ws.append([d["fid"], d["kind"], d["serie"], d["num"], d["issue"], d["due"], d["cid"], d["cname"], d["tdoc"], d["doc"], d["addr"],
               d["mail"], d["cur"], d["sub"], d["disc"], d["base"], d["igv"], d["total"], d["estado"], d["pagado"], d["saldo"],
               d["metodo"], d["ref"] or ""])
for row in ws.iter_rows(min_row=2, min_col=5, max_col=6):
    for cell in row: cell.number_format = "dd/mm/yyyy"

ws = wb.create_sheet("Detalle_Facturas")
ws.append(["id_detalle", "id_factura", "linea", "codigo_item", "descripcion", "unidad", "cantidad", "precio_unitario_con_igv",
           "descuento", "subtotal", "igv", "total"])
for l in lines:
    ws.append([l["id"], l["fid"], l["line"], l["code"], l["desc"], l["unit"], l["q"], l["price"], l["disc"], l["sub"], l["igv"], l["total"]])

ws = wb.create_sheet("Catalogo")
ws.append(["Catálogo de productos y servicios"])
ws.append([])
ws.append(["codigo_item", "descripcion", "categoria", "unidad", "precio_unitario_con_igv", "afecto_igv"])
for p in catalog:
    ws.append([p["code"], p["desc"], p["cat"], p["unit"], p["price"], "Sí"])

out = os.path.join(HERE, "migracion_1500_sintetico.xlsx")
wb.save(out)

def net(cur):
    s = 0.0
    for d in docs:
        if d["cur"] != cur or d["estado"] == "Anulada": continue
        s += -d["total"] if d["kind"] == "Nota de crédito" else d["total"]
    return round(s, 2)

exp = dict(clients=250, documents=1500, facturas=1168, boletas=274, credit_notes=58, lines=3738, products=14,
           voided=sum(1 for d in docs if d["estado"] == "Anulada"),
           invalid_docs=sum(1 for c in clients if c["doc"] == "TESTDNI0000"),
           net_total={"PEN": net("PEN"), "USD": net("USD")},
           receivable={cur: round(sum(d["saldo"] for d in docs if d["cur"] == cur and d["estado"] in ("Parcial", "Pendiente", "Vencida")), 2) for cur in ("PEN", "USD")},
           collected={cur: round(sum(d["pagado"] for d in docs if d["cur"] == cur and d["estado"] != "Anulada" and d["kind"] != "Nota de crédito"), 2) for cur in ("PEN", "USD")})
json.dump(exp, open(os.path.join(HERE, "migracion_1500_esperado.json"), "w"), indent=1, ensure_ascii=False)
print(json.dumps(exp, ensure_ascii=False))
