// Productos de EJEMPLO por rubro para que el punto de venta no empiece vacío.
// Los precios son referenciales y se pueden editar o borrar: el dueño los ajusta a su negocio. No se cargan solos:
// el usuario toca "Cargar productos de ejemplo". Sin fotos: cada producto muestra un emoji hasta que el dueño suba la suya.

class SampleItem {
  const SampleItem(this.name, this.price, this.category, this.emoji);
  final String name;
  final double price; // precio de venta referencial CON IGV (al cargarlo se guarda sin IGV)
  final String category;
  final String emoji;
}

const sampleCatalog = <String, List<SampleItem>>{
  'bodega': [
    SampleItem('Gaseosa 500 ml', 3.0, 'Bebidas', '🥤'),
    SampleItem('Agua mineral 625 ml', 1.8, 'Bebidas', '💧'),
    SampleItem('Arroz extra 1 kg', 4.5, 'Abarrotes', '🍚'),
    SampleItem('Aceite vegetal 1 L', 9.5, 'Abarrotes', '🫒'),
    SampleItem('Azúcar rubia 1 kg', 4.2, 'Abarrotes', '🧂'),
    SampleItem('Leche evaporada', 4.0, 'Lácteos', '🥛'),
    SampleItem('Pan francés (unidad)', 0.3, 'Panadería', '🥖'),
    SampleItem('Huevos (unidad)', 0.6, 'Abarrotes', '🥚'),
    SampleItem('Detergente 500 g', 7.0, 'Limpieza', '🧼'),
    SampleItem('Galletas', 1.5, 'Snacks', '🍪'),
  ],
  'restaurante': [
    SampleItem('Menú del día', 12.0, 'Menú', '🍽️'),
    SampleItem('Pollo a la brasa (1/4)', 18.0, 'Platos', '🍗'),
    SampleItem('Lomo saltado', 24.0, 'Platos', '🥩'),
    SampleItem('Ceviche', 28.0, 'Platos', '🐟'),
    SampleItem('Arroz con pollo', 16.0, 'Platos', '🍛'),
    SampleItem('Causa rellena', 14.0, 'Entradas', '🥔'),
    SampleItem('Chicha morada (jarra)', 12.0, 'Bebidas', '🍹'),
    SampleItem('Gaseosa personal', 4.0, 'Bebidas', '🥤'),
    SampleItem('Postre del día', 8.0, 'Postres', '🍮'),
    SampleItem('Café', 5.0, 'Bebidas', '☕'),
  ],
  'servicios_tecnicos': [
    SampleItem('Visita técnica', 40.0, 'Servicios', '🛠️'),
    SampleItem('Instalación de internet', 80.0, 'Servicios', '📡'),
    SampleItem('Cambio de router', 60.0, 'Servicios', '📶'),
    SampleItem('Cable de red (metro)', 2.0, 'Materiales', '🔌'),
    SampleItem('Conector RJ45', 1.5, 'Materiales', '🔗'),
    SampleItem('Mantenimiento de equipo', 50.0, 'Servicios', '🖥️'),
  ],
  'salon': [
    SampleItem('Corte de cabello', 25.0, 'Cabello', '✂️'),
    SampleItem('Tinte', 90.0, 'Cabello', '🎨'),
    SampleItem('Manicure', 30.0, 'Uñas', '💅'),
    SampleItem('Pedicure', 40.0, 'Uñas', '🦶'),
    SampleItem('Peinado', 45.0, 'Cabello', '💇'),
    SampleItem('Limpieza facial', 70.0, 'Cuidado', '🧖'),
    SampleItem('Shampoo (venta)', 28.0, 'Productos', '🧴'),
  ],
  'consultorio': [
    SampleItem('Consulta general', 60.0, 'Consultas', '🩺'),
    SampleItem('Control', 40.0, 'Consultas', '📋'),
    SampleItem('Procedimiento menor', 90.0, 'Procedimientos', '🩹'),
    SampleItem('Certificado', 30.0, 'Trámites', '📄'),
  ],
  'taller': [
    SampleItem('Cambio de aceite', 80.0, 'Servicios', '🛢️'),
    SampleItem('Revisión de frenos', 60.0, 'Servicios', '🛑'),
    SampleItem('Alineamiento y balanceo', 90.0, 'Servicios', '🚗'),
    SampleItem('Filtro de aceite', 25.0, 'Repuestos', '⚙️'),
    SampleItem('Batería', 280.0, 'Repuestos', '🔋'),
    SampleItem('Llanta', 250.0, 'Repuestos', '🛞'),
    SampleItem('Mano de obra (hora)', 40.0, 'Servicios', '🔧'),
  ],
  'mayorista': [
    SampleItem('Arroz saco 50 kg', 190.0, 'Abarrotes', '🌾'),
    SampleItem('Azúcar saco 50 kg', 185.0, 'Abarrotes', '🧂'),
    SampleItem('Aceite caja x12', 105.0, 'Abarrotes', '🫒'),
    SampleItem('Gaseosa caja x12', 28.0, 'Bebidas', '🥤'),
    SampleItem('Fideos caja x20', 60.0, 'Abarrotes', '🍝'),
    SampleItem('Detergente caja x12', 75.0, 'Limpieza', '🧼'),
  ],
  'educacion': [
    SampleItem('Matrícula', 150.0, 'Matrícula', '🎓'),
    SampleItem('Pensión mensual', 250.0, 'Pensiones', '📚'),
    SampleItem('Material educativo', 45.0, 'Materiales', '✏️'),
    SampleItem('Taller de reforzamiento', 80.0, 'Talleres', '🧠'),
    SampleItem('Uniforme', 70.0, 'Otros', '👕'),
  ],
  'construccion': [
    SampleItem('Cemento (bolsa)', 30.0, 'Materiales', '🧱'),
    SampleItem('Fierro 3/8 (varilla)', 38.0, 'Materiales', '🏗️'),
    SampleItem('Ladrillo (millar)', 700.0, 'Materiales', '🧱'),
    SampleItem('Arena (m³)', 60.0, 'Materiales', '⛰️'),
    SampleItem('Mano de obra (día)', 80.0, 'Servicios', '👷'),
    SampleItem('Alquiler de herramienta (día)', 50.0, 'Servicios', '🔨'),
  ],
};

