import 'package:flutter/material.dart';

import '../services/app_updater.dart';
import 'liquid_glass.dart';

/// Offers a new version when one is published. Checks on start and whenever
/// the app returns to the foreground; stays out of the way otherwise.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> with WidgetsBindingObserver {
  final _updater = AppUpdater.instance;
  String? _message;
  bool _dismissed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updater.check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _updater.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _update(AppRelease release) async {
    setState(() { _busy = true; _message = null; });
    final ok = await _updater.download(release);
    if (!mounted) return;
    if (!ok) {
      setState(() { _busy = false; _message = 'No se pudo descargar o verificar la actualización. Inténtalo con mejor conexión.'; });
      return;
    }
    final start = await _updater.install();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (start) {
        InstallStart.started => 'Confirma «Actualizar» en la ventana de Android.',
        InstallStart.needsPermission => 'Activa «Permitir de esta fuente» para FacturaVoz, vuelve y toca Actualizar otra vez.',
        InstallStart.failed => 'No se pudo abrir el instalador.',
      };
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppRelease?>(
    valueListenable: _updater.available,
    builder: (context, release, _) {
      if (release == null || (_dismissed && !release.mandatory)) return const SizedBox.shrink();
      final t = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: FvLiquidGlass(
          key: const ValueKey('app-update-banner'),
          radius: 22,
          blur: 0,
          tint: const Color(0xFF3EE6B0),
          strength: 1.6,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.system_update_rounded, color: Color(0xFF19A88A)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nueva versión ${release.versionName} lista',
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (release.notes.isNotEmpty)
                  Text(release.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
              ])),
              if (!release.mandatory && !_busy)
                IconButton(
                  tooltip: 'Más tarde',
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ]),
            const SizedBox(height: 8),
            ValueListenableBuilder<double?>(
              valueListenable: _updater.progress,
              builder: (context, value, _) => value == null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _update(release),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Actualizar'),
                      ),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      LinearProgressIndicator(value: value, minHeight: 6, borderRadius: BorderRadius.circular(6)),
                      const SizedBox(height: 4),
                      Text('Descargando ${(value * 100).round()} %', style: t.textTheme.labelSmall),
                    ]),
            ),
            if (_message != null) ...[
              const SizedBox(height: 6),
              Text(_message!, style: t.textTheme.bodySmall),
            ],
          ]),
        ),
      );
    },
  );
}
