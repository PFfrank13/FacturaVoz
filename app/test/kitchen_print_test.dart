import 'package:facturavoz/services/print/kitchen_print.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cada rubro con órdenes o citas tiene su propio documento', () {
    expect(jobDocSpec('taller').title, 'ORDEN DE TRABAJO');
    expect(jobDocSpec('servicios_tecnicos').title, 'ORDEN DE SERVICIO');
    expect(jobDocSpec('construccion').title, 'ORDEN DE OBRA');
    expect(jobDocSpec('salon').title, 'CITA');
    expect(jobDocSpec('consultorio').title, 'CITA');
    expect(jobDocSpec('educacion').title, 'HORARIO / CLASE');
    expect(jobDocSpec('bodega').title, 'ORDEN'); // sin documento propio: no muestra el botón
    expect(jobDocSpec('taller').signature, isTrue);
    expect(jobDocSpec('salon').signature, isFalse);
  });

  test('DocData omite los campos vacíos', () {
    const d = DocData(title: 'CITA', number: 'N° 1', date: 'hoy', issuer: 'Sol', rows: [('Cliente', 'Ana'), ('Notas', ' '), ('Dirección', '')]);
    expect(d.shown.length, 1);
    expect(d.shown.first.$1, 'Cliente');
  });

  test('Comanda: para llevar si no hay mesa', () {
    const a = ComandaData(table: '', waiter: '', date: 'x', lines: []);
    const b = ComandaData(table: ' 4 ', waiter: '', date: 'x', lines: []);
    expect(a.where, 'PARA LLEVAR');
    expect(b.where, 'MESA: 4');
  });
}
