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
    // Todo en enteros: con doubles, 0,2625 puede quedar en 0,26249999 y
    // redondear para el lado equivocado. El precio puede tener 6 decimales
    // (precio de menú con IVA ÷ 1.15), así que la base va en millonésimas de
    // dólar; la tarifa, en centésimas de punto (15% = 1500).
    final basePorTarifa = <int, int>{};
    int ivaCentavos = 0;
    for (final d in detalles) {
      final cantidad = cantidadDe(d);
      if (cantidad <= 0) continue;
      // Cortesía: se descuenta completa en el backend, no suma base ni IVA.
      if (d.cortesia) continue;
      final tarifa = d.ivaPorcentaje ?? ivaPredeterminado;
      final clave = (tarifa * 100).round();
      final baseMicro = (d.precioUnitario * 1000000).round() * cantidad;
      // La base de la línea se redondea a centavos; el IVA se calcula sobre
      // la base SIN redondear (mitad hacia arriba), línea por línea. Es lo
      // que hacen el backend y Factuplan, y lo que hace cuadrar precio ×
      // cantidad con el menú. Con precios de 2 decimales da lo mismo de siempre.
      final baseCentavos = (baseMicro + 5000) ~/ 10000;
      basePorTarifa[clave] = (basePorTarifa[clave] ?? 0) + baseCentavos;
      if (clave > 0) ivaCentavos += (baseMicro * clave + 50000000) ~/ 100000000;
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
