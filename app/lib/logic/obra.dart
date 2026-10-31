// Construcción: semáforo de gasto por obra. Compara cuánto del contrato ya gastaste con cuánto ya facturaste.
// Es una señal para revisar, no un cálculo contable: los gastos y los hitos pueden estar con o sin IGV.

enum ObraAlert { none, faster, over }

class ObraSignal {
  const ObraSignal(this.alert, this.spentShare, this.invoicedShare);
  final ObraAlert alert;
  final double spentShare; // gastado / contratado (0–n)
  final double invoicedShare; // facturado / contratado (0–1+)
}

/// [agreed] = suma de hitos; [invoiced] = hitos facturados; [spent] = gastos asignados.
/// - `over`: ya gastaste el contrato completo o más.
/// - `faster`: gastas (en % del contrato) más de 15 puntos por encima de lo que llevas facturado.
/// Sin contrato (agreed <= 0) no hay señal.
ObraSignal obraSignal({required double agreed, required double invoiced, required double spent}) {
  if (agreed <= 0) return const ObraSignal(ObraAlert.none, 0, 0);
  final s = spent / agreed;
  final i = invoiced / agreed;
  if (spent >= agreed - 0.004) return ObraSignal(ObraAlert.over, s, i);
  if (s - i > 0.15) return ObraSignal(ObraAlert.faster, s, i);
  return ObraSignal(ObraAlert.none, s, i);
}
