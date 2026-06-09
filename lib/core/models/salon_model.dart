class SalonModel {
  final String salonId;
  final String nombre;
  final String descripcion;
  final bool activo;

  const SalonModel({
    required this.salonId,
    required this.nombre,
    required this.descripcion,
    required this.activo,
  });

  factory SalonModel.fromJson(Map<String, dynamic> j) => SalonModel(
    salonId:     j['salonId']?.toString() ?? '',
    nombre:      j['nombre']?.toString() ?? '',
    descripcion: j['descripcion']?.toString() ?? '',
    activo:      j['activo'] ?? true,
  );
}
