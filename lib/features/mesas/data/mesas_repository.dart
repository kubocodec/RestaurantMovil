import '../../../core/models/mesa_model.dart';
import '../../../core/models/salon_model.dart';
import '../../../core/network/api_client.dart';

class MesasRepository {
  final _dio = ApiClient.instance.dio;

  Future<List<SalonModel>> getSalonesBySucursal(String sucursalId) async {
    final r = await _dio.get('/api/salones/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => SalonModel.fromJson(j)).toList();
  }

  Future<List<MesaModel>> getMesasBySucursal(String sucursalId) async {
    final r = await _dio.get('/api/mesas/sucursal/$sucursalId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => MesaModel.fromJson(j)).toList();
  }

  Future<List<MesaModel>> getMesasBySalon(String salonId) async {
    final r = await _dio.get('/api/mesas/salon/$salonId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => MesaModel.fromJson(j)).toList();
  }

  Future<void> cambiarEstadoMesa(String mesaId, String estado) async {
    await _dio.patch('/api/mesas/$mesaId/estado', data: {'estado': estado});
  }
}
