/// Unidades de los insumos.
///
/// El backend solo conoce tres unidades base (GRAMO, MILILITRO, UNIDAD) para
/// que recetas, compras y stock nunca mezclen medidas. Lo que la gente escribe
/// ("2 kg", "5 lb", "1,5 L") se convierte aquí antes de enviarlo.
class UnidadCompra {
  final String etiqueta;
  final double factor; // cuántas unidades base hay en una de estas
  const UnidadCompra(this.etiqueta, this.factor);

  // Por valor: la opción de la presentación se crea en cada build y el
  // DropdownButton exige que el valor elegido sea "igual" a uno de la lista.
  @override
  bool operator ==(Object other) =>
      other is UnidadCompra && other.etiqueta == etiqueta && other.factor == factor;

  @override
  int get hashCode => Object.hash(etiqueta, factor);
}

/// Presentación en que se compra y se cuenta un insumo: "Botella" de 750 ml.
///
/// El cliente piensa en botellas, no en litros: "12 botellas" y no "9 L". El
/// stock se sigue guardando en la unidad base; esto solo cambia cómo se
/// muestra y cómo se escribe. Sin presentación, todo se ve como siempre.
class Presentacion {
  final String nombre;    // "Botella"
  final double contenido; // 750 (en la unidad base del insumo)
  const Presentacion(this.nombre, this.contenido);

  /// null si falta el nombre o el contenido (insumo sin presentación).
  static Presentacion? de(String? nombre, double? contenido) {
    final n = nombre?.trim() ?? '';
    if (n.isEmpty || contenido == null || contenido <= 0) return null;
    return Presentacion(n, contenido);
  }

  String get singular => nombre.toLowerCase();

  /// Plural simple en español: botella → botellas, quintal → quintales,
  /// galón → galones, caja → cajas.
  String get plural {
    final s = singular;
    if (s.isEmpty) return s;
    if (RegExp(r'[aeiouáéíóú]$').hasMatch(s)) return '${s}s';
    if (s.endsWith('z')) return '${s.substring(0, s.length - 1)}ces';
    const sinTilde = {'ón': 'on', 'án': 'an', 'én': 'en', 'ín': 'in', 'ún': 'un'};
    for (final e in sinTilde.entries) {
      if (s.endsWith(e.key)) return '${s.substring(0, s.length - 2)}${e.value}es';
    }
    return '${s}es';
  }

  String etiqueta(int n) => n == 1 ? singular : plural;

  /// Parte una cantidad base en presentaciones enteras y lo que sobra:
  /// 8440 ml con botellas de 750 → (11, 190). En milésimas enteras para que
  /// 9000 / 750 no dé 11,9999 botellas.
  (int, double) partir(double cantidadBase) {
    final total = (cantidadBase.abs() * 1000).round();
    final una = (contenido * 1000).round();
    return (total ~/ una, (total % una) / 1000);
  }
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
  ///
  /// Con [p] (presentación del insumo) se agrega primero, para que compras y
  /// conteos arranquen en botellas; sin ella, la lista de siempre.
  static List<UnidadCompra> opciones(String unidadBase, {Presentacion? p}) {
    if (p != null) {
      return [UnidadCompra(p.plural, p.contenido), ...opciones(unidadBase)];
    }
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
  ///
  /// Con [p]: 9000 ml → "12 botellas"; 8440 ml → "11 botellas + 190 ml";
  /// menos de una presentación se muestra en la unidad base ("440 ml").
  static String formato(double? cantidad, String unidadBase, {Presentacion? p}) {
    if (cantidad == null) return '—';
    if (p != null) {
      final (n, resto) = p.partir(cantidad);
      if (n > 0) {
        final texto = '$n ${p.etiqueta(n)}'
            '${resto > 0 ? ' + ${formato(resto, unidadBase)}' : ''}';
        if (cantidad >= 0) return texto;
        return resto > 0 ? '-($texto)' : '-$texto';
      }
    }
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
  static String costo(double? costoBase, String unidadBase, {Presentacion? p}) {
    if (costoBase == null) return 'sin costo';
    if (p != null) return '\$${(costoBase * p.contenido).toStringAsFixed(2)} / ${p.singular}';
    switch (unidadBase) {
      case 'GRAMO':     return '\$${(costoBase * 1000).toStringAsFixed(2)} / kg';
      case 'MILILITRO': return '\$${(costoBase * 1000).toStringAsFixed(2)} / L';
      default:          return '\$${costoBase.toStringAsFixed(2)} / u';
    }
  }

  static double? leer(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.'));
}
