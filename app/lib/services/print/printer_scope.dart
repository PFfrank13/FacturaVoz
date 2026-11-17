/// Phase 5: printer devices are local settings scoped to ONE tenant.
///
/// Never read the legacy global key (fv_printer_v2): it could send another
/// company's receipt to the wrong physical device after switching orgs.
String? printerStorageKey(String? orgId) {
  if (orgId == null || orgId.trim().isEmpty) return null;
  final id = orgId.trim();
  return 'fv_printer_v3_org_$id';
}

/// Parse a LAN ESC/POS printer endpoint without silently accepting a bad port.
/// IPv4 and DNS hostnames are supported; IPv6 literals require a future format.
({String host, int port}) parsePrinterEndpoint(String address) {
  final parts = address.trim().split(':');
  final host = parts.first.trim();
  final port = parts.length == 2 ? int.tryParse(parts[1]) : 9100;
  if (parts.length > 2 || host.isEmpty ||
      !RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host) ||
      port == null || port < 1 || port > 65535) {
    throw StateError('IP o puerto de la impresora inválidos. Revísalos en Ajustes.');
  }
  return (host: host, port: port);
}
