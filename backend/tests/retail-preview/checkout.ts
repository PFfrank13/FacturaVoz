export async function checkout(): Promise<never> {
  throw new Error("QA: respuesta perdida, sin escritura remota");
}
