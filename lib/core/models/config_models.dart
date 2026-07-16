class TasaIvaModel {
  final String tasaIvaId;
  final String tenantId;
  final String nombre;
  final double porcentaje;
  final String vigentDesde;
  final String? vigentHasta;
  final bool activo;

  const TasaIvaModel({
    required this.tasaIvaId,
    required this.tenantId,
    required this.nombre,
    required this.porcentaje,
    required this.vigentDesde,
    this.vigentHasta,
    required this.activo,
  });

  factory TasaIvaModel.fromJson(Map<String, dynamic> j) => TasaIvaModel(
    tasaIvaId:   j['tasaIvaId']?.toString() ?? '',
    tenantId:    j['tenantId']?.toString() ?? '',
    nombre:      j['nombre']?.toString() ?? '',
    porcentaje:  _toDouble(j['porcentaje']),
    vigentDesde: j['vigentDesde']?.toString() ?? '',
    vigentHasta: j['vigentHasta']?.toString(),
    activo:      j['activo'] ?? true,
  );

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

class CategoriaModel {
  final String categoriaId;
  final String restaurantId;
  final String nombre;
  final String? descripcion;
  final bool activo;

  const CategoriaModel({
    required this.categoriaId,
    required this.restaurantId,
    required this.nombre,
    this.descripcion,
    required this.activo,
  });

  factory CategoriaModel.fromJson(Map<String, dynamic> j) => CategoriaModel(
    categoriaId:  j['categoriaId']?.toString() ?? '',
    restaurantId: j['restaurantId']?.toString() ?? '',
    nombre:       j['nombre']?.toString() ?? '',
    descripcion:  j['descripcion']?.toString(),
    activo:       j['activo'] ?? true,
  );
}

class SubcategoriaModel {
  final String subcategoriaId;
  final String categoriaId;
  final String nombre;
  final bool activo;

  const SubcategoriaModel({
    required this.subcategoriaId,
    required this.categoriaId,
    required this.nombre,
    required this.activo,
  });

  factory SubcategoriaModel.fromJson(Map<String, dynamic> j) => SubcategoriaModel(
    subcategoriaId: j['subcategoriaId']?.toString() ?? '',
    categoriaId:    j['categoriaId']?.toString() ?? '',
    nombre:         j['nombre']?.toString() ?? '',
    activo:         j['activo'] ?? true,
  );
}

class RolModel {
  final String rolId;
  final String nombre;
  final String? descripcion;

  const RolModel({required this.rolId, required this.nombre, this.descripcion});

  factory RolModel.fromJson(Map<String, dynamic> j) => RolModel(
    rolId:       j['rolId']?.toString() ?? '',
    nombre:      j['nombre']?.toString() ?? '',
    descripcion: j['descripcion']?.toString(),
  );
}

class UsuarioListModel {
  final String usuarioId;
  final String nombre;
  final String usuario;
  final String nombreRol;
  final String rolId;
  final bool activo;

  const UsuarioListModel({
    required this.usuarioId,
    required this.nombre,
    required this.usuario,
    required this.nombreRol,
    required this.rolId,
    required this.activo,
  });

  factory UsuarioListModel.fromJson(Map<String, dynamic> j) => UsuarioListModel(
    usuarioId: j['usuarioId']?.toString() ?? '',
    nombre:    j['nombre']?.toString() ?? '',
    usuario:   j['usuario']?.toString() ?? '',
    nombreRol: j['nombreRol']?.toString() ?? '',
    rolId:     j['rolId']?.toString() ?? '',
    activo:    j['activo'] ?? true,
  );
}

class CajaConfigModel {
  final String cajaId;
  final String nombre;
  final String? descripcion;
  final String codigoPuntoEmision;
  final bool activo;

  const CajaConfigModel({
    required this.cajaId,
    required this.nombre,
    this.descripcion,
    required this.codigoPuntoEmision,
    required this.activo,
  });

  factory CajaConfigModel.fromJson(Map<String, dynamic> j) => CajaConfigModel(
    cajaId:              j['cajaId']?.toString() ?? '',
    nombre:              j['nombre']?.toString() ?? '',
    descripcion:         j['descripcion']?.toString(),
    codigoPuntoEmision:  j['codigoPuntoEmision']?.toString() ?? '',
    activo:              j['activo'] ?? true,
  );
}

class TenantModel {
  final String tenantId;
  final String nombre;
  final String ruc;
  final String email;
  final String? plan;
  final bool activo;

  const TenantModel({
    required this.tenantId,
    required this.nombre,
    required this.ruc,
    required this.email,
    this.plan,
    required this.activo,
  });

  factory TenantModel.fromJson(Map<String, dynamic> j) => TenantModel(
    tenantId: j['tenantId']?.toString() ?? '',
    nombre:   j['nombre']?.toString() ?? '',
    ruc:      j['ruc']?.toString() ?? '',
    email:    j['email']?.toString() ?? '',
    plan:     j['plan']?.toString(),
    activo:   j['activo'] ?? true,
  );
}

class RestaurantModel {
  final String restaurantId;
  final String tenantId;
  final String nombre;
  final bool activo;

  const RestaurantModel({
    required this.restaurantId,
    required this.tenantId,
    required this.nombre,
    required this.activo,
  });

  factory RestaurantModel.fromJson(Map<String, dynamic> j) => RestaurantModel(
    restaurantId: j['restaurantId']?.toString() ?? '',
    tenantId:     j['tenantId']?.toString() ?? '',
    nombre:       j['nombre']?.toString() ?? '',
    activo:       j['activo'] ?? true,
  );
}

class SucursalModel {
  final String sucursalId;
  final String restaurantId;
  final String nombre;
  final String direccion;
  final bool activo;

  const SucursalModel({
    required this.sucursalId,
    required this.restaurantId,
    required this.nombre,
    required this.direccion,
    required this.activo,
  });

  factory SucursalModel.fromJson(Map<String, dynamic> j) => SucursalModel(
    sucursalId:   j['sucursalId']?.toString() ?? '',
    restaurantId: j['restaurantId']?.toString() ?? '',
    nombre:       j['nombre']?.toString() ?? '',
    direccion:    j['direccion']?.toString() ?? '',
    activo:       j['activo'] ?? true,
  );
}

class PlatoMasterModel {
  final String platoId;
  final String subcategoriaId;
  final String nombre;
  final String? descripcion;
  final bool activo;

  const PlatoMasterModel({
    required this.platoId,
    required this.subcategoriaId,
    required this.nombre,
    this.descripcion,
    required this.activo,
  });

  factory PlatoMasterModel.fromJson(Map<String, dynamic> j) => PlatoMasterModel(
    platoId:        j['platoId']?.toString() ?? '',
    subcategoriaId: j['subcategoriaId']?.toString() ?? '',
    nombre:         j['nombre']?.toString() ?? '',
    descripcion:    j['descripcion']?.toString(),
    activo:         j['activo'] ?? true,
  );
}

class SetupStatus {
  final bool tieneTasaIva;
  final bool tieneSalones;
  final bool tieneMesas;
  final bool tienePlatos;
  final bool tieneCaja;
  final bool tieneUsuarios;

  const SetupStatus({
    required this.tieneTasaIva,
    required this.tieneSalones,
    required this.tieneMesas,
    required this.tienePlatos,
    required this.tieneCaja,
    required this.tieneUsuarios,
  });

  bool get isComplete =>
      tieneTasaIva && tieneSalones && tieneMesas && tienePlatos && tieneCaja && tieneUsuarios;

  int get completedCount => [
    tieneTasaIva, tieneSalones, tieneMesas, tienePlatos, tieneCaja, tieneUsuarios
  ].where((v) => v).length;
}

class ImpresoraModel {
  final String impresoraId;
  final String sucursalId;
  final String nombre;
  final String? area;
  final String? ip;
  final int? puerto;
  final String? mac;
  final bool activo;
  final List<String> categorias;
  final List<String> categoriaIds;

  const ImpresoraModel({
    required this.impresoraId,
    required this.sucursalId,
    required this.nombre,
    this.area,
    this.ip,
    this.puerto,
    this.mac,
    required this.activo,
    required this.categorias,
    required this.categoriaIds,
  });

  /// Tiene al menos una vía de conexión configurada (red o Bluetooth).
  bool get imprimible => (ip?.isNotEmpty ?? false) || (mac?.isNotEmpty ?? false);

  factory ImpresoraModel.fromJson(Map<String, dynamic> j) => ImpresoraModel(
    impresoraId: j['impresoraId']?.toString() ?? '',
    sucursalId:  j['sucursalId']?.toString() ?? '',
    nombre:      j['nombre']?.toString() ?? '',
    area:        j['area']?.toString(),
    ip:          j['ip']?.toString(),
    puerto:      (j['puerto'] as num?)?.toInt(),
    mac:         j['mac']?.toString(),
    activo:      j['activo'] ?? true,
    categorias:  ((j['categorias'] as List?) ?? []).map((e) => e.toString()).toList(),
    categoriaIds: ((j['categoriaIds'] as List?) ?? []).map((e) => e.toString()).toList(),
  );
}
