import '../../../core/models/config_models.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/models/salon_model.dart';
import '../../../core/models/mesa_model.dart';
import '../../../core/models/caja_model.dart';
import '../../../core/network/api_client.dart';

class ConfiguracionRepository {
  final _dio = ApiClient.instance.dio;

  // ── SETUP STATUS ────────────────────────────────────────────────────────────

  Future<SetupStatus> getSetupStatus({
    required String sucursalId,
    required String tenantId,
    required String restaurantId,
  }) async {
    final results = await Future.wait([
      _checkTasaIva(tenantId),
      _checkSalones(sucursalId),
      _checkMesas(sucursalId),
      _checkPlatos(sucursalId),
      _checkCajas(sucursalId),
      _checkUsuarios(sucursalId),
    ]);
    return SetupStatus(
      tieneTasaIva:   results[0],
      tieneSalones:   results[1],
      tieneMesas:     results[2],
      tienePlatos:    results[3],
      tieneCaja:      results[4],
      tieneUsuarios:  results[5],
    );
  }

  Future<bool> _checkTasaIva(String tenantId) async {
    try {
      final r = await _dio.get('/api/tasa-iva/tenant/$tenantId');
      final List data = r.data['data'] ?? [];
      return data.any((t) => t['activo'] == true);
    } catch (_) { return false; }
  }

  Future<bool> _checkSalones(String sucursalId) async {
    try {
      final r = await _dio.get('/api/salones/sucursal/$sucursalId');
      final List data = r.data['data'] ?? [];
      return data.isNotEmpty;
    } catch (_) { return false; }
  }

  Future<bool> _checkMesas(String sucursalId) async {
    try {
      final r = await _dio.get('/api/mesas/sucursal/$sucursalId');
      final List data = r.data['data'] ?? [];
      return data.isNotEmpty;
    } catch (_) { return false; }
  }

  Future<bool> _checkPlatos(String sucursalId) async {
    try {
      final r = await _dio.get('/api/platos/sucursal/$sucursalId');
      final List data = r.data['data'] ?? [];
      return data.isNotEmpty;
    } catch (_) { return false; }
  }

  Future<bool> _checkCajas(String sucursalId) async {
    try {
      final r = await _dio.get('/api/caja/sucursal/$sucursalId');
      final List data = r.data['data'] ?? [];
      return data.isNotEmpty;
    } catch (_) { return false; }
  }

  Future<bool> _checkUsuarios(String sucursalId) async {
    try {
      final r = await _dio.get('/api/usuarios/sucursal/$sucursalId');
      final List data = r.data['data'] ?? [];
      return data.length > 1;
    } catch (_) { return false; }
  }

  // ── TASAS IVA ────────────────────────────────────────────────────────────────

