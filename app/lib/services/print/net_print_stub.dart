// Web: no hay sockets TCP en el navegador. Se usa el ticket en PDF.
Future<void> sendToNetworkPrinter(String host, int port, List<int> bytes) async {
  throw UnsupportedError('La impresión por red no está disponible en la versión web. Usa "Ticket en PDF".');
}
