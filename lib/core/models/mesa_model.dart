class MesaModel {
  final String mesaId;
  final String salonId;
  final String nombreSalon;
  final String numeroMesa;
  final int capacidad;
  final String estado;
  final bool activo;
  final String? tokenSesion;

  const MesaModel({
    required this.mesaId,
    required this.salonId,
    required this.nombreSalon,
    required this.numeroMesa,
    required this.capacidad,
    required this.estado,
    required this.activo,
    this.tokenSesion,
  });

  factory MesaModel.fromJson(Map<String, dynamic> j) => MesaModel(
    mesaId:      j['mesaId']?.toString() ?? '',
    salonId:     j['salonId']?.toString() ?? '',
    nombreSalon: j['nombreSalon']?.toString() ?? '',
    numeroMesa:  j['numeroMesa']?.toString() ?? '',
    capacidad:   (j['capacidad'] ?? 4) as int,
    estado:      j['estado']?.toString() ?? 'LIBRE',
    activo:      j['activo'] ?? true,
    tokenSesion: j['tokenSesion']?.toString(),
  );

  bool get isLibre       => estado == 'LIBRE';
  bool get isOcupada     => estado == 'OCUPADA';
  bool get isReservada   => estado == 'RESERVADA';
  bool get isMantenimiento => estado == 'MANTENIMIENTO';
}