  Future<List<TasaIvaModel>> getTasasIva(String tenantId) async {
    final r = await _dio.get('/api/tasa-iva/tenant/$tenantId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => TasaIvaModel.fromJson(j)).toList();
  }

  Future<TasaIvaModel> crearTasaIva({
    required String tenantId,
    required String nombre,
    required double porcentaje,
    required String vigentDesde,
    String? vigentHasta,
  }) async {
    final r = await _dio.post('/api/tasa-iva', data: {
      'tenantId':    tenantId,
      'nombre':      nombre,
      'porcentaje':  porcentaje,
      'vigentDesde': vigentDesde,
      if (vigentHasta != null) 'vigentHasta': vigentHasta,
    });
    return TasaIvaModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> toggleTasaIva(String tasaIvaId) async {
    await _dio.patch('/api/tasa-iva/$tasaIvaId/toggle');
  }

  // ── SALONES ──────────────────────────────────────────────────────────────────

  Future<List<SalonModel>> getSalones(String sucursalId) async {
    final r = await _dio.get('/api/salones/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => SalonModel.fromJson(j)).toList();
  }

  Future<SalonModel> crearSalon({
    required String sucursalId,
    required String nombre,
    String? descripcion,
  }) async {
    final r = await _dio.post('/api/salones', data: {
      'sucursalId':  sucursalId,
      'nombre':      nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return SalonModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> eliminarSalon(String salonId) async {
    await _dio.delete('/api/salones/$salonId');
  }

  // ── MESAS ────────────────────────────────────────────────────────────────────

  Future<List<MesaModel>> getMesasBySalon(String salonId) async {
    final r = await _dio.get('/api/mesas/salon/$salonId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => MesaModel.fromJson(j)).toList();
  }

  Future<MesaModel> crearMesa({
    required String salonId,
    required String numeroMesa,
    required int capacidad,
  }) async {
    final r = await _dio.post('/api/mesas', data: {
      'salonId':    salonId,
      'numeroMesa': numeroMesa,
      'capacidad':  capacidad,
    });
    return MesaModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> eliminarMesa(String mesaId) async {
    await _dio.delete('/api/mesas/$mesaId');
  }

  // ── CAJAS ────────────────────────────────────────────────────────────────────

  Future<List<CajaConfigModel>> getCajas(String sucursalId) async {
    final r = await _dio.get('/api/caja/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => CajaConfigModel.fromJson(j)).toList();
  }

  Future<CajaConfigModel> crearCaja({
    required String sucursalId,
    required String nombre,
    required String codigoPuntoEmision,
    String? descripcion,
  }) async {
    final r = await _dio.post('/api/caja', data: {
      'sucursalId':          sucursalId,
      'nombre':              nombre,
      'codigoPuntoEmision':  codigoPuntoEmision,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return CajaConfigModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> toggleCaja(String cajaId) async {
    await _dio.patch('/api/caja/$cajaId/toggle');
  }

  // ── CATEGORÍAS ───────────────────────────────────────────────────────────────

  Future<List<CategoriaModel>> getCategorias(String restaurantId) async {
    final r = await _dio.get('/api/categorias/restaurant/$restaurantId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => CategoriaModel.fromJson(j)).toList();
  }

  Future<CategoriaModel> crearCategoria({
    required String restaurantId,
    required String nombre,
    String? descripcion,
  }) async {
    final r = await _dio.post('/api/categorias', data: {
      'restaurantId': restaurantId,
      'nombre':       nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return CategoriaModel.fromJson(r.data['data'] ?? r.data);
  }

  // ── SUBCATEGORÍAS ────────────────────────────────────────────────────────────

  Future<List<SubcategoriaModel>> getSubcategorias(String categoriaId) async {
    final r = await _dio.get('/api/categorias/$categoriaId/subcategorias');
    final List data = r.data['data'] ?? [];
    return data.map((j) => SubcategoriaModel.fromJson(j)).toList();
  }

  Future<SubcategoriaModel> crearSubcategoria({
    required String categoriaId,
    required String nombre,
    String? descripcion,
  }) async {
    final r = await _dio.post('/api/categorias/subcategorias', data: {
      'categoriaId': categoriaId,
      'nombre':      nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return SubcategoriaModel.fromJson(r.data['data'] ?? r.data);
  }

  // ── PLATOS ───────────────────────────────────────────────────────────────────

  Future<List<PlatoModel>> getPlatosSucursal(String sucursalId) async {
    final r = await _dio.get('/api/platos/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => PlatoModel.fromJson(j)).toList();
  }

  Future<List<PlatoMasterModel>> getPlatosBySubcategoria(String subcategoriaId) async {
    final r = await _dio.get('/api/platos/subcategoria/$subcategoriaId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => PlatoMasterModel.fromJson(j)).toList();
  }

  Future<PlatoMasterModel> crearPlato({
    required String subcategoriaId,
    required String nombre,
    String? descripcion,
    int? tiempoPreparacion,
  }) async {
    final r = await _dio.post('/api/platos', data: {
      'subcategoriaId':      subcategoriaId,
      'nombre':              nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
      if (tiempoPreparacion != null) 'tiempoPreparacion': tiempoPreparacion,
    });
    return PlatoMasterModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<PlatoModel> asignarPlatoSucursal({
    required String sucursalId,
    required String platoId,
    required double precio,
  }) async {
    final r = await _dio.post('/api/platos/sucursal', data: {
      'sucursalId': sucursalId,
      'platoId':    platoId,
      'precio':     precio,
    });
    return PlatoModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> toggleDisponibilidadPlato(String sucursalPlatoId, bool disponible) async {
    await _dio.put('/api/platos/sucursal/$sucursalPlatoId', data: {
      'disponible': disponible,
    });
  }

  // ── USUARIOS ─────────────────────────────────────────────────────────────────

  Future<List<UsuarioListModel>> getUsuarios(String sucursalId) async {
    final r = await _dio.get('/api/usuarios/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => UsuarioListModel.fromJson(j)).toList();
  }

  Future<UsuarioListModel> crearUsuario({
    required String sucursalId,
    required String rolId,
    required String nombre,
    required String usuario,
    required String password,
    String? correo,
    String? telefono,
  }) async {
    final r = await _dio.post('/api/usuarios', data: {
      'sucursalId': sucursalId,
      'rolId':      rolId,
      'nombre':     nombre,
      'usuario':    usuario,
      'password':   password,
      if (correo != null && correo.isNotEmpty) 'correo': correo,
      if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
    });
    return UsuarioListModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> toggleUsuario(String usuarioId) async {
    await _dio.patch('/api/usuarios/$usuarioId/toggle-activo');
  }

  Future<List<RolModel>> getRoles() async {
    final r = await _dio.get('/api/roles');
    final List data = r.data['data'] ?? [];
    return data.map((j) => RolModel.fromJson(j)).toList();
  }

  // ── SUPERADMIN: TENANTS / RESTAURANTS / SUCURSALES ──────────────────────────

  Future<List<TenantModel>> getTenants() async {
    final r = await _dio.get('/api/tenants');
    final List data = r.data['data'] ?? [];
    return data.map((j) => TenantModel.fromJson(j)).toList();
  }

  Future<TenantModel> crearTenant({
    required String nombre,
    required String email,
    String? ruc,
    String? telefono,
    String plan = 'BASIC',
  }) async {
    final r = await _dio.post('/api/tenants', data: {
      'nombre': nombre,
      'email':  email,
      if (ruc != null && ruc.isNotEmpty)      'ruc':      ruc,
      if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
      'plan': plan,
    });
    return TenantModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> toggleTenant(String tenantId) async {
    await _dio.patch('/api/tenants/$tenantId/toggle-activo');
  }

  Future<List<RestaurantModel>> getRestaurantsByTenant(String tenantId) async {
    final r = await _dio.get('/api/restaurants/tenant/$tenantId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => RestaurantModel.fromJson(j)).toList();
  }

  Future<RestaurantModel> crearRestaurant({
    required String tenantId,
    required String nombre,
    String colorPrimario = '#D4A017',
    String colorSecundario = '#2C3E50',
  }) async {
    final r = await _dio.post('/api/restaurants', data: {
      'tenantId':        tenantId,
      'nombre':          nombre,
      'colorPrimario':   colorPrimario,
      'colorSecundario': colorSecundario,
    });
    return RestaurantModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<List<SucursalModel>> getSucursalesByRestaurant(String restaurantId) async {
    final r = await _dio.get('/api/sucursales/restaurant/$restaurantId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => SucursalModel.fromJson(j)).toList();
  }

  Future<SucursalModel> crearSucursal({
    required String restaurantId,
    required String nombre,
    required String direccion,
    String? ciudad,
    String? telefono,
    String? codigoEstablecimiento,
  }) async {
    final r = await _dio.post('/api/sucursales', data: {
      'restaurantId': restaurantId,
      'nombre':       nombre,
      'direccion':    direccion,
      if (ciudad != null && ciudad.isNotEmpty)                     'ciudad':                ciudad,
      if (telefono != null && telefono.isNotEmpty)                 'telefono':              telefono,
      if (codigoEstablecimiento != null && codigoEstablecimiento.isNotEmpty)
        'codigoEstablecimiento': codigoEstablecimiento,
    });
    return SucursalModel.fromJson(r.data['data'] ?? r.data);
  }

  // ── Impresoras de comandas ──────────────────────────────────────────────
  Future<List<ImpresoraModel>> getImpresoras(String sucursalId) async {
    final r = await _dio.get('/api/impresoras/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => ImpresoraModel.fromJson(j)).toList();
  }

  Future<ImpresoraModel> crearImpresora({
    required String sucursalId,
    required String nombre,
    String? area,
    String? ip,
    int? puerto,
    List<String> categoriaIds = const [],
  }) async {
    final r = await _dio.post('/api/impresoras', data: {
      'sucursalId': sucursalId,
      'nombre':     nombre,
      if (area != null && area.isNotEmpty) 'area': area,
      if (ip != null && ip.isNotEmpty)     'ip':   ip,
      if (puerto != null)                  'puerto': puerto,
      'categoriaIds': categoriaIds,
    });
    return ImpresoraModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<ImpresoraModel> actualizarImpresora({
    required String impresoraId,
    required String sucursalId,
    required String nombre,
    String? area,
    String? ip,
    int? puerto,
  }) async {
    final r = await _dio.put('/api/impresoras/$impresoraId', data: {
      'sucursalId': sucursalId,
      'nombre':     nombre,
      if (area != null && area.isNotEmpty) 'area': area,
      if (ip != null && ip.isNotEmpty)     'ip':   ip,
      if (puerto != null)                  'puerto': puerto,
    });
    return ImpresoraModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> asignarCategoriasImpresora(String impresoraId, List<String> categoriaIds) async {
    await _dio.patch('/api/impresoras/$impresoraId/categorias', data: categoriaIds);
  }

  Future<void> toggleImpresora(String impresoraId) async {
    await _dio.patch('/api/impresoras/$impresoraId/toggle-activo');
  }
}