/// Emoji de un producto para mostrar cuando no tiene foto: primero el de ejemplo, luego por palabras del nombre o categoría.
String? tileEmoji(String name, [String? category]) {
  final n = name.toLowerCase();
  for (final l in sampleCatalog.values) {
    for (final s in l) {
      if (s.name.toLowerCase() == n) return s.emoji;
    }
  }
  final t = '$n ${(category ?? '').toLowerCase()}';
  const keys = <String, String>{
    'gaseosa': '🥤', 'agua': '💧', 'cerveza': '🍺', 'jugo': '🧃', 'café': '☕', 'cafe': '☕', 'té ': '🍵',
    'pollo': '🍗', 'carne': '🥩', 'pescado': '🐟', 'ceviche': '🐟', 'arroz': '🍚', 'fideo': '🍝', 'pan': '🥖',
    'postre': '🍮', 'helado': '🍨', 'leche': '🥛', 'queso': '🧀', 'huevo': '🥚', 'fruta': '🍎', 'verdura': '🥬',
    'limpieza': '🧼', 'detergente': '🧼', 'aceite': '🛢️', 'llanta': '🛞', 'batería': '🔋', 'bateria': '🔋',
    'repuesto': '⚙️', 'cable': '🔌', 'corte': '✂️', 'uña': '💅', 'consulta': '🩺', 'cemento': '🧱', 'ladrillo': '🧱',
  };
  for (final e in keys.entries) {
    if (t.contains(e.key)) return e.value;
  }
  return null;
}
