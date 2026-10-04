import '../../../core/network/api_client.dart';

/// Adelanto de reserva: dinero que el cliente deja antes y se descuenta el
/// día que consume. No vence; si cancela, queda para otro día.
class AdelantoModel {
  final String adelantoId;
  final String clienteId;
  final String nombreCliente;
  final String? cedulaCliente;
  final double monto;
  /// Lo que queda por usar (el monto menos lo ya devuelto al cliente).
  final double disponible;
  final String metodoPagoId;
  final String nombreMetodoPago;
  final String? referencia;
  final DateTime? fechaPrevista;
  final String? nota;
  /// PENDIENTE | APLICADO | ANULADO
  final String estado;
  final DateTime fechaRegistro;
  final String usuario;
  final String? numeroFactura;

  const AdelantoModel({
    required this.adelantoId,
    required this.clienteId,
    required this.nombreCliente,
    this.cedulaCliente,
    required this.monto,
    required this.disponible,
    required this.metodoPagoId,
    required this.nombreMetodoPago,
    this.referencia,
    this.fechaPrevista,
    this.nota,
    required this.estado,
    required this.fechaRegistro,
    required this.usuario,
    this.numeroFactura,
  });

  bool get pendiente => estado == 'PENDIENTE';

  static double _d(dynamic v) =>
      v == null ? 0 : v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;

  factory AdelantoModel.fromJson(Map<String, dynamic> j) => AdelantoModel(
        adelantoId:       j['adelantoId']?.toString() ?? '',
        clienteId:        j['clienteId']?.toString() ?? '',
        nombreCliente:    j['nombreCliente']?.toString() ?? '',
        cedulaCliente:    j['cedulaCliente']?.toString(),
        monto:            _d(j['monto']),
        disponible:       _d(j['disponible']),
        metodoPagoId:     j['metodoPagoId']?.toString() ?? '',
        nombreMetodoPago: j['nombreMetodoPago']?.toString() ?? '',
        referencia:       j['referencia']?.toString(),
        fechaPrevista:    DateTime.tryParse(j['fechaPrevista']?.toString() ?? ''),
        nota:             j['nota']?.toString(),
        estado:           j['estado']?.toString() ?? 'PENDIENTE',
        fechaRegistro:    DateTime.tryParse(j['fechaRegistro']?.toString() ?? '') ?? DateTime.now(),
        usuario:          j['usuario']?.toString() ?? '',
        numeroFactura:    j['numeroFactura']?.toString(),
      );
}

/// [habilitado] = false si el restaurante no usa adelantos: la app esconde
/// el módulo por completo.
class ListaAdelantos {
  final bool habilitado;
  final List<AdelantoModel> adelantos;
  const ListaAdelantos({this.habilitado = false, this.adelantos = const []});
}

class AdelantosRepository {
  final _dio = ApiClient.instance.dio;

  /// Adelantos de la sucursal por estado (PENDIENTE por defecto). Si el
  /// endpoint aún no está desplegado o falla, responde "no habilitado" en
  /// vez de romper la pantalla que lo consulta.
  Future<ListaAdelantos> listar(String sucursalId, {String estado = 'PENDIENTE', String? buscar}) async {
    try {
      final r = await _dio.get('/api/adelantos/sucursal/$sucursalId', queryParameters: {
        'estado': estado,
        if (buscar != null && buscar.trim().isNotEmpty) 'buscar': buscar.trim(),
      });
      final d = r.data['data'] ?? {};
      return ListaAdelantos(
        habilitado: d['habilitado'] == true,
        adelantos: ((d['adelantos'] as List?) ?? [])
            .map((e) => AdelantoModel.fromJson(e))
            .toList(),
      );
    } catch (_) {
      return const ListaAdelantos();
    }
  }

  /// Igual que [listar] pero propaga el error: para la pantalla de
  /// Adelantos, donde el cajero sí debe enterarse si algo falló.
  Future<ListaAdelantos> listarOFallar(String sucursalId, {String estado = 'PENDIENTE'}) async {
    final r = await _dio.get('/api/adelantos/sucursal/$sucursalId',
        queryParameters: {'estado': estado});
    final d = r.data['data'] ?? {};
    return ListaAdelantos(
      habilitado: d['habilitado'] == true,
      adelantos: ((d['adelantos'] as List?) ?? [])
          .map((e) => AdelantoModel.fromJson(e))
          .toList(),
    );
  }

  Future<AdelantoModel> registrar({
    required String aperturaCierreCajaId,
    required String clienteId,
    required double monto,
    required String metodoPagoId,
    String? referencia,
    DateTime? fechaPrevista,
    String? nota,
    required String clientRequestId,
  }) async {
    final r = await _dio.post('/api/adelantos', data: {
      'aperturaCierreCajaId': aperturaCierreCajaId,
      'clienteId': clienteId,
      'monto': monto,
      'metodoPagoId': metodoPagoId,
      if (referencia != null && referencia.isNotEmpty) 'referencia': referencia,
      if (fechaPrevista != null) 'fechaPrevista': _fecha(fechaPrevista),
      if (nota != null && nota.isNotEmpty) 'nota': nota,
      'clientRequestId': clientRequestId,
    });
    return AdelantoModel.fromJson(r.data['data']);
  }

  Future<AdelantoModel> cambiarFecha(String adelantoId, DateTime? fecha) async {
    final r = await _dio.patch('/api/adelantos/$adelantoId/fecha-prevista',
        data: {'fechaPrevista': fecha != null ? _fecha(fecha) : null});
    return AdelantoModel.fromJson(r.data['data']);
  }

  Future<AdelantoModel> anular(String adelantoId, String motivo) async {
    final r = await _dio.post('/api/adelantos/$adelantoId/anular', data: {'motivo': motivo});
    return AdelantoModel.fromJson(r.data['data']);
  }

  static String _fecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
