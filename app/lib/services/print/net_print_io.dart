// Android/iOS/escritorio: impresoras térmicas de red (Wi‑Fi/LAN) en el puerto RAW 9100.
import 'dart:io';

Future<void> sendToNetworkPrinter(String host, int port, List<int> bytes) async {
  final s = await Socket.connect(host, port, timeout: const Duration(seconds: 6));
  try {
    s.add(bytes);
    await s.flush();
  } finally {
    await s.close();
  }
}
