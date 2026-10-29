// Mapa pequeño de la ubicación del cliente o del trabajo (OpenStreetMap: gratis, sin clave). Solo lectura:
// el botón "Cómo llegar" abre Google Maps/Waze del teléfono. Respeta la política de uso de OSM (agente propio y crédito).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

class MiniMap extends StatelessWidget {
  const MiniMap({super.key, required this.lat, required this.lng, this.height = 160});
  final double lat;
  final double lng;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = LatLng(lat, lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: height,
        child: RepaintBoundary(
          child: FlutterMap(
            options: MapOptions(initialCenter: p, initialZoom: 16, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.facturavoz.app'),
              MarkerLayer(markers: [
                Marker(point: p, width: 44, height: 44, alignment: Alignment.topCenter, child: const Icon(Icons.location_on_rounded, color: Brand.bad, size: 44)),
              ]),
              const SimpleAttributionWidget(source: Text('OpenStreetMap')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre la app de mapas del teléfono con la ruta hasta el punto (sin claves ni costo).
Future<bool> openDirections(double lat, double lng) =>
    launchUrl(Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': '$lat,$lng'}), mode: LaunchMode.externalApplication);

Future<bool> openMapSearch(String address) =>
    launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address}), mode: LaunchMode.externalApplication);
