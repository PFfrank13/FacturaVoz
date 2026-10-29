// Generador ESC/POS puro (sin plugins) para ticketeras térmicas de 58 mm y 80 mm (Epson y compatibles).
// - Logo del EMISOR convertido a monocromo con difuminado Floyd–Steinberg e impreso como imagen raster (GS v 0).
// - Código QR SUNAT con el comando nativo de la impresora (GS ( k, modelo 2, corrección Q) y, si la impresora no
//   lo soporta, como imagen (se pasa la matriz ya calculada).
// - Texto en la página de códigos 1252 (tildes y ñ); lo que no exista se translitera.
import 'dart:convert';
import 'dart:typed_data';

/// Ancho útil en puntos y caracteres por línea (fuente A) de cada papel.
class Paper {
  const Paper(this.mm, this.dots, this.chars);
  final int mm;
  final int dots;
  final int chars;
  static const mm58 = Paper(58, 384, 32);
  static const mm80 = Paper(80, 576, 48);
  static Paper of(int mm) => mm == 58 ? mm58 : mm80;
}

/// Imagen 1 bit lista para GS v 0: [width] múltiplo de 8, [data] = filas de width/8 bytes (bit 1 = negro).
class Raster {
  const Raster(this.width, this.height, this.data);
  final int width;
  final int height;
  final Uint8List data;
}

/// RGBA (como lo entrega Flutter) → monocromo difuminado del ancho pedido (proporcional, fondo transparente = blanco).
Raster rasterize(Uint8List rgba, int srcW, int srcH, int targetW, {int threshold = 128}) {
  final w = (targetW ~/ 8) * 8;
  if (w <= 0 || srcW <= 0 || srcH <= 0) return Raster(8, 1, Uint8List(1));
  final h = (srcH * w / srcW).round().clamp(1, 2000);
  // Escalado por promedio de área (se ve mejor que el vecino más cercano) a escala de grises.
  final gray = Float64List(w * h);
  final sx = srcW / w;
  final sy = srcH / h;
  for (var y = 0; y < h; y++) {
    final y0 = (y * sy).floor();
    final y1 = ((y + 1) * sy).ceil().clamp(y0 + 1, srcH);
    for (var x = 0; x < w; x++) {
      final x0 = (x * sx).floor();
      final x1 = ((x + 1) * sx).ceil().clamp(x0 + 1, srcW);
      var sum = 0.0;
      var n = 0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          final i = (yy * srcW + xx) * 4;
          final a = rgba[i + 3] / 255.0;
          final lum = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
          sum += lum * a + 255 * (1 - a); // transparente = blanco
          n++;
        }
      }
      gray[y * w + x] = n == 0 ? 255 : sum / n;
    }
  }
  // Floyd–Steinberg
  final out = Uint8List((w ~/ 8) * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final old = gray[i];
      final black = old < threshold;
      final err = old - (black ? 0 : 255);
      if (black) out[y * (w ~/ 8) + (x >> 3)] |= 0x80 >> (x & 7);
      if (x + 1 < w) gray[i + 1] += err * 7 / 16;
      if (y + 1 < h) {
        if (x > 0) gray[i + w - 1] += err * 3 / 16;
        gray[i + w] += err * 5 / 16;
        if (x + 1 < w) gray[i + w + 1] += err * 1 / 16;
      }
    }
  }
  return Raster(w, h, out);
}

/// Matriz booleana (por ejemplo, un QR calculado en el teléfono) → raster con módulos de [scale] puntos.
Raster matrixToRaster(List<List<bool>> m, {int scale = 6, int quiet = 2}) {
  final n = m.length + quiet * 2;
  final px = n * scale;
  final w = ((px + 7) ~/ 8) * 8;
  final data = Uint8List((w ~/ 8) * px);
  for (var y = 0; y < m.length; y++) {
    for (var x = 0; x < m[y].length; x++) {
      if (!m[y][x]) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          final X = (x + quiet) * scale + dx;
          final Y = (y + quiet) * scale + dy;
          data[Y * (w ~/ 8) + (X >> 3)] |= 0x80 >> (X & 7);
        }
      }
    }
  }
  return Raster(w, px, data);
}

const _cp1252Extra = {'€': 0x80, '‚': 0x82, '„': 0x84, '…': 0x85, '‘': 0x91, '’': 0x92, '“': 0x93, '”': 0x94, '–': 0x96, '—': 0x97};

