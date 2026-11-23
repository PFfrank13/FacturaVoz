import { describe, expect, it } from "vitest";
import { couponProblem, couponState, discountLabel, promoProblem, promoState } from "@/lib/erp/loyalty";

const money = (v: number) => `S/ ${v.toFixed(2)}`;

describe("promociones y cupones", () => {
  it("describe el descuento como en el móvil", () => {
    expect(discountLabel("porcentaje", 10, null, money)).toBe("10 % menos");
    expect(discountLabel("monto", 1.5, null, money)).toBe("S/ 1.50 menos");
    expect(discountLabel("volumen", 15, 3, money)).toBe("llevando 3 o más, 15 % menos");
  });

  it("sabe si una promoción está activa, programada, terminada o pausada", () => {
    const t = "2026-11-23";
    expect(promoState({ active: true, starts_on: null, ends_on: null }, t)).toBe("activa");
    expect(promoState({ active: true, starts_on: "2026-12-01", ends_on: null }, t)).toBe("programada");
    expect(promoState({ active: true, starts_on: null, ends_on: "2026-11-22" }, t)).toBe("terminada");
    expect(promoState({ active: false, starts_on: null, ends_on: null }, t)).toBe("pausada");
    expect(couponState({ active: true, expires_on: null, max_uses: 5, uses: 5 }, t)).toBe("agotado");
    expect(couponState({ active: true, expires_on: "2026-11-01", max_uses: null, uses: 0 }, t)).toBe("vencido");
  });

  it("valida los formularios con mensajes claros", () => {
    expect(promoProblem({ name: "", kind: "porcentaje", value: 10, minQty: null, startsOn: "", endsOn: "" })).toMatch(/nombre/);
    expect(promoProblem({ name: "Verano", kind: "porcentaje", value: 95, minQty: null, startsOn: "", endsOn: "" })).toMatch(/90 %/);
    expect(promoProblem({ name: "Verano", kind: "volumen", value: 10, minQty: 1, startsOn: "", endsOn: "" })).toMatch(/2 o más/);
    expect(promoProblem({ name: "Verano", kind: "monto", value: 2, minQty: null, startsOn: "2026-12-10", endsOn: "2026-12-01" })).toMatch(/anterior/);
    expect(promoProblem({ name: "Verano", kind: "monto", value: 2, minQty: null, startsOn: "", endsOn: "" })).toBeNull();
    expect(couponProblem({ code: "a b", kind: "monto", value: 2, maxUses: null })).toMatch(/código/);
    expect(couponProblem({ code: "VECINO10", kind: "porcentaje", value: 10, maxUses: 0 })).toMatch(/usos/);
    expect(couponProblem({ code: "VECINO10", kind: "porcentaje", value: 10, maxUses: 50 })).toBeNull();
  });
});
