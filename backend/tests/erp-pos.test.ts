import { describe, expect, it } from "vitest";
import { addToCart, cartTotals, changeFor, ean13Check, findByCode, parseScaleLabel, quickCash, searchProducts, setQuantity, stockProblems, type PosProduct } from "@/lib/erp/pos";

const p = (id: string, name: string, price: number, extra: Partial<PosProduct> = {}): PosProduct =>
  ({ id, name, unit_price: price, unit: "NIU", stock: null, barcode: null, icbper: false, category: null, image_url: null, ...extra });

const products = [
  p("a", "Papel Noble 4 rollos", 4, { barcode: "7751234500011", stock: 10 }),
  p("b", "Queso fresco", 22, { unit: "KGM", barcode: "00123" }),
  p("c", "Gaseosa 500 ml", 2.5, { category: "Bebidas" }),
];

describe("venta rápida web", () => {
  it("encuentra por código principal y por código adicional", () => {
    expect(findByCode("7751234500011", products, {})?.product.id).toBe("a");
    expect(findByCode("7759999999999", products, { "7759999999999": "a" })?.product.id).toBe("a");
    expect(findByCode("000", products, {})).toBeNull();
  });

  it("lee la etiqueta de la balanza: PLU y peso", () => {
    const base = "20" + "00123" + "00750"; // prefijo 20, PLU 00123, 750 g
    const code = base + ean13Check(base);
    expect(parseScaleLabel(code)).toEqual({ plu: "00123", prefixPlu: "2000123", kilos: 0.75 });
    const hit = findByCode(code, products, {});
    expect(hit?.product.id).toBe("b");
    expect(hit?.quantity).toBe(0.75);
    expect(parseScaleLabel(base + ((ean13Check(base) + 1) % 10))).toBeNull();
  });

  it("suma el mismo producto, cambia cantidades y calcula total y vuelto", () => {
    let cart = addToCart([], products[0], 1);
    cart = addToCart(cart, products[0], 2);
    cart = addToCart(cart, products[2], 1);
    expect(cart).toHaveLength(2);
    expect(cart[0].quantity).toBe(3);
    expect(cartTotals(cart, 0).total).toBe(14.5);
    // Igual que el móvil: IGV por línea redondeado (12 → 2.16; 2.5 → 0.45).
    expect(cartTotals(cart, 18)).toEqual({ subtotal: 14.5, tax: 2.61, total: 17.11 });
    expect(changeFor(14.5, 20)).toBe(5.5);
    expect(changeFor(14.5, 10)).toBeNull();
    cart = setQuantity(cart, "c", 0);
    expect(cart.map(l => l.product_id)).toEqual(["a"]);
  });

  it("avisa si falta stock", () => {
    expect(stockProblems(addToCart([], products[0], 11))).toEqual(["Papel Noble 4 rollos: quedan 10"]);
    expect(stockProblems(addToCart([], products[2], 99))).toEqual([]);
  });

  it("billetes rápidos y búsqueda sin tildes", () => {
    expect(quickCash(14.5)).toEqual([14.5, 15, 20, 50, 100]);
    expect(searchProducts("gaseosa", products).map(x => x.id)).toEqual(["c"]);
    expect(searchProducts("bebidas", products).map(x => x.id)).toEqual(["c"]);
    expect(searchProducts("QUESO", products).map(x => x.id)).toEqual(["b"]);
  });
});
