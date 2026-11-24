import "server-only";
import { cache } from "react";
import { redirect, notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { sectorFor, type License, type Access } from "./access";

/**
 * No service-role client: membership, RPCs and reads retain the user's RLS context.
 * Wrapped in React `cache`: the layout and the page of one request share a single check (it used to run twice
 * per click), and the membership check runs in parallel with the rest (one round trip instead of two).
 */
export const workspaceContext = cache(async (org: string) => {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(org)) notFound();
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) redirect("/login");
  const [membership, license, access, organization, settings] = await Promise.all([
    db.from("organization_members").select("org_id").eq("org_id", org).eq("user_id", user.id).maybeSingle(),
    db.rpc("my_license", { p_org: org }), db.rpc("my_access", { p_org: org }),
    db.from("organizations").select("id,name,currency,tax_id,address,default_tax_rate").eq("id", org).maybeSingle(),
    db.from("org_settings").select("business_type").eq("org_id", org).maybeSingle(),
  ]);
  // Not a member: the license and access RPCs fail too, so membership is checked first.
  if (membership.error || !membership.data) notFound();
  if (license.error || access.error || organization.error || !organization.data || settings.error) throw new Error("No se pudo verificar el acceso a la empresa.");
  return { db, user, org, license: (license.data ?? {}) as License, access: (access.data ?? {}) as Access,
    organization: organization.data, sector: sectorFor(settings.data?.business_type ?? "") };
});
