class PlatoModel {
  final String sucursalPlatoId;
  final String platoId;
  final String nombrePlato;
  final String? descripcionPlato;
  final String? imagenPlato;
  final String categoria;
  final String subcategoria;
  final double precio;
  final bool disponible;

  // --- Inventario (solo llega con contenido si el restaurante lo tiene
  // activado y el plato está marcado para controlar stock) ---
  /// 'SIN_CONTROL' o 'UNIDADES'.
  final String modoInventario;
  final double? stock;
  final double? stockMinimo;
  final String? unidad;
  /// Se controla el stock y ya no quedan unidades.
  final bool agotado;
  /// Quedan unidades pero está en el mínimo o por debajo.
  final bool bajoMinimo;

  const PlatoModel({
    required this.sucursalPlatoId,
    required this.platoId,
    required this.nombrePlato,
    this.descripcionPlato,
    this.imagenPlato,
    this.categoria = '',
    this.subcategoria = '',
    required this.precio,
    required this.disponible,
    this.modoInventario = 'SIN_CONTROL',
    this.stock,
    this.stockMinimo,
    this.unidad,
    this.agotado = false,
    this.bajoMinimo = false,
  });

  /// El plato lleva control de stock en esta sucursal.
  bool get controlaStock => modoInventario == 'UNIDADES';

  /// Unidades disponibles como entero, para mostrar y para topar el carrito.
  int get unidadesDisponibles => (stock ?? 0) <= 0 ? 0 : (stock ?? 0).floor();

  factory PlatoModel.fromJson(Map<String, dynamic> j) => PlatoModel(
    sucursalPlatoId: j['sucursalPlatoId']?.toString() ?? '',
    platoId:         j['platoId']?.toString() ?? '',
    nombrePlato:     j['nombrePlato']?.toString() ?? '',
    descripcionPlato: j['descripcionPlato']?.toString(),
    imagenPlato:     j['imagenPlato']?.toString(),
    categoria:       j['categoria']?.toString() ?? '',
    subcategoria:    j['subcategoria']?.toString() ?? '',
    precio:          _toDouble(j['precio']),
    disponible:      j['disponible'] ?? true,
    modoInventario:  j['modoInventario']?.toString() ?? 'SIN_CONTROL',
    stock:           j['stock'] == null ? null : _toDouble(j['stock']),
    stockMinimo:     j['stockMinimo'] == null ? null : _toDouble(j['stockMinimo']),
    unidad:          j['unidad']?.toString(),
    agotado:         j['agotado'] ?? false,
    bajoMinimo:      j['bajoMinimo'] ?? false,
  );

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