/// Texto → bytes en la página 1252 (las tildes y la ñ van; lo demás se translitera o se cambia por '?').
Uint8List encode1252(String s) {
  final b = BytesBuilder();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (r < 0x80 || (r >= 0xA0 && r <= 0xFF)) {
      b.addByte(r);
    } else if (_cp1252Extra.containsKey(ch)) {
      b.addByte(_cp1252Extra[ch]!);
    } else {
      b.addByte(0x3F);
    }
  }
  return b.toBytes();
}

class EscPos {
  EscPos(this.paper);
  final Paper paper;
  final BytesBuilder _b = BytesBuilder();

  Uint8List bytes() => _b.toBytes();

  void raw(List<int> v) => _b.add(v);
  void init() => raw([0x1B, 0x40, 0x1B, 0x74, 16]); // reiniciar + página de códigos WPC1252
  void align(int a) => raw([0x1B, 0x61, a]); // 0 izq, 1 centro, 2 der
  void bold(bool on) => raw([0x1B, 0x45, on ? 1 : 0]);
  void size(int w, int h) => raw([0x1D, 0x21, ((w - 1) << 4) | (h - 1)]);
  void feed([int n = 1]) => raw([0x1B, 0x64, n]);
  void cut() => raw([0x1D, 0x56, 66, 3]); // corte parcial dejando 3 líneas
  void openDrawer() => raw([0x1B, 0x70, 0, 25, 250]);

  void text(String s, {bool b = false, int a = 0, bool big = false}) {
    align(a);
    if (b) bold(true);
    if (big) size(2, 2);
    _b.add(encode1252(s));
    raw([0x0A]);
    if (big) size(1, 1);
    if (b) bold(false);
  }

  /// Texto largo partido en líneas del ancho del papel (por palabras).
  void wrap(String s, {int a = 0, bool b = false}) {
    for (final l in wrapLines(s, paper.chars)) {
      text(l, a: a, b: b);
    }
  }

  void line([String c = '-']) => text(c * paper.chars);

  /// "Izquierda ......... derecha" en una línea (la izquierda se recorta si no entra).
  void pair(String left, String right, {bool b = false}) => text(twoCols(left, right, paper.chars), b: b);

  void image(Raster r, {int a = 1}) {
    align(a);
    final wb = r.width ~/ 8;
    // Por bloques de 255 filas (algunas impresoras no aceptan imágenes más altas en un solo comando).
    for (var y0 = 0; y0 < r.height; y0 += 255) {
      final h = (r.height - y0) > 255 ? 255 : r.height - y0;
      raw([0x1D, 0x76, 0x30, 0, wb & 0xFF, (wb >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF]);
      _b.add(Uint8List.sublistView(r.data, y0 * wb, (y0 + h) * wb));
    }
    align(0);
  }

  /// QR nativo de la impresora (modelo 2, corrección Q como pide SUNAT, módulo de [module] puntos).
  void qr(String data, {int module = 6}) {
    final d = utf8.encode(data);
    final len = d.length + 3;
    align(1);
    raw([0x1D, 0x28, 0x6B, 4, 0, 0x31, 0x41, 0x32, 0x00]); // modelo 2
    raw([0x1D, 0x28, 0x6B, 3, 0, 0x31, 0x43, module.clamp(1, 16)]); // tamaño
    raw([0x1D, 0x28, 0x6B, 3, 0, 0x31, 0x45, 0x33]); // corrección Q (0x33)
    raw([0x1D, 0x28, 0x6B, len & 0xFF, (len >> 8) & 0xFF, 0x31, 0x50, 0x30]);
    _b.add(d);
    raw([0x1D, 0x28, 0x6B, 3, 0, 0x31, 0x51, 0x30]); // imprimir
    raw([0x0A]);
    align(0);
  }
}

List<String> wrapLines(String s, int width) {
  final out = <String>[];
  for (final para in s.split('\n')) {
    var cur = '';
    for (final w in para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      var word = w;
      while (word.length > width) {
        if (cur.isNotEmpty) {
          out.add(cur);
          cur = '';
        }
        out.add(word.substring(0, width));
        word = word.substring(width);
      }
      if (cur.isEmpty) {
        cur = word;
      } else if (cur.length + 1 + word.length <= width) {
        cur = '$cur $word';
      } else {
        out.add(cur);
        cur = word;
      }
    }
    out.add(cur);
  }
  return out;
}

String twoCols(String left, String right, int width) {
  final r = right.length > width ? right.substring(0, width) : right;
  final room = width - r.length - 1;
  final l = room <= 0 ? '' : (left.length > room ? left.substring(0, room) : left);
  return l + ' ' * (width - l.length - r.length) + r;
}
