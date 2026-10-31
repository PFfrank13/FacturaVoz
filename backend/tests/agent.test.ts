import { describe, expect, it } from "vitest";
import { AGENT_ACTIONS, collectionMessage, sanitizePlan, suggestedQty } from "../src/lib/agent";
import { copilotTier, copilotTierBlock, rubroPromptBlock } from "../src/lib/rubro-copilot";

describe("Copiloto agente: lista cerrada de acciones", () => {
  it("descarta acciones que no existen, repetidas y exceso de pasos", () => {
    const p = sanitizePlan({ title: "x", steps: [{ action: "borrar_todo" }, { action: "cobranza" }, { action: "cobranza" }, { action: "emitir_sunat" }, { action: "resumen" }, { action: "reposicion" }, { action: "recordatorios" }, { action: "resumen" }] });
    expect(p?.steps.map((s) => s.action)).toEqual(["cobranza", "resumen", "reposicion", "recordatorios"]);
    for (const s of p!.steps) expect(AGENT_ACTIONS).toContain(s.action);
  });
  it("acota parámetros y rechaza planes vacíos", () => {
    const p = sanitizePlan({ title: "", steps: [{ action: "recordatorios", days: 9999, max: -5 }] });
    expect(p?.steps[0]).toEqual({ action: "recordatorios", days: 30, max: 1 });
    expect(p?.title).toBe("Tarea del Copiloto");
    expect(sanitizePlan({ title: "a", steps: [] })).toBeNull();
    expect(sanitizePlan(null)).toBeNull();
  });
  it("mensaje de cobro con datos reales y sin inventar", () => {
    const m = collectionMessage("Rosa Pérez", 30, 5, "Bodega Lola");
    expect(m).toContain("Hola Rosa");
    expect(m).toContain("S/ 30.00");
    expect(m).toContain("5 días");
    expect(collectionMessage("Ana", 10, 0, "")).not.toContain("vencido");
  });
  it("cantidad sugerida de reposición", () => {
    expect(suggestedQty(1, 3, 2)).toBe(27); // 14 días × 2 = 28 − 1
    expect(suggestedQty(10, 3, 0)).toBe(0);
    expect(suggestedQty(1, 3, 0)).toBe(2);
  });
});

describe("Copiloto por plan", () => {
  it("Empresa: asesor que se adelanta y manda las tareas largas a Tareas del Copiloto", () => {
    expect(copilotTier({ copiloto_agente: true })).toBe("empresa");
    expect(copilotTierBlock({ copiloto_agente: true })).toMatch(/Lo que yo haría hoy/);
    expect(copilotTierBlock({ copiloto_agente: true })).toMatch(/Tareas del Copiloto/);
  });
  it("Pro: responde y propone; las tareas delegadas son de Empresa", () => {
    expect(copilotTier({ copiloto: true, copiloto_agente: false })).toBe("pro");
    expect(copilotTierBlock(null)).toMatch(/plan Empresa/);
    expect(rubroPromptBlock({ rubro: "bodega", role: "owner", canMoney: true, plan: "PRO", features: { copiloto_agente: false } })).toMatch(/Nivel del Copiloto: PRO/);
  });
});
