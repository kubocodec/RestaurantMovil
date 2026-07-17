import '../../../core/models/orden_model.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/network/api_client.dart';

class OrdenesRepository {
  final _dio = ApiClient.instance.dio;

  // Platos disponibles de la sucursal
  Future<List<PlatoModel>> getPlatosBySucursal(String sucursalId) async {
    final r = await _dio.get('/api/platos/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data
        .map((j) => PlatoModel.fromJson(j))
        .where((p) => p.disponible)
        .toList();
  }

  // Órdenes activas de la sucursal
  Future<List<OrdenModel>> getOrdenesActivas(String sucursalId) async {
    final r = await _dio.get('/api/ordenes/sucursal/$sucursalId/activas');
    final List data = r.data['data'] ?? [];
    return data.map((j) => OrdenModel.fromJson(j)).toList();
  }

  // Detalle de una orden
  Future<OrdenModel> getOrden(String ordenId) async {
    final r = await _dio.get('/api/ordenes/$ordenId');
    return OrdenModel.fromJson(r.data['data'] ?? r.data);
  }

  // Paso 1: Crear orden (sin items).
  // Sin mesa (para llevar) el backend exige la sucursal.
  Future<OrdenModel> crearOrden({
    String? mesaId,
    String? sucursalId,
    required String tipoOrden,     // EN_MESA | PARA_LLEVAR
    String tipoOrigen = 'MESERO',
    String? observaciones,
  }) async {
    final r = await _dio.post('/api/ordenes', data: {
      if (mesaId != null) 'mesaId': mesaId,
      if (sucursalId != null) 'sucursalId': sucursalId,
      'tipoOrden':    tipoOrden,
      'tipoOrigen':   tipoOrigen,
      if (observaciones != null) 'observaciones': observaciones,
    });
    return OrdenModel.fromJson(r.data['data'] ?? r.data);
  }

  // Paso 2: Agregar item a orden existente
  Future<DetalleOrdenModel> agregarDetalle({
    required String ordenId,
    required String platoId,
    required int cantidad,
    String tipoServicio = 'EN_MESA',
    String? observaciones,
  }) async {
    final r = await _dio.post('/api/ordenes/$ordenId/detalles', data: {
      'platoId':      platoId,
      'cantidad':     cantidad,
      'tipoServicio': tipoServicio,
      if (observaciones != null && observaciones.isNotEmpty)
        'observaciones': observaciones,
    });
    return DetalleOrdenModel.fromJson(r.data['data'] ?? r.data);
  }

  // Paso 3: Enviar todos los ítems pendientes a cocina.
  // Devuelve los detalles con los datos de su impresora para imprimir comandas.
  Future<List<DetalleOrdenModel>> enviarACocina(String ordenId) async {
    final r = await _dio.post('/api/ordenes/$ordenId/enviar-cocina');
    final List data = r.data['data'] ?? [];
    return data.map((j) => DetalleOrdenModel.fromJson(j)).toList();
  }

  // Mover unidades de items a otra mesa (ej. 2 de 3 tigrillos).
  // Devuelve la orden destino (existente de esa mesa o recién creada).
  Future<OrdenModel> moverItems({
    required String ordenId,
    required String mesaDestinoId,
    required Map<String, int> cantidadesPorDetalle, // detalleId -> cantidad
  }) async {
    final r = await _dio.post('/api/ordenes/$ordenId/mover-items', data: {
      'mesaDestinoId': mesaDestinoId,
      'items': cantidadesPorDetalle.entries
          .map((e) => {'detalleId': e.key, 'cantidad': e.value})
          .toList(),
    });
    return OrdenModel.fromJson(r.data['data'] ?? r.data);
  }

  // Mover la orden a otra mesa (el cliente se cambió de sitio)
  Future<void> cambiarMesa(String ordenId, String mesaId) async {
    await _dio.patch('/api/ordenes/$ordenId/mesa', queryParameters: {'mesaId': mesaId});
  }

  // Cambiar estado de orden: usa query param ?estado=
  Future<void> cambiarEstadoOrden(String ordenId, String estado) async {
    await _dio.patch('/api/ordenes/$ordenId/estado', queryParameters: {'estado': estado});
  }

  // Cambiar estado de detalle: usa query param ?estado=
  Future<void> cambiarEstadoDetalle(String detalleId, String estado) async {
    await _dio.patch('/api/ordenes/detalles/$detalleId/estado', queryParameters: {'estado': estado});
  }
}
