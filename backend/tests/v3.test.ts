import { describe, expect, it } from "vitest";
import { partialJsonString } from "../src/lib/groq";

describe("Copiloto en tiempo real: lectura parcial del JSON", () => {
  it("devuelve el texto mientras se escribe", () => {
    expect(partialJsonString('{"answer":"Vendiste S/ 1', "answer")).toEqual({ text: "Vendiste S/ 1", done: false });
    expect(partialJsonString('{"answer":"Hola","intent":"question"}', "answer")).toEqual({ text: "Hola", done: true });
  });
  it("aún no empezó la propiedad", () => {
    expect(partialJsonString('{"ans', "answer")).toBeNull();
  });
  it("respeta comillas y escapes, sin cortar un escape a medias", () => {
    expect(partialJsonString('{"answer":"Dijo \\"hola\\" y\\n', "answer")?.text).toBe('Dijo "hola" y\n');
    expect(partialJsonString('{"answer":"a\\', "answer")?.text).toBe("a");
    expect(partialJsonString('{"answer":"ni\\u00f1o', "answer")?.text).toBe("niño");
    expect(partialJsonString('{"answer":"ni\\u00f', "answer")?.text).toBe("ni");
  });
});
