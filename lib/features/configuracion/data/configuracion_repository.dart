import '../../../core/models/config_models.dart';
import '../../../core/models/factura_model.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/models/salon_model.dart';
import '../../../core/models/mesa_model.dart';
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

  // Incluye inactivas: la configuración las muestra para poder reactivarlas
  Future<List<TasaIvaModel>> getTasasIva(String tenantId) async {
    final r = await _dio.get('/api/tasa-iva/tenant/$tenantId',
        queryParameters: {'incluirInactivas': true});
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

  // Incluye inactivos: la configuración los muestra para poder reactivarlos
  Future<List<SalonModel>> getSalones(String sucursalId) async {
    final r = await _dio.get('/api/salones/sucursal/$sucursalId',
        queryParameters: {'incluirInactivos': true});
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

  Future<SalonModel> actualizarSalon({
    required String salonId,
    required String sucursalId,
    required String nombre,
    String? descripcion,
  }) async {
    final r = await _dio.put('/api/salones/$salonId', data: {
      'sucursalId':  sucursalId,
      'nombre':      nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return SalonModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> toggleSalon(String salonId) async {
    await _dio.patch('/api/salones/$salonId/toggle-activo');
  }

  // ── MESAS ────────────────────────────────────────────────────────────────────

  // Incluye inactivas: la configuración las muestra para poder reactivarlas
  Future<List<MesaModel>> getMesasBySalon(String salonId) async {
    final r = await _dio.get('/api/mesas/salon/$salonId',
        queryParameters: {'incluirInactivas': true});
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

  Future<MesaModel> actualizarMesa({
    required String mesaId,
    required String salonId,
    required String numeroMesa,
    required int capacidad,
  }) async {
    final r = await _dio.put('/api/mesas/$mesaId', data: {
      'salonId':    salonId,
      'numeroMesa': numeroMesa,
      'capacidad':  capacidad,
    });
    return MesaModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> eliminarMesa(String mesaId) async {
    await _dio.delete('/api/mesas/$mesaId');
  }

  Future<void> toggleMesa(String mesaId) async {
    await _dio.patch('/api/mesas/$mesaId/toggle-activo');
  }

  // ── CAJAS ────────────────────────────────────────────────────────────────────

  // Incluye inactivas: la configuración las muestra para poder reactivarlas
  Future<List<CajaConfigModel>> getCajas(String sucursalId) async {
    final r = await _dio.get('/api/caja/sucursal/$sucursalId',
        queryParameters: {'incluirInactivas': true});
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

  Future<CajaConfigModel> actualizarCaja({
    required String cajaId,
    required String sucursalId,
    required String nombre,
    required String codigoPuntoEmision,
    String? descripcion,
  }) async {
    final r = await _dio.put('/api/caja/$cajaId', data: {
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

  // ── MÉTODOS DE PAGO (por sucursal) ──────────────────────────────────────────

  Future<List<MetodoPagoModel>> getMetodosPago(String sucursalId) async {
    final r = await _dio.get('/api/metodos-pago/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => MetodoPagoModel.fromJson(j)).toList();
  }

  Future<MetodoPagoModel> crearMetodoPago({
    required String sucursalId,
    required String nombre,
    String? descripcion,
    bool requiereReferencia = false,
  }) async {
    final r = await _dio.post('/api/metodos-pago', data: {
      'sucursalId':          sucursalId,
      'nombre':              nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
      'requiereReferencia':  requiereReferencia,
    });
    return MetodoPagoModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<MetodoPagoModel> actualizarMetodoPago({
    required String metodoPagoId,
    required String nombre,
    String? descripcion,
    bool requiereReferencia = false,
  }) async {
    final r = await _dio.put('/api/metodos-pago/$metodoPagoId', data: {
      'nombre':              nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
      'requiereReferencia':  requiereReferencia,
    });
    return MetodoPagoModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> toggleMetodoPago(String metodoPagoId) async {
    await _dio.patch('/api/metodos-pago/$metodoPagoId/toggle');
  }

  // ── CATEGORÍAS ───────────────────────────────────────────────────────────────

  // Incluye inactivas: la configuración las muestra para poder reactivarlas
  Future<List<CategoriaModel>> getCategorias(String restaurantId) async {
    final r = await _dio.get('/api/categorias/restaurant/$restaurantId',
        queryParameters: {'incluirInactivas': true});
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

  Future<CategoriaModel> actualizarCategoria({
    required String categoriaId,
    required String restaurantId,
    required String nombre,
    String? descripcion,
  }) async {
    final r = await _dio.put('/api/categorias/$categoriaId', data: {
      'restaurantId': restaurantId,
      'nombre':       nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return CategoriaModel.fromJson(r.data['data'] ?? r.data);
  }

  // ── SUBCATEGORÍAS ────────────────────────────────────────────────────────────

  // Incluye inactivas: la configuración las muestra para poder reactivarlas
  Future<List<SubcategoriaModel>> getSubcategorias(String categoriaId) async {
    final r = await _dio.get('/api/categorias/$categoriaId/subcategorias',
        queryParameters: {'incluirInactivas': true});
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

  Future<SubcategoriaModel> actualizarSubcategoria({
    required String subcategoriaId,
    required String categoriaId,
    required String nombre,
    String? descripcion,
  }) async {
    final r = await _dio.put('/api/categorias/subcategorias/$subcategoriaId', data: {
      'categoriaId': categoriaId,
      'nombre':      nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return SubcategoriaModel.fromJson(r.data['data'] ?? r.data);
  }

  // ── PLATOS ───────────────────────────────────────────────────────────────────

  // Incluye inactivos: la configuración los muestra para poder reactivarlos
  Future<List<PlatoModel>> getPlatosSucursal(String sucursalId) async {
    final r = await _dio.get('/api/platos/sucursal/$sucursalId',
        queryParameters: {'incluirInactivos': true});
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

  Future<PlatoMasterModel> actualizarPlato({
    required String platoId,
    required String subcategoriaId,
    required String nombre,
    String? descripcion,
  }) async {
    final r = await _dio.put('/api/platos/$platoId', data: {
      'subcategoriaId': subcategoriaId,
      'nombre':         nombre,
      if (descripcion != null && descripcion.isNotEmpty) 'descripcion': descripcion,
    });
    return PlatoMasterModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Actualiza precio y/o disponibilidad del plato en la sucursal.
  /// El backend valida sucursalId/platoId/precio como requeridos, por eso
  /// se envía el cuerpo completo aunque solo cambie la disponibilidad.
  Future<PlatoModel> actualizarPrecioPlato({
    required String sucursalPlatoId,
    required String sucursalId,
    required String platoId,
    required double precio,
    bool? disponible,
  }) async {
    final r = await _dio.put('/api/platos/sucursal/$sucursalPlatoId', data: {
      'sucursalId': sucursalId,
      'platoId':    platoId,
      'precio':     precio,
      if (disponible != null) 'disponible': disponible,
    });
    return PlatoModel.fromJson(r.data['data'] ?? r.data);
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

  Future<UsuarioListModel> actualizarUsuario({
    required String usuarioId,
    required String sucursalId,
    required String rolId,
    required String nombre,
    required String usuario,
    String? correo,
    String? telefono,
  }) async {
    final r = await _dio.put('/api/usuarios/$usuarioId', data: {
      'sucursalId': sucursalId,
      'rolId':      rolId,
      'nombre':     nombre,
      'usuario':    usuario,
      if (correo != null && correo.isNotEmpty) 'correo': correo,
      if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
    });
    return UsuarioListModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<void> cambiarPasswordUsuario(String usuarioId, String nuevaPassword) async {
    await _dio.patch(
      '/api/usuarios/$usuarioId/cambiar-password',
      queryParameters: {'nuevaPassword': nuevaPassword},
    );
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

  /// Fija la fecha del próximo pago del servicio (null = quitar el control).
  Future<RestaurantModel> fijarProximoPago(String restaurantId, DateTime? fecha) async {
    final f = fecha == null
        ? ''
        : '?fecha=${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
    final r = await _dio.patch('/api/restaurants/$restaurantId/proximo-pago$f');
    return RestaurantModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Registra el pago del mes: corre la fecha de próximo pago un mes adelante.
  Future<RestaurantModel> registrarPagoRestaurant(String restaurantId) async {
    final r = await _dio.patch('/api/restaurants/$restaurantId/registrar-pago');
    return RestaurantModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Activa/desactiva la facturación electrónica SRI del restaurante
  /// (activar solo cuando su RUC y P12 ya estén dados de alta en Factuplan).
  Future<RestaurantModel> setFacturacionElectronica(String restaurantId, bool activa) async {
    final r = await _dio.patch(
        '/api/restaurants/$restaurantId/facturacion-electronica?activa=$activa');
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
    String? email,
    String? ruc,
    String? razonSocial,
    String? codigoEstablecimiento,
  }) async {
    final r = await _dio.post('/api/sucursales', data: {
      'restaurantId': restaurantId,
      'nombre':       nombre,
      'direccion':    direccion,
      if (ciudad != null && ciudad.isNotEmpty)                     'ciudad':                ciudad,
      if (telefono != null && telefono.isNotEmpty)                 'telefono':              telefono,
      if (email != null && email.isNotEmpty)                       'email':                 email,
      if (ruc != null && ruc.isNotEmpty)                           'ruc':                   ruc,
      if (razonSocial != null && razonSocial.isNotEmpty)           'razonSocial':           razonSocial,
      if (codigoEstablecimiento != null && codigoEstablecimiento.isNotEmpty)
        'codigoEstablecimiento': codigoEstablecimiento,
    });
    return SucursalModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Actualiza los datos de la sucursal, incluidos RUC y razón social (con
  /// los que se emite la factura electrónica). El PUT reemplaza todos los
  /// campos: siempre enviar el formulario completo prellenado.
  Future<SucursalModel> actualizarSucursal({
    required String sucursalId,
    required String restaurantId,
    required String nombre,
    required String direccion,
    String? ciudad,
    String? telefono,
    String? email,
    String? ruc,
    String? razonSocial,
    String? codigoEstablecimiento,
  }) async {
    final r = await _dio.put('/api/sucursales/$sucursalId', data: {
      'restaurantId':          restaurantId,
      'nombre':                nombre,
      'direccion':             direccion,
      'ciudad':                ciudad,
      'telefono':              telefono,
      'email':                 email,
      'ruc':                   ruc,
      'razonSocial':           razonSocial,
      'codigoEstablecimiento': codigoEstablecimiento,
    });
    return SucursalModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Renombra el restaurante (el backend conserva logo y colores si no se
  /// envían).
  Future<RestaurantModel> actualizarRestaurant({
    required String restaurantId,
    required String tenantId,
    required String nombre,
  }) async {
    final r = await _dio.put('/api/restaurants/$restaurantId', data: {
      'tenantId': tenantId,
      'nombre':   nombre,
    });
    return RestaurantModel.fromJson(r.data['data'] ?? r.data);
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
    String? mac,
    List<String> categoriaIds = const [],
  }) async {
    final r = await _dio.post('/api/impresoras', data: {
      'sucursalId': sucursalId,
      'nombre':     nombre,
      if (area != null && area.isNotEmpty) 'area': area,
      if (ip != null && ip.isNotEmpty)     'ip':   ip,
      if (puerto != null)                  'puerto': puerto,
      if (mac != null && mac.isNotEmpty)   'mac':  mac,
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
    String? mac,
  }) async {
    // ip y mac se envían siempre (aun vacíos → null en backend) para poder
    // quitar una vía de conexión al editar, no solo agregarla.
    final r = await _dio.put('/api/impresoras/$impresoraId', data: {
      'sucursalId': sucursalId,
      'nombre':     nombre,
      if (area != null && area.isNotEmpty) 'area': area,
      'ip':  (ip != null && ip.isNotEmpty) ? ip : null,
      if (puerto != null)                  'puerto': puerto,
      'mac': (mac != null && mac.isNotEmpty) ? mac : null,
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
