class PlatoModel {
  final String sucursalPlatoId;
  final String platoId;
  final String nombrePlato;
  final String? imagenPlato;
  final double precio;
  final bool disponible;

  const PlatoModel({
    required this.sucursalPlatoId,
    required this.platoId,
    required this.nombrePlato,
    this.imagenPlato,
    required this.precio,
    required this.disponible,
  });

  factory PlatoModel.fromJson(Map<String, dynamic> j) => PlatoModel(
    sucursalPlatoId: j['sucursalPlatoId']?.toString() ?? '',
    platoId:         j['platoId']?.toString() ?? '',
    nombrePlato:     j['nombrePlato']?.toString() ?? '',
    imagenPlato:     j['imagenPlato']?.toString(),
    precio:          _toDouble(j['precio']),
    disponible:      j['disponible'] ?? true,
  );

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
