import { describe, expect, it } from "vitest";
import { canCut, isoToLimaLocal, jobStatuses, limaLocalToIso, noticeText, normPlate, obraSignal, splitEven, statusOf } from "@/lib/erp/rubros";

describe("módulos de otros rubros (web = app)", () => {
  it("estados de trabajos por rubro o los propios de la empresa", () => {
    expect(jobStatuses("taller", null).map(s => s.key)).toEqual(["nuevo", "diagnostico", "cotizado", "en_reparacion", "listo", "entregado"]);
    expect(jobStatuses("salon", null).some(s => s.key === "no_vino")).toBe(true);
    expect(jobStatuses(null, null).map(s => s.key)).toEqual(["nuevo", "en_proceso", "terminado"]);
    const own = jobStatuses("taller", [{ key: "x", label: "Equis", done: true, color: 0xff23956f }]);
    expect(own).toEqual([{ key: "x", label: "Equis", done: true, color: "#23956f" }]);
    expect(statusOf(own, "raro_estado").label).toBe("raro estado");
  });

  it("hora de Lima ida y vuelta", () => {
    expect(limaLocalToIso("2026-11-24T09:30")).toBe("2026-11-24T14:30:00.000Z");
    expect(isoToLimaLocal("2026-11-24T14:30:00.000Z")).toBe("2026-11-24T09:30");
    expect(limaLocalToIso("ayer")).toBeNull();
  });

  it("divide la cuenta al décimo y el último paga el resto", () => {
    expect(splitEven(100, 3)).toEqual([33.3, 33.3, 33.4]);
    expect(splitEven(50, 1)).toEqual([50]);
  });

  it("placas y obras", () => {
    expect(normPlate("abc-123 ")).toBe("ABC123");
    expect(obraSignal(1000, 200, 500).alert).toBe("faster");
    expect(obraSignal(1000, 600, 500).alert).toBe("none");
    expect(obraSignal(1000, 600, 1000).alert).toBe("over");
    expect(obraSignal(0, 0, 50).alert).toBe("none");
  });

  it("el corte solo se habilita un día después del aviso", () => {
    expect(canCut({}, "2026-11-24")).toBe(false);
    expect(canCut({ aviso_corte_fecha: "2026-11-24" }, "2026-11-24")).toBe(false);
    expect(canCut({ aviso_corte_fecha: "2026-11-23" }, "2026-11-24")).toBe(true);
    expect(noticeText({ aviso_pension_fecha: "2026-11-20" }, "aviso_pension_fecha", "2026-11-24")).toBe("Avisado hace 4 días");
    expect(noticeText({}, "aviso_corte_fecha", "2026-11-24", "Sin aviso previo")).toBe("Sin aviso previo");
  });
});
