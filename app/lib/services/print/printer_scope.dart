/// Phase 5: printer devices are local settings scoped to ONE tenant.
///
/// Never read the legacy global key (fv_printer_v2): it could send another
/// company's receipt to the wrong physical device after switching orgs.
String? printerStorageKey(String? orgId) {
  if (orgId == null || orgId.trim().isEmpty) return null;
  final id = orgId.trim();
  return 'fv_printer_v3_org_$id';
}
