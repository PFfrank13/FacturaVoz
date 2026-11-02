// Logo y diseño de comprobantes + impresora de tickets (Fase 3 y 4).
// El logo se guarda en Storage PRIVADO (carpeta de la empresa; solo administradores lo cambian) y se usa en el PDF A4,
// en el ticket térmico (convertido a blanco y negro) y en las páginas públicas del comprobante.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../access.dart';
import '../errors.dart';
import '../services/print/ticket_printer.dart';
import '../services/v2_repo.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const pdfTemplates = {'clasico': ('Clásico', 'Encabezado editorial, jerarquía limpia y datos claros'), 'moderno': ('Moderno', 'Diseño contemporáneo, contraste y total destacado'), 'minimal': ('Minimal', 'Elegante y sobrio, óptimo para impresión económica')};
const brandColors = ['#1E3A8A', '#6A62E2', '#0F766E', '#B91C1C', '#C2410C', '#111827'];

Color _hex(String h) => Color(int.parse('FF${h.replaceAll('#', '')}', radix: 16));

class BrandingScreen extends StatefulWidget {
  const BrandingScreen({super.key});

  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> {
  Map<String, dynamic>? _b;
  Uint8List? _logo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await V2Repo.branding();
    final logo = await V2Repo.download(b['logo_path'] as String?);
    if (mounted) {
      setState(() {
        _b = Map<String, dynamic>.from(b);
        _logo = logo;
      });
    }
  }

  Future<void> _save(Map<String, dynamic> fields, {String ok = 'Guardado'}) async {
    setState(() => _busy = true);
    try {
      await V2Repo.saveBranding(fields);
      if (mounted) {
        setState(() => _b = {...?_b, ...fields});
        showSuccess(context, ok);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is AppException ? e.message : V2Repo.missingHint(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickLogo() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, maxHeight: 900, imageQuality: 88);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) throw AppException('La imagen pesa más de 5 MB.');
      final png = x.name.toLowerCase().endsWith('.png');
      setState(() => _busy = true);
      final path = await V2Repo.upload('logo', bytes, ext: png ? 'png' : 'jpg');
      setState(() => _logo = bytes);
      await _save({'logo_path': path}, ok: 'Logo actualizado');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is AppException ? e.message : V2Repo.missingHint(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = _b;
    final admin = Access.instance.can('settings');
    return Scaffold(
      appBar: AppBar(title: const Text('Logo y comprobantes')),
      body: b == null
          ? const SkeletonList(count: 3)
          : AbsorbPointer(
              absorbing: _busy || !admin,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                if (!admin) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Solo el dueño o un administrador puede cambiar esto.', style: t.textTheme.bodySmall)),
                SoftCard(
                  child: Row(children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(Radii.lg)),
                      child: _logo == null ? const Icon(Icons.add_photo_alternate_rounded, size: 36) : ClipRRect(borderRadius: BorderRadius.circular(Radii.lg), child: Image.memory(_logo!, fit: BoxFit.contain)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Logo de tu negocio', style: t.textTheme.titleSmall),
                        Text('PNG o JPG, fondo blanco o transparente. Sale en el PDF, el ticket y tu tienda.', style: t.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          FilledButton.tonal(onPressed: _pickLogo, child: Text(_logo == null ? 'Subir logo' : 'Cambiar')),
                          if (_logo != null)
                            TextButton(
                              onPressed: () async {
                                await _save({'logo_path': null}, ok: 'Logo quitado');
                                setState(() => _logo = null);
                              },
                              child: const Text('Quitar'),
                            ),
                        ]),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const SectionTitle('Plantilla profesional del comprobante (A4)'),
                for (final e in pdfTemplates.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Pressable(
                      onTap: () => _save({'pdf_template': e.key}, ok: 'Diseño: ${e.value.$1}'),
                      child: SoftCard(
                        padding: const EdgeInsets.all(14),
                        color: b['pdf_template'] == e.key || (b['pdf_template'] == null && e.key == 'clasico') ? t.colorScheme.primary.withValues(alpha: 0.10) : null,
                        child: Row(children: [
                          Icon(b['pdf_template'] == e.key || (b['pdf_template'] == null && e.key == 'clasico') ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: t.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.value.$1, style: t.textTheme.titleSmall), Text(e.value.$2, style: t.textTheme.bodySmall)])),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const SectionTitle('Color de marca'),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final c in brandColors)
                    Pressable(
                      onTap: () => _save({'brand_color': c}, ok: 'Color guardado'),
                      child: AnimatedContainer(
                        duration: Motion.d(context, Motion.fast),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _hex(c),
                          shape: BoxShape.circle,
                          border: Border.all(color: (b['brand_color'] ?? '#1E3A8A').toString().toUpperCase() == c ? t.colorScheme.onSurface : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                const SectionTitle('Ancho del ticket'),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
                  selected: {((b['ticket_width'] as num?) ?? 80).toInt() == 58 ? 58 : 80},
                  onSelectionChanged: (s) => _save({'ticket_width': s.first}, ok: 'Ticket de ${s.first} mm'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Configurar impresora de tickets'),
                ),
              ]),
            ),
    );
  }
}

// ═════════════════════════ Impresora ═════════════════════════
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterConfig? _c;
  List<BtDevice> _devices = const [];
  final _ip = TextEditingController();
  String _msg = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    V2Repo.branding().then((b) async {
      final c = await PrinterStore.load(orgWidth: (b['ticket_width'] as num?)?.toInt());
      if (!mounted) return;
      setState(() {
        _c = c;
        if (c.kind == 'net') _ip.text = c.address;
      });
    });
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _set(PrinterConfig c) async {
    setState(() => _c = c);
    await PrinterStore.save(c);
  }

  Future<void> _scanBt() async {
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      final d = await pairedPrinters();
      setState(() {
        _devices = d;
        _msg = d.isEmpty ? 'No hay impresoras emparejadas. Empareja la impresora en Ajustes → Bluetooth del teléfono (PIN usual: 0000 o 1234).' : '';
      });
    } catch (e) {
      setState(() => _msg = e is StateError ? e.message : 'No se pudo usar el Bluetooth: revisa el permiso "Dispositivos cercanos".');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _test() async {
    final c = _c;
    if (c == null) return;
    final data = TicketData(
      issuerName: 'PRUEBA DE IMPRESIÓN',
      issuerRuc: '',
      issuerAddress: 'FacturaVoz',
      title: 'TICKET DE PRUEBA',
      number: 'Ñandú ✓ áéíóú',
      date: DateTime.now().toString().substring(0, 16),
      clientName: '',
      clientDoc: '',
      currency: 'PEN',
      lines: const [TicketLine(1.0, 'Producto de prueba', 10.0, 10.0)],
      totals: const [('TOTAL', 10.0, true)],
      qr: 'https://www.sunat.gob.pe',
      warning: 'SIN VALOR',
    );
    setState(() {
      _busy = true;
      _msg = '';
    });
    try {
      if (c.kind == 'pdf') {
        final pdf = await buildTicketPdf(data, width: c.width);
        await Printing.layoutPdf(name: 'ticket-prueba.pdf', onLayout: (_) => pdf);
      } else {
        await sendEscPos(c, buildEscPosTicket(data, width: c.width, nativeQr: c.nativeQr, openDrawer: c.openDrawer));
        _msg = '¡Listo! Si el QR no salió, desactiva "QR nativo".';
      }
    } catch (e) {
      _msg = e is StateError ? e.message : friendly(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Impresora de tickets')),
      body: c == null
          ? const SkeletonList(count: 3)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              SegmentedButton<String>(
                segments: [
                  if (bluetoothSupported) const ButtonSegment(value: 'bt', label: Text('Bluetooth'), icon: Icon(Icons.bluetooth_rounded)),
                  if (networkSupported) const ButtonSegment(value: 'net', label: Text('Red / Wi‑Fi'), icon: Icon(Icons.wifi_rounded)),
                  const ButtonSegment(value: 'pdf', label: Text('PDF'), icon: Icon(Icons.picture_as_pdf_rounded)),
                ],
                selected: {c.kind},
                onSelectionChanged: (s) => _set(c.copyWith(kind: s.first)),
              ),
              const SizedBox(height: 12),
              if (c.kind == 'bt') ...[
                Text('Funciona con ticketeras Bluetooth ESC/POS (Epson, Xprinter, GOOJPRT y similares). En iPhone solo las compatibles con BLE.', style: t.textTheme.bodySmall),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(onPressed: _busy ? null : _scanBt, icon: const Icon(Icons.search_rounded), label: const Text('Buscar impresoras emparejadas')),
                for (final d in _devices)
                  ListTile(
                    leading: const Icon(Icons.print_rounded),
                    title: Text(d.name),
                    subtitle: Text(d.mac),
                    trailing: c.address == d.mac ? const Icon(Icons.check_circle_rounded, color: Brand.ok) : null,
                    onTap: () => _set(c.copyWith(address: d.mac, name: d.name)),
                  ),
                if (c.address.isNotEmpty && _devices.isEmpty) ListTile(leading: const Icon(Icons.print_rounded), title: Text(c.name), subtitle: Text('Elegida · ${c.address}')),
              ],
              if (c.kind == 'net') ...[
                TextField(
                  controller: _ip,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'IP de la impresora (ej.: 192.168.1.50 o 192.168.1.50:9100)'),
                  onChanged: (v) => _set(c.copyWith(address: v.trim(), name: v.trim())),
                ),
                const SizedBox(height: 4),
                Text('La IP aparece en la hoja de autoprueba de la impresora (mantén presionado FEED al encenderla). El teléfono debe estar en la misma red.', style: t.textTheme.bodySmall),
              ],
              if (c.kind == 'pdf') Text('Se abre un PDF del tamaño del rollo: sirve para cualquier impresora (USB, de red o compartir por WhatsApp).', style: t.textTheme.bodySmall),
              const SizedBox(height: 14),
              SegmentedButton<int>(
                segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
                selected: {c.width},
                onSelectionChanged: (s) => _set(c.copyWith(width: s.first)),
              ),
              if (c.kind != 'pdf') ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: c.nativeQr,
                  onChanged: (v) => _set(c.copyWith(nativeQr: v)),
                  title: const Text('QR nativo de la impresora'),
                  subtitle: const Text('Apágalo si el código QR no sale (se imprimirá como imagen).'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: c.openDrawer,
                  onChanged: (v) => _set(c.copyWith(openDrawer: v)),
                  title: const Text('Abrir el cajón de dinero al imprimir'),
                ),
              ],
              const SizedBox(height: 12),
              GradientButton(label: 'Imprimir prueba', icon: Icons.print_rounded, busy: _busy, onPressed: _busy ? null : _test),
              if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg, textAlign: TextAlign.center)),
              const SizedBox(height: 16),
              Text(
                'No disponible: impresoras USB conectadas al teléfono y la impresión directa desde la versión web. En esos casos usa "PDF".',
                style: t.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ]),
    );
  }
}
