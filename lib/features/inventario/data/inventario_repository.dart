import '../../../core/network/api_client.dart';

/// Un plato con control de stock.
class InventarioItemModel {
  final String sucursalPlatoId;
  final String platoId;
  final String nombrePlato;
  final String categoria;
  final String subcategoria;
  final String modoInventario;
  final double? stock;
  final double? stockMinimo;
  final String? unidad;
  final bool agotado;
  final bool bajoMinimo;
  final bool disponible;

  const InventarioItemModel({
    required this.sucursalPlatoId,
    required this.platoId,
    required this.nombrePlato,
    this.categoria = '',
    this.subcategoria = '',
    this.modoInventario = 'SIN_CONTROL',
    this.stock,
    this.stockMinimo,
    this.unidad,
    this.agotado = false,
    this.bajoMinimo = false,
    this.disponible = true,
  });

  /// Sin decimales cuando son unidades enteras: "23", no "23.000".
  String get stockTexto => _num(stock);
  String get minimoTexto => _num(stockMinimo);

  static String _num(double? v) {
    if (v == null) return '—';
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(3);
  }

  factory InventarioItemModel.fromJson(Map<String, dynamic> j) => InventarioItemModel(
        sucursalPlatoId: j['sucursalPlatoId']?.toString() ?? '',
        platoId:         j['platoId']?.toString() ?? '',
        nombrePlato:     j['nombrePlato']?.toString() ?? '',
        categoria:       j['categoria']?.toString() ?? '',
        subcategoria:    j['subcategoria']?.toString() ?? '',
        modoInventario:  j['modoInventario']?.toString() ?? 'SIN_CONTROL',
        stock:           _d(j['stock']),
        stockMinimo:     _d(j['stockMinimo']),
        unidad:          j['unidad']?.toString(),
        agotado:         j['agotado'] ?? false,
        bajoMinimo:      j['bajoMinimo'] ?? false,
        disponible:      j['disponible'] ?? true,
      );

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// Una línea del historial de un plato.
class MovimientoInventarioModel {
  final String movimientoInventarioId;
  final DateTime fecha;
  final String tipo; // INGRESO, VENTA, ANULACION, AJUSTE, COMPRA, MERMA
  final double cantidad;
  final double stockResultante;
  final String? usuario;
  final int? numeroOrden;
  final String? nota;
  /// Costo por unidad base del movimiento (solo insumos).
  final double? costoUnitario;

  const MovimientoInventarioModel({
    required this.movimientoInventarioId,
    required this.fecha,
    required this.tipo,
    required this.cantidad,
    required this.stockResultante,
    this.usuario,
    this.numeroOrden,
    this.nota,
    this.costoUnitario,
  });

  factory MovimientoInventarioModel.fromJson(Map<String, dynamic> j) =>
      MovimientoInventarioModel(
        movimientoInventarioId: j['movimientoInventarioId']?.toString() ?? '',
        fecha: DateTime.tryParse(j['fecha']?.toString() ?? '') ?? DateTime.now(),
        tipo: j['tipo']?.toString() ?? '',
        cantidad: InventarioItemModel._d(j['cantidad']) ?? 0,
        stockResultante: InventarioItemModel._d(j['stockResultante']) ?? 0,
        usuario: j['usuario']?.toString(),
        numeroOrden: (j['numeroOrden'] as num?)?.toInt(),
        nota: j['nota']?.toString(),
        costoUnitario: InventarioItemModel._d(j['costoUnitario']),
      );
}

/// Lo agotado y lo que está por agotarse en la sucursal.
class AlertasInventarioModel {
  final bool habilitado;
  final int totalAgotados;
  final int totalBajoMinimo;
  final List<InventarioItemModel> agotados;
  final List<InventarioItemModel> bajoMinimo;
  /// Insumos en el mínimo o en negativo (inventario por recetas).
  final int totalInsumosBajoMinimo;
  final List<InsumoModel> insumosBajoMinimo;

  const AlertasInventarioModel({
    this.habilitado = false,
    this.totalAgotados = 0,
    this.totalBajoMinimo = 0,
    this.agotados = const [],
    this.bajoMinimo = const [],
    this.totalInsumosBajoMinimo = 0,
    this.insumosBajoMinimo = const [],
  });

