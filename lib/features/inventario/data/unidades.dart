/// Unidades de los insumos.
///
/// El backend solo conoce tres unidades base (GRAMO, MILILITRO, UNIDAD) para
/// que recetas, compras y stock nunca mezclen medidas. Lo que la gente escribe
/// ("2 kg", "5 lb", "1,5 L") se convierte aquí antes de enviarlo.
class UnidadCompra {
  final String etiqueta;
  final double factor; // cuántas unidades base hay en una de estas
  const UnidadCompra(this.etiqueta, this.factor);
}

class Unidades {
  static const base = ['GRAMO', 'MILILITRO', 'UNIDAD'];

  static String nombre(String unidadBase) {
    switch (unidadBase) {
      case 'GRAMO':     return 'Gramos';
      case 'MILILITRO': return 'Mililitros';
      default:          return 'Unidades';
    }
  }

  static String corta(String unidadBase) {
    switch (unidadBase) {
      case 'GRAMO':     return 'g';
      case 'MILILITRO': return 'ml';
      default:          return 'u';
    }
  }

  /// Unidades en que se puede escribir una cantidad de este insumo. La
  /// primera es la base (factor 1).
  static List<UnidadCompra> opciones(String unidadBase) {
    switch (unidadBase) {
      case 'GRAMO':
        return const [
          UnidadCompra('g', 1),
          UnidadCompra('kg', 1000),
          UnidadCompra('lb', 453.592),
        ];
      case 'MILILITRO':
        return const [
          UnidadCompra('ml', 1),
          UnidadCompra('L', 1000),
        ];
      default:
        return const [UnidadCompra('u', 1)];
    }
  }

  /// Cantidad legible: 22680 g se muestra como "22,68 kg"; 1500 ml como "1,5 L".
  static String formato(double? cantidad, String unidadBase) {
    if (cantidad == null) return '—';
    final abs = cantidad.abs();
    if (unidadBase == 'GRAMO' && abs >= 1000) {
      return '${numero(cantidad / 1000)} kg';
    }
    if (unidadBase == 'MILILITRO' && abs >= 1000) {
      return '${numero(cantidad / 1000)} L';
    }
    return '${numero(cantidad)} ${corta(unidadBase)}';
  }

  /// Sin ceros de más: 23 → "23", 1.5 → "1,5", 0.125 → "0,125".
  static String numero(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s.replaceAll('.', ',');
  }

  /// Costo por la unidad que la gente entiende: por kg, por litro o por unidad.
  static String costo(double? costoBase, String unidadBase) {
    if (costoBase == null) return 'sin costo';
    switch (unidadBase) {
      case 'GRAMO':     return '\$${(costoBase * 1000).toStringAsFixed(2)} / kg';
      case 'MILILITRO': return '\$${(costoBase * 1000).toStringAsFixed(2)} / L';
      default:          return '\$${costoBase.toStringAsFixed(2)} / u';
    }
  }

  static double? leer(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.'));
}
