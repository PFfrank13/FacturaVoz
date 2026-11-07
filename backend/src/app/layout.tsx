import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
const retailFont = localFont({ variable: "--font-retail", display: "swap", src: [
  { path: "../../public/fonts/Inter-Regular.otf", weight: "400" },
  { path: "../../public/fonts/Inter-Medium.otf", weight: "500" },
  { path: "../../public/fonts/Inter-SemiBold.otf", weight: "600" },
  { path: "../../public/fonts/Inter-Bold.otf", weight: "700" },
] });

export const metadata: Metadata = {
  title: "FacturaVoz",
  description: "Administración de tienda de FacturaVoz, por Solvex Software Labs.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es">
      <body
        className={`${retailFont.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