  bool get hayAlgoQueAvisar => habilitado
      && (totalAgotados > 0 || totalBajoMinimo > 0 || totalInsumosBajoMinimo > 0);

  factory AlertasInventarioModel.fromJson(Map<String, dynamic> j) => AlertasInventarioModel(
        habilitado:      j['habilitado'] ?? false,
        totalAgotados:   (j['totalAgotados'] as num?)?.toInt() ?? 0,
        totalBajoMinimo: (j['totalBajoMinimo'] as num?)?.toInt() ?? 0,
        agotados: ((j['agotados'] as List?) ?? [])
            .map((e) => InventarioItemModel.fromJson(e)).toList(),
        bajoMinimo: ((j['bajoMinimo'] as List?) ?? [])
            .map((e) => InventarioItemModel.fromJson(e)).toList(),
        totalInsumosBajoMinimo: (j['totalInsumosBajoMinimo'] as num?)?.toInt() ?? 0,
        insumosBajoMinimo: ((j['insumosBajoMinimo'] as List?) ?? [])
            .map((e) => InsumoModel.fromJson(e)).toList(),
      );
}

double? _dbl(dynamic v) => InventarioItemModel._d(v);

/// Un insumo del restaurante con su existencia en la sucursal.
class InsumoModel {
  final String insumoId;
  final String nombre;
  final String unidad; // GRAMO, MILILITRO, UNIDAD
  final String? categoria;
  final bool activo;
  final double stock;
  final double? stockMinimo;
  final double? costoPromedio;
  final double valorStock;
  final bool bajoMinimo;
  final bool negativo;

  const InsumoModel({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    this.categoria,
    this.activo = true,
    this.stock = 0,
    this.stockMinimo,
    this.costoPromedio,
    this.valorStock = 0,
    this.bajoMinimo = false,
    this.negativo = false,
  });

  factory InsumoModel.fromJson(Map<String, dynamic> j) => InsumoModel(
        insumoId:      j['insumoId']?.toString() ?? '',
        nombre:        j['nombre']?.toString() ?? '',
        unidad:        j['unidad']?.toString() ?? 'UNIDAD',
        categoria:     j['categoria']?.toString(),
        activo:        j['activo'] ?? true,
        stock:         _dbl(j['stock']) ?? 0,
        stockMinimo:   _dbl(j['stockMinimo']),
        costoPromedio: _dbl(j['costoPromedio']),
        valorStock:    _dbl(j['valorStock']) ?? 0,
        bajoMinimo:    j['bajoMinimo'] ?? false,
        negativo:      j['negativo'] ?? false,
      );
}

/// Una línea de receta: cuánto de un insumo lleva una porción.
class RecetaItemModel {
  final String insumoId;
  final String nombre;
  final String unidad;
  final double cantidad;
  final double? costoUnitario;
  final double? costoLinea;

  const RecetaItemModel({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    this.costoUnitario,
    this.costoLinea,
  });

  factory RecetaItemModel.fromJson(Map<String, dynamic> j) => RecetaItemModel(
        insumoId:      j['insumoId']?.toString() ?? '',
        nombre:        j['nombre']?.toString() ?? '',
        unidad:        j['unidad']?.toString() ?? 'UNIDAD',
        cantidad:      _dbl(j['cantidad']) ?? 0,
        costoUnitario: _dbl(j['costoUnitario']),
        costoLinea:    _dbl(j['costoLinea']),
      );
}

/// Receta de un plato con su costo en la sucursal.
class RecetaModel {
  final String platoId;
  final String nombrePlato;
  final String? sucursalPlatoId;
  final String? modoInventario;
  final double? precio;
  final double costoTotal;
  /// Falso si algún insumo todavía no tiene compras: el costo se queda corto.
  final bool costoCompleto;
  final double? margenPorcentaje;
  final List<RecetaItemModel> items;

  const RecetaModel({
    required this.platoId,
    required this.nombrePlato,
    this.sucursalPlatoId,
    this.modoInventario,
    this.precio,
    this.costoTotal = 0,
    this.costoCompleto = false,
    this.margenPorcentaje,
    this.items = const [],
  });

