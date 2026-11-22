import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV !== "production";

function contentSecurityPolicy(flutter: boolean) {
  return [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}${flutter ? " 'wasm-unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https://*.supabase.co",
    "font-src 'self' data:",
    "media-src 'self' blob:",
    `connect-src 'self' https://*.supabase.co wss://*.supabase.co${flutter ? " blob: https://fonts.gstatic.com" : ""}`,
    "worker-src 'self' blob:",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
  ].join("; ");
}

const nextConfig: NextConfig = {
  poweredByHeader: false,
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
