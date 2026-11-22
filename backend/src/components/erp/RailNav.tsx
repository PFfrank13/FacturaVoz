"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

/** Rail links with the current section marked for sighted and screen reader users. */
export default function RailNav({ links }: { links: readonly { href: string; label: string }[] }) {
  const path = usePathname();
  return <nav aria-label="Navegación de la empresa">
    {links.map((l, i) => {
      const current = i === 0 ? path === l.href : path === l.href || path.startsWith(`${l.href}/`);
      return <Link key={l.href} href={l.href} aria-current={current ? "page" : undefined}>{l.label}</Link>;
    })}
  </nav>;
}