  bool get seDescuenta => modoInventario == 'RECETA';

  factory RecetaModel.fromJson(Map<String, dynamic> j) => RecetaModel(
        platoId:          j['platoId']?.toString() ?? '',
        nombrePlato:      j['nombrePlato']?.toString() ?? '',
        sucursalPlatoId:  j['sucursalPlatoId']?.toString(),
        modoInventario:   j['modoInventario']?.toString(),
        precio:           _dbl(j['precio']),
        costoTotal:       _dbl(j['costoTotal']) ?? 0,
        costoCompleto:    j['costoCompleto'] ?? false,
        margenPorcentaje: _dbl(j['margenPorcentaje']),
        items: ((j['items'] as List?) ?? [])
            .map((e) => RecetaItemModel.fromJson(e)).toList(),
      );
}

class ProveedorModel {
  final String proveedorId;
  final String nombre;
  final String? ruc;
  final String? telefono;
  final String? email;
  final bool activo;

  const ProveedorModel({
    required this.proveedorId,
    required this.nombre,
    this.ruc,
    this.telefono,
    this.email,
    this.activo = true,
  });

  factory ProveedorModel.fromJson(Map<String, dynamic> j) => ProveedorModel(
        proveedorId: j['proveedorId']?.toString() ?? '',
        nombre:      j['nombre']?.toString() ?? '',
        ruc:         j['ruc']?.toString(),
        telefono:    j['telefono']?.toString(),
        email:       j['email']?.toString(),
        activo:      j['activo'] ?? true,
      );
}

class CompraItemModel {
  final String insumoId;
  final String nombre;
  final String unidad;
  final double cantidad;
  final double costoUnitario;
  final double subtotal;

  const CompraItemModel({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.cantidad,
    required this.costoUnitario,
    required this.subtotal,
  });

  factory CompraItemModel.fromJson(Map<String, dynamic> j) => CompraItemModel(
        insumoId:      j['insumoId']?.toString() ?? '',
        nombre:        j['nombre']?.toString() ?? '',
        unidad:        j['unidad']?.toString() ?? 'UNIDAD',
        cantidad:      _dbl(j['cantidad']) ?? 0,
        costoUnitario: _dbl(j['costoUnitario']) ?? 0,
        subtotal:      _dbl(j['subtotal']) ?? 0,
      );
}

class CompraModel {
  final String compraId;
  final DateTime fecha;
  final String? proveedor;
  final String? numeroDocumento;
  final double total;
  final String? usuario;
  final String? nota;
  final int totalItems;
  final List<CompraItemModel> items;

  const CompraModel({
    required this.compraId,
    required this.fecha,
    this.proveedor,
    this.numeroDocumento,
    this.total = 0,
    this.usuario,
    this.nota,
    this.totalItems = 0,
    this.items = const [],
  });

  factory CompraModel.fromJson(Map<String, dynamic> j) => CompraModel(
        compraId:        j['compraId']?.toString() ?? '',
        fecha:           DateTime.tryParse(j['fecha']?.toString() ?? '') ?? DateTime.now(),
        proveedor:       j['proveedor']?.toString(),
        numeroDocumento: j['numeroDocumento']?.toString(),
        total:           _dbl(j['total']) ?? 0,
        usuario:         j['usuario']?.toString(),
        nota:            j['nota']?.toString(),
        totalItems:      (j['totalItems'] as num?)?.toInt() ?? 0,
        items: ((j['items'] as List?) ?? [])
            .map((e) => CompraItemModel.fromJson(e)).toList(),
      );
}

/// Línea que se envía al registrar una compra (en la unidad base).
class CompraLinea {
  final String insumoId;
  final double cantidad;
  final double costoTotal;
  const CompraLinea(this.insumoId, this.cantidad, this.costoTotal);
}

class InventarioRepository {
  final _dio = ApiClient.instance.dio;

