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
    return data.map((j) => MesaModel.fromJson(j)).toList()..sort(_porNumeroMesa);
  }

  Future<List<MesaModel>> getMesasBySalon(String salonId) async {
    final r = await _dio.get('/api/mesas/salon/$salonId');
    final List data = r.data['data'] ?? [];
    return data.map((j) => MesaModel.fromJson(j)).toList()..sort(_porNumeroMesa);
  }

  Future<void> cambiarEstadoMesa(String mesaId, String estado) async {
    await _dio.patch('/api/mesas/$mesaId/estado', data: {'estado': estado});
  }

  /// Orden natural: "Mesa 2" antes que "Mesa 10" (el backend también ordena,
  /// pero así la app no depende de la versión desplegada).
  static int _porNumeroMesa(MesaModel a, MesaModel b) {
    final c = _naturalCompare(a.numeroMesa, b.numeroMesa);
    if (c != 0) return c;
    return a.nombreSalon.toLowerCase().compareTo(b.nombreSalon.toLowerCase());
  }

  static final _partes = RegExp(r'\d+|\D+');

  static int _naturalCompare(String a, String b) {
    final pa = _partes.allMatches(a).map((m) => m.group(0)!).toList();
    final pb = _partes.allMatches(b).map((m) => m.group(0)!).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]);
      final nb = int.tryParse(pb[i]);
      final c = (na != null && nb != null)
          ? na.compareTo(nb)
          : pa[i].toLowerCase().compareTo(pb[i].toLowerCase());
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }
}
