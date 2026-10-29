// Ubicación actual del teléfono (para guardar dónde vive el cliente o dónde fue el trabajo). Gratis, sin servidores.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import '../errors.dart';

Future<({double lat, double lng})> currentLocation() async {
  try {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
      throw AppException('Activa la ubicación (GPS) del teléfono.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw AppException('Permite la ubicación para FacturaVoz en los ajustes del teléfono.');
    }
    final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20));
    return (lat: p.latitude, lng: p.longitude);
  } on AppException {
    rethrow;
  } catch (_) {
    throw AppException('No se pudo obtener tu ubicación. Prueba pegando un enlace de Google Maps.');
  }
}
