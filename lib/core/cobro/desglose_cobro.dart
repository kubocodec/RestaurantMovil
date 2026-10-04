import '../models/orden_model.dart';

/// Subtotal, IVA y total de lo que se cobra. Lo usan el cobro y la precuenta:
/// los dos tienen que dar exactamente la misma cifra, así que el cálculo vive
/// en un solo lugar. Replica el del backend (FacturaService), que es el que
/// manda: el cobro registra el total que devuelve el servidor.
class DesgloseCobro {
  final double subtotal;
  final double iva;
  /// Base por tarifa de IVA (15.0 → base gravada, 0.0 → base 0%).
  final Map<double, double> basePorTarifa;

  const DesgloseCobro(this.subtotal, this.iva, this.basePorTarifa);

  static const vacio = DesgloseCobro(0, 0, {});

  double get total => subtotal + iva;

  /// [cantidadDe] dice cuántas unidades de cada línea entran (en el cobro,
  /// lo elegido en una cuenta dividida; en la precuenta, todo lo pendiente).
  /// [ivaPredeterminado] es la tarifa de las líneas sin tarifa propia.
  static DesgloseCobro calcular(
    Iterable<DetalleOrdenModel> detalles,
    int Function(DetalleOrdenModel) cantidadDe,
    double ivaPredeterminado,
  ) {
    // Todo en centavos enteros: con doubles, 0,2625 puede quedar en
    // 0,26249999 y redondear para el lado equivocado. La tarifa va en
    // centésimas de punto (15% = 1500).
    final basePorTarifa = <int, int>{};
    int ivaCentavos = 0;
    for (final d in detalles) {
      final cantidad = cantidadDe(d);
      if (cantidad <= 0) continue;
      // Cortesía: se descuenta completa en el backend, no suma base ni IVA.
      if (d.cortesia) continue;
      final tarifa = d.ivaPorcentaje ?? ivaPredeterminado;
      final clave = (tarifa * 100).round();
      final baseCentavos = (d.precioUnitario * 100).round() * cantidad;
      basePorTarifa[clave] = (basePorTarifa[clave] ?? 0) + baseCentavos;
      // IVA redondeado por línea (mitad hacia arriba), igual que el backend y
      // que Factuplan: agrupado por tarifa daba a veces un centavo más.
      if (clave > 0) ivaCentavos += (baseCentavos * clave + 5000) ~/ 10000;
    }

    double subtotal = 0;
    final bases = <double, double>{};
    basePorTarifa.forEach((clave, base) {
      subtotal += base / 100;
      bases[clave / 100] = base / 100;
    });
    return DesgloseCobro(subtotal, ivaCentavos / 100, bases);
  }
}
