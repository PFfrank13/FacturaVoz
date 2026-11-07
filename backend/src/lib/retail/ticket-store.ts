import { z } from "zod";

const draftSchema = z.object({
  version: z.literal(1), org: z.string().min(1), user: z.string().min(1), revision: z.number().int().positive(),
  currency: z.string().regex(/^[A-Z]{3}$/), taxBasisPoints: z.number().int().min(0).max(10000),
  savedAt: z.string(), operationId: z.uuid().nullable(),
  method: z.enum(["efectivo", "yape", "plin", "tarjeta", "transferencia"]),
  lines: z.array(z.object({ id: z.uuid(), name: z.string().max(500), unitPriceCents: z.number().int().nonnegative().max(1000000000), quantityMilli: z.number().int().positive().max(100000000) })).max(50),
});
export type TicketDraft = z.infer<typeof draftSchema>;
export type TicketContent = Omit<TicketDraft, "version" | "revision" | "savedAt" | "org" | "user">;
type StoragePort = Pick<Storage, "getItem" | "setItem">;

/** Draft recovery only. This is not a ledger or a confirmed offline sale. */
export class TicketStore {
  readonly key: string;
  constructor(private storage: StoragePort, private org: string, private user: string) {
    this.key = `solvex-retail:ticket:v1:${encodeURIComponent(org)}:${encodeURIComponent(user)}`;
  }
  read(): TicketDraft | null {
    const raw = this.storage.getItem(this.key);
    if (!raw) return null;
    const draft = draftSchema.parse(JSON.parse(raw));
    if (draft.org !== this.org || draft.user !== this.user) throw new Error("El ticket pertenece a otra sesión");
    if (new Set(draft.lines.map(l => l.id)).size !== draft.lines.length) throw new Error("Ticket con líneas duplicadas");
    return draft;
  }
  save(content: TicketContent, expectedRevision: number): TicketDraft {
    const existing = this.read();
    if ((existing?.revision ?? 0) !== expectedRevision) throw new Error("El ticket cambió en otra pestaña. Recarga para recuperar su última versión.");
    const next = draftSchema.parse({ ...content, org: this.org, user: this.user, version: 1,
      revision: expectedRevision + 1, savedAt: new Date().toISOString() });
    this.storage.setItem(this.key, JSON.stringify(next));
    // Fail rather than advertise persistence if the adapter did not retain the write.
    if (this.storage.getItem(this.key) !== JSON.stringify(next)) throw new Error("No se pudo verificar el guardado local");
    return next;
  }
}
