class ApiConstants {
  ApiConstants._();

  // Emulador Android: usar 'http://10.0.2.2:8080'
  static const String baseUrl = 'https://api-restaurante.soprintserver.duckdns.org';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Auth
  static const String login = '/api/auth/login';
  static const String refresh = '/api/auth/refresh';

  // Mesas
  static const String mesas = '/api/mesas';
  static const String mesasBySalon = '/api/mesas/salon';
  static const String mesasBySucursal = '/api/mesas/sucursal';

  // Salones
  static const String salones = '/api/salones';
  static const String saloneBySucursal = '/api/salones/sucursal';

  // Órdenes
  static const String ordenes = '/api/ordenes';
  static const String ordenesActivas = '/api/ordenes/sucursal';

  // Platos
  static const String platosBySucursal = '/api/platos/sucursal';

  // Categorías
  static const String categorias = '/api/categorias';

  // Factura
  static const String facturas = '/api/facturas';

  // Caja
  static const String caja = '/api/caja';
  static const String cajaAbrir = '/api/caja/abrir';

  // Clientes
  static const String clientes = '/api/clientes';
  static const String clientesPorCedula = '/api/clientes/cedula';

  // Reportes
  static const String resumenDiario = '/api/reportes/resumen-diario';

  // Métodos de pago
  static const String metodosPago = '/api/metodos-pago/activos';

  // Menú público QR
  static const String menuPublico = '/api/menu/publico';

  // ── Configuración (superadmin / admin) ──────────────────────────────────────
  static const String tenants             = '/api/tenants';
  static const String restaurants         = '/api/restaurants';
  static const String sucursales          = '/api/sucursales';
  static const String tasaIva             = '/api/tasa-iva';
  static const String subcategorias       = '/api/subcategorias';
  static const String platos              = '/api/platos';
  static const String usuarios            = '/api/usuarios';
  static const String roles               = '/api/roles';
  static const String impresoras          = '/api/impresoras';
}
