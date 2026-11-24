import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV !== "production";

/** The configured Supabase origin (custom domain or local stack), when it is not *.supabase.co. */
function supabaseOrigins(): { http: string; socket: string } {
  try {
    const url = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL ?? "");
    if (url.hostname.endsWith(".supabase.co")) return { http: "", socket: "" };
    return { http: ` ${url.origin}`, socket: ` ${url.protocol === "https:" ? "wss:" : "ws:"}//${url.host}` };
  } catch {
    return { http: "", socket: "" };
  }
}

function contentSecurityPolicy(flutter: boolean) {
  const supabase = supabaseOrigins();
  return [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}${flutter ? " 'wasm-unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: https://*.supabase.co${supabase.http}`,
    "font-src 'self' data:",
    "media-src 'self' blob:",
    `connect-src 'self' https://*.supabase.co wss://*.supabase.co${supabase.http}${supabase.socket}${flutter ? " blob: https://fonts.gstatic.com" : ""}`,
    "worker-src 'self' blob:",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
  ].join("; ");
}

const nextConfig: NextConfig = {
  poweredByHeader: false,
  // Volver a una sección ya abierta es instantáneo durante 30 s (el contenido en vivo se refresca solo con
  // LiveRefresh y cada acción llama a router.refresh / revalidatePath, así que no se ven datos viejos).
  experimental: { staleTimes: { dynamic: 30, static: 180 } },
  async rewrites() {
    return [{ source: "/app", destination: "/app/index.html" }];
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
          { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
        ],
      },
      {
        source: "/:path((?!app(?:/|$)).*)",
        headers: [
          { key: "Content-Security-Policy", value: contentSecurityPolicy(false) },
          { key: "Permissions-Policy", value: "microphone=(self), camera=(), geolocation=(), payment=()" },
        ],
      },
      {
        source: "/app/:path*",
        headers: [
          { key: "Content-Security-Policy", value: contentSecurityPolicy(true) },
          { key: "Permissions-Policy", value: "microphone=(self), camera=(self), geolocation=(self), payment=()" },
        ],
      },
    ];
  },
};

export default nextConfig;
