import { authenticateBearer, jsonWith, preflight } from "@/lib/api-auth";

export const OPTIONS = preflight;
/** El acceso comercial sólo se activa con una licencia de Solvex Hub. */
export async function POST(req: Request) {
  const json = jsonWith(req.headers.get("origin"));
  const auth = await authenticateBearer(req);
  if (!auth) return json({ error: "No autorizado" }, 401);
  return json({ error: "Prueba automática deshabilitada. Solicita una licencia a Solvex y actívala en la app." }, 403);
}
