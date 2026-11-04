import "server-only";
import { redirect, notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { sectorFor, type License, type Access } from "./access";

/** No service-role client: membership, RPCs and reads retain the user's RLS context. */
export async function workspaceContext(org: string) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(org)) notFound();
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) redirect("/login");
  const membership = await db.from("organization_members").select("org_id").eq("org_id", org).eq("user_id", user.id).maybeSingle();
  if (membership.error || !membership.data) notFound();
  const [license, access, organization, settings] = await Promise.all([
    db.rpc("my_license", { p_org: org }), db.rpc("my_access", { p_org: org }),
    db.from("organizations").select("id,name,currency,tax_id,address,default_tax_rate").eq("id", org).single(),
    db.from("org_settings").select("business_type").eq("org_id", org).maybeSingle(),
  ]);
  if (license.error || access.error || organization.error || settings.error) throw new Error("No se pudo verificar el acceso a la empresa.");
  return { db, user, org, license: (license.data ?? {}) as License, access: (access.data ?? {}) as Access,
    organization: organization.data, sector: sectorFor(settings.data?.business_type ?? "") };
}
