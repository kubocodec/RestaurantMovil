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
  final String tipo; // INGRESO, VENTA, ANULACION, AJUSTE
  final double cantidad;
  final double stockResultante;
  final String? usuario;
  final int? numeroOrden;
  final String? nota;

  const MovimientoInventarioModel({
    required this.movimientoInventarioId,
    required this.fecha,
    required this.tipo,
    required this.cantidad,
    required this.stockResultante,
    this.usuario,
    this.numeroOrden,
    this.nota,
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
      );
}

/// Lo agotado y lo que está por agotarse en la sucursal.
class AlertasInventarioModel {
  final bool habilitado;
  final int totalAgotados;
  final int totalBajoMinimo;
  final List<InventarioItemModel> agotados;
  final List<InventarioItemModel> bajoMinimo;

  const AlertasInventarioModel({
    this.habilitado = false,
    this.totalAgotados = 0,
    this.totalBajoMinimo = 0,
    this.agotados = const [],
    this.bajoMinimo = const [],
  });

  bool get hayAlgoQueAvisar => habilitado && (totalAgotados > 0 || totalBajoMinimo > 0);

  factory AlertasInventarioModel.fromJson(Map<String, dynamic> j) => AlertasInventarioModel(
        habilitado:      j['habilitado'] ?? false,
        totalAgotados:   (j['totalAgotados'] as num?)?.toInt() ?? 0,
        totalBajoMinimo: (j['totalBajoMinimo'] as num?)?.toInt() ?? 0,
        agotados: ((j['agotados'] as List?) ?? [])
            .map((e) => InventarioItemModel.fromJson(e)).toList(),
        bajoMinimo: ((j['bajoMinimo'] as List?) ?? [])
            .map((e) => InventarioItemModel.fromJson(e)).toList(),
      );
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
  Future<InventarioItemModel> configurar(
    String sucursalPlatoId, {
    required bool controlar,
    double? stockInicial,
    double? stockMinimo,
    String? unidad,
  }) async {
    final r = await _dio.put('/api/inventario/$sucursalPlatoId/configuracion', data: {
      'modoInventario': controlar ? 'UNIDADES' : 'SIN_CONTROL',
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
}