  Future<List<InventarioItemModel>> getInventario(String sucursalId) async {
    final r = await _dio.get('/api/inventario/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((e) => InventarioItemModel.fromJson(e)).toList();
  }

  /// Alertas para el dashboard. Devuelve vacío (sin romper la pantalla) si el
  /// servidor todavía no tiene el módulo desplegado.
  Future<AlertasInventarioModel> getAlertas(String sucursalId) async {
    try {
      final r = await _dio.get('/api/inventario/sucursal/$sucursalId/alertas');
      return AlertasInventarioModel.fromJson(r.data['data'] ?? r.data);
    } catch (_) {
      return const AlertasInventarioModel();
    }
  }

  Future<InventarioItemModel> ingresar(
    String sucursalPlatoId, {
    required double cantidad,
    String? nota,
  }) async {
    final r = await _dio.post('/api/inventario/$sucursalPlatoId/ingreso', data: {
      'cantidad': cantidad,
      if (nota != null && nota.isNotEmpty) 'nota': nota,
    });
    return InventarioItemModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<InventarioItemModel> ajustar(
    String sucursalPlatoId, {
    required double stock,
    String? nota,
  }) async {
    final r = await _dio.post('/api/inventario/$sucursalPlatoId/ajuste', data: {
      'stock': stock,
      if (nota != null && nota.isNotEmpty) 'nota': nota,
    });
    return InventarioItemModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Activa o desactiva el control de stock de un plato en la sucursal.
  /// [stockInicial] solo se usa al activarlo.
  /// [modo] manda sobre [controlar]: 'SIN_CONTROL', 'UNIDADES' o 'RECETA'.
  Future<InventarioItemModel> configurar(
    String sucursalPlatoId, {
    bool controlar = false,
    String? modo,
    double? stockInicial,
    double? stockMinimo,
    String? unidad,
  }) async {
    final r = await _dio.put('/api/inventario/$sucursalPlatoId/configuracion', data: {
      'modoInventario': modo ?? (controlar ? 'UNIDADES' : 'SIN_CONTROL'),
      if (stockInicial != null) 'stockInicial': stockInicial,
      if (stockMinimo != null) 'stockMinimo': stockMinimo,
      if (unidad != null && unidad.isNotEmpty) 'unidad': unidad,
    });
    return InventarioItemModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<List<MovimientoInventarioModel>> getMovimientos(String sucursalPlatoId) async {
    final r = await _dio.get('/api/inventario/$sucursalPlatoId/movimientos');
    final List data = r.data['data'] ?? [];
    return data.map((e) => MovimientoInventarioModel.fromJson(e)).toList();
  }

  // ------------------------------------------------------------------
  // Inventario por insumos (recetas)
  // ------------------------------------------------------------------

  String _base(String sucursalId) => '/api/inventario/sucursal/$sucursalId';

  Future<List<InsumoModel>> getInsumos(String sucursalId, {bool incluirInactivos = false}) async {
    final r = await _dio.get('${_base(sucursalId)}/insumos',
        queryParameters: {'incluirInactivos': incluirInactivos});
    final List data = r.data['data'] ?? [];
    return data.map((e) => InsumoModel.fromJson(e)).toList();
  }

  Future<InsumoModel> guardarInsumo(
    String sucursalId, {
    String? insumoId,
    required String nombre,
    required String unidad,
    String? categoria,
    double? stockMinimo,
  }) async {
    final body = {
      'nombre': nombre,
      'unidad': unidad,
      if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
      if (stockMinimo != null) 'stockMinimo': stockMinimo,
    };
    final r = insumoId == null
        ? await _dio.post('${_base(sucursalId)}/insumos', data: body)
        : await _dio.put('${_base(sucursalId)}/insumos/$insumoId', data: body);
    return InsumoModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<InsumoModel> cambiarEstadoInsumo(String sucursalId, String insumoId, bool activo) async {
    final r = await _dio.patch('${_base(sucursalId)}/insumos/$insumoId/activo',
        queryParameters: {'activo': activo});
    return InsumoModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<InsumoModel> ajustarInsumo(String sucursalId, String insumoId,
      {required double stock, String? nota}) async {
    final r = await _dio.post('${_base(sucursalId)}/insumos/$insumoId/ajuste', data: {
      'stock': stock,
      if (nota != null && nota.isNotEmpty) 'nota': nota,
    });
    return InsumoModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<InsumoModel> registrarMerma(String sucursalId, String insumoId,
      {required double cantidad, required String motivo}) async {
    final r = await _dio.post('${_base(sucursalId)}/insumos/$insumoId/merma',
        data: {'cantidad': cantidad, 'motivo': motivo});
    return InsumoModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<List<MovimientoInventarioModel>> getMovimientosInsumo(
      String sucursalId, String insumoId) async {
    final r = await _dio.get('${_base(sucursalId)}/insumos/$insumoId/movimientos');
    final List data = r.data['data'] ?? [];
    return data.map((e) => MovimientoInventarioModel.fromJson(e)).toList();
  }

  Future<RecetaModel> getReceta(String sucursalId, String platoId) async {
    final r = await _dio.get('${_base(sucursalId)}/recetas/$platoId');
    return RecetaModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Reemplaza la receta completa. Lista vacía = el plato queda sin receta.
  Future<RecetaModel> guardarReceta(
      String sucursalId, String platoId, Map<String, double> cantidades) async {
    final r = await _dio.put('${_base(sucursalId)}/recetas/$platoId', data: {
      'items': cantidades.entries
          .map((e) => {'insumoId': e.key, 'cantidad': e.value})
          .toList(),
    });
    return RecetaModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<List<ProveedorModel>> getProveedores(String sucursalId,
      {bool incluirInactivos = false}) async {
    final r = await _dio.get('${_base(sucursalId)}/proveedores',
        queryParameters: {'incluirInactivos': incluirInactivos});
    final List data = r.data['data'] ?? [];
    return data.map((e) => ProveedorModel.fromJson(e)).toList();
  }

  Future<ProveedorModel> guardarProveedor(
    String sucursalId, {
    String? proveedorId,
    required String nombre,
    String? ruc,
    String? telefono,
    String? email,
  }) async {
    final body = {
      'nombre': nombre,
      if (ruc != null && ruc.isNotEmpty) 'ruc': ruc,
      if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
      if (email != null && email.isNotEmpty) 'email': email,
    };
    final r = proveedorId == null
        ? await _dio.post('${_base(sucursalId)}/proveedores', data: body)
        : await _dio.put('${_base(sucursalId)}/proveedores/$proveedorId', data: body);
    return ProveedorModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<ProveedorModel> cambiarEstadoProveedor(
      String sucursalId, String proveedorId, bool activo) async {
    final r = await _dio.patch('${_base(sucursalId)}/proveedores/$proveedorId/activo',
        queryParameters: {'activo': activo});
    return ProveedorModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<CompraModel> registrarCompra(
    String sucursalId, {
    String? proveedorId,
    String? numeroDocumento,
    DateTime? fecha,
    String? nota,
    required List<CompraLinea> lineas,
  }) async {
    final r = await _dio.post('${_base(sucursalId)}/compras', data: {
      if (proveedorId != null) 'proveedorId': proveedorId,
      if (numeroDocumento != null && numeroDocumento.isNotEmpty) 'numeroDocumento': numeroDocumento,
      if (fecha != null) 'fecha': _fecha(fecha),
      if (nota != null && nota.isNotEmpty) 'nota': nota,
      'items': lineas
          .map((l) => {'insumoId': l.insumoId, 'cantidad': l.cantidad, 'costoTotal': l.costoTotal})
          .toList(),
    });
    return CompraModel.fromJson(r.data['data'] ?? r.data);
  }

  Future<List<CompraModel>> getCompras(String sucursalId,
      {DateTime? desde, DateTime? hasta}) async {
    final r = await _dio.get('${_base(sucursalId)}/compras', queryParameters: {
      if (desde != null) 'desde': _fecha(desde),
      if (hasta != null) 'hasta': _fecha(hasta),
    });
    final List data = r.data['data'] ?? [];
    return data.map((e) => CompraModel.fromJson(e)).toList();
  }

  Future<CompraModel> getCompra(String sucursalId, String compraId) async {
    final r = await _dio.get('${_base(sucursalId)}/compras/$compraId');
    return CompraModel.fromJson(r.data['data'] ?? r.data);
  }

  static String _fecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
