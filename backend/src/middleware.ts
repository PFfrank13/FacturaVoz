import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { safeNext } from "@/lib/safe-next";

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll(list) {
          list.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          list.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const p = request.nextUrl.pathname;
  if (!user && !p.startsWith("/login") && !p.startsWith("/auth")) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    // Volver al enlace de la empresa tras iniciar sesión (solo rutas internas validadas en safeNext).
    const next = safeNext(p);
    if (next) url.searchParams.set("next", next);
    return NextResponse.redirect(url);
  }
  return response;
}

export const config = {
  // Todas las rutas /api se autentican a sí mismas (Bearer, cookie, CRON_SECRET o token público); si pasaran por aquí,
  // las apps móviles serían redirigidas a /login. /cotizacion, /pagar y /tienda son páginas públicas para el cliente final.
  // /portal, /comprobante, /encuesta y /reservar (v2.0) también son públicas (cliente final, sin cuenta).
  matcher: ["/((?!_next/static|_next/image|favicon.ico|api/|cotizacion/|pagar/|tienda/|portal/|comprobante/|encuesta/|reservar/).*)"],
};
