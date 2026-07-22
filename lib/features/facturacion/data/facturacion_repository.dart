import '../../../core/models/factura_model.dart';
import '../../../core/network/api_client.dart';

class FacturacionRepository {
  final _dio = ApiClient.instance.dio;

  // Métodos de pago activos de la sucursal (cada sucursal tiene su catálogo).
  // El where es un seguro extra: aunque el backend respondiera alguno
  // inactivo, el cobro jamás debe ofrecerlo.
  Future<List<MetodoPagoModel>> getMetodosPago(String sucursalId) async {
    final r = await _dio.get('/api/metodos-pago/sucursal/$sucursalId/activos');
    final List data = r.data['data'] ?? [];
    return data
        .map((j) => MetodoPagoModel.fromJson(j))
        .where((m) => m.activo)
        .toList();
  }

  /// Porcentaje de IVA vigente de la sucursal (el mismo que aplicará el
  /// backend al emitir). Devuelve null si el endpoint no está disponible,
  /// para que la pantalla decida qué mostrar.
  Future<double?> getIvaVigente(String sucursalId) async {
    try {
      final r = await _dio.get('/api/tasa-iva/sucursal/$sucursalId/vigente');
      final d = r.data['data'];
      if (d == null) return null;
      return d is num ? d.toDouble() : double.tryParse(d.toString());
    } catch (_) {
      return null;
    }
  }

  Future<ClienteModel?> buscarClientePorCedula(String cedula) async {
    try {
      final r = await _dio.get('/api/clientes/cedula/$cedula');
      final d = r.data['data'];
      if (d == null) return null;
      return ClienteModel.fromJson(d);
    } catch (_) {
      return null;
    }
  }

  // Registrar cliente nuevo (queda vinculado a la sucursal del usuario)
  Future<ClienteModel> crearCliente({
    required String nombre,
    String? cedulaRuc,
    String? email,
    String? telefono,
    String? direccion,
  }) async {
    final r = await _dio.post('/api/clientes', data: {
      'nombre': nombre,
      if (cedulaRuc != null && cedulaRuc.isNotEmpty) 'cedulaRuc': cedulaRuc,
      if (email != null && email.isNotEmpty)         'email':     email,
      if (telefono != null && telefono.isNotEmpty)   'telefono':  telefono,
      if (direccion != null && direccion.isNotEmpty) 'direccion': direccion,
    });
    return ClienteModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Actualiza los datos del cliente (la cédula/RUC es su identidad y el
  /// backend no la cambia). El PUT reemplaza email/teléfono/dirección.
  Future<ClienteModel> actualizarCliente({
    required String clienteId,
    required String nombre,
    String? email,
    String? telefono,
    String? direccion,
  }) async {
    final r = await _dio.put('/api/clientes/$clienteId', data: {
      'nombre':    nombre,
      'email':     email,
      'telefono':  telefono,
      'direccion': direccion,
    });
    return ClienteModel.fromJson(r.data['data'] ?? r.data);
  }

  // Emitir factura (requiere aperturaCierreCajaId)
  Future<FacturaModel> emitirFactura({
    required String ordenId,
    required String aperturaCierreCajaId,
    String? clienteId,
    required List<Map<String, dynamic>> detalles, // [{ordenDetalleId, cantidad}]
    double descuento = 0,
    double propina = 0,
    String? notas,
  }) async {
    final r = await _dio.post('/api/facturas', data: {
      'ordenId':               ordenId,
      'aperturaCierreCajaId':  aperturaCierreCajaId,
      if (clienteId != null) 'clienteId': clienteId,
      'detalles':  detalles,
      'descuento': descuento,
      'propina':   propina,
      if (notas != null) 'notas': notas,
    });
    return FacturaModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Historial de comprobantes (facturas y recibos) de la sucursal en un día.
  Future<List<FacturaModel>> getComprobantes(String sucursalId, {DateTime? fecha}) async {
    final r = await _dio.get('/api/facturas/sucursal/$sucursalId', queryParameters: {
      if (fecha != null)
        'fecha': '${fecha.year.toString().padLeft(4, '0')}-'
            '${fecha.month.toString().padLeft(2, '0')}-'
            '${fecha.day.toString().padLeft(2, '0')}',
    });
    final List data = r.data['data'] ?? [];
    return data.map((j) => FacturaModel.fromJson(j)).toList();
  }

  // ---- Facturación electrónica SRI (Factuplan, vía backend) ----

  Future<FacturaModel> getFactura(String facturaVentaId) async {
    final r = await _dio.get('/api/facturas/$facturaVentaId');
    return FacturaModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Reintenta (o dispara) la emisión electrónica en el SRI.
  Future<FacturaModel> emitirSri(String facturaVentaId) async {
    final r = await _dio.post('/api/facturas/$facturaVentaId/sri/emitir');
    return FacturaModel.fromJson(r.data['data'] ?? r.data);
  }

  /// Consulta el estado en el SRI y lo sincroniza en el backend.
  Future<FacturaModel> getEstadoSri(String facturaVentaId) async {
    final r = await _dio.get('/api/facturas/$facturaVentaId/sri/estado');
    return FacturaModel.fromJson(r.data['data'] ?? r.data);
  }

  /// URL temporal del RIDE (PDF, expira en ~5 min) y URL de verificación.
  Future<({String? url, String? previewUrl})> getPdfSri(String facturaVentaId) async {
    final r = await _dio.get('/api/facturas/$facturaVentaId/sri/pdf');
    final d = r.data['data'] ?? {};
    return (url: d['url']?.toString(), previewUrl: d['previewUrl']?.toString());
  }

  // Registrar pago de factura
  Future<FacturaModel> registrarPago({
    required String facturaVentaId,
    required String metodoPagoId,
    required double monto,
    String? referencia,
  }) async {
    final r = await _dio.post('/api/facturas/$facturaVentaId/pagos', data: {
      'metodoPagoId': metodoPagoId,
      'monto':        monto,
      if (referencia != null && referencia.isNotEmpty) 'referencia': referencia,
    });
    return FacturaModel.fromJson(r.data['data'] ?? r.data);
  }
}
