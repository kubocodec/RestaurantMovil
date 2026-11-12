import '../../../core/models/caja_model.dart';
import '../../../core/models/factura_model.dart';
import '../../../core/models/orden_model.dart';
import '../../inventario/data/inventario_repository.dart';
import '../data/reportes_repository.dart';
import '../data/resumen_periodo_model.dart';

/// Una sucursal a exportar. Solo el id y el nombre: los ids vienen siempre
/// de la pantalla, nunca del AuthBloc (el superadmin exporta restaurantes que
/// no son su tenant).
typedef SucursalExcel = ({String id, String nombre});

enum GrupoExcel {
  ventas('Ventas'),
  porDia('Detalle día por día'),
  perdidas('Pérdidas'),
  inventario('Inventario');

  final String titulo;
  const GrupoExcel(this.titulo);
}

/// Cada sección sale en su propia hoja (Cierres trae dos: cierres y
/// movimientos). El orden del enum es el orden de las hojas.
enum SeccionExcel {
  resumen('Resumen', GrupoExcel.ventas),
  platos('Platos vendidos', GrupoExcel.ventas),
  categorias('Categorías', GrupoExcel.ventas),
  sinVenta('Platos sin ventas', GrupoExcel.ventas),
  diaHora('Día y hora', GrupoExcel.ventas),
  tipo('Mesa y para llevar', GrupoExcel.ventas),
  metodosPago('Métodos de pago', GrupoExcel.ventas),
  personal('Personal y propinas', GrupoExcel.ventas),
  ventasDia('Ventas por día', GrupoExcel.porDia),
  comprobantes('Comprobantes', GrupoExcel.porDia),
  detalleVendido('Detalle de lo vendido', GrupoExcel.porDia),
  cierres('Cierres y movimientos de caja', GrupoExcel.porDia),
  cortesias('Cortesías', GrupoExcel.perdidas),
  anuladas('Órdenes anuladas', GrupoExcel.perdidas),
  insumos('Stock de insumos', GrupoExcel.inventario),
  platosStock('Stock de platos', GrupoExcel.inventario),
  compras('Compras del período', GrupoExcel.inventario),
  proveedores('Proveedores', GrupoExcel.inventario);

  final String titulo;
  final GrupoExcel grupo;
  const SeccionExcel(this.titulo, this.grupo);

  /// Necesitan una llamada por día y por sucursal.
  bool get esPorDia => grupo == GrupoExcel.porDia;

  /// Salen del resumen del período (una sola llamada).
  bool get delResumen => grupo == GrupoExcel.ventas;

  bool get esInventario => grupo == GrupoExcel.inventario;

  /// Desde Reportes se puede pedir todo; desde Inventario, solo lo suyo.
  static Set<SeccionExcel> get deReportes => values.toSet();

  static Set<SeccionExcel> get deInventario => values.where((s) => s.esInventario).toSet();
}

/// Todo lo reunido para armar el libro. Lo que no se pidió o no se pudo
/// cargar queda vacío o null; `notas` explica cada hueco.
class DatosExportacion {
  final String alcance;
  final DateTime desde;
  final DateTime hasta;
  final DateTime generado;
  final Set<SeccionExcel> secciones;
  final bool variasSucursales;

  ResumenPeriodoModel? resumen;
  final List<(String, DateTime, ResumenDiarioModel)> ventasDia = [];
  final List<(String, FacturaModel)> comprobantes = [];
  final List<(String, CierreDetalladoModel)> cierres = [];
  final List<(String, CortesiaItemModel)> cortesias = [];
  final List<(String, OrdenModel)> anuladas = [];
  final List<(String, InsumoModel)> insumos = [];
  final List<(String, InventarioItemModel)> platosStock = [];
  final List<(String, CompraModel)> compras = [];
  final List<ProveedorModel> proveedores = [];

  /// Sucursales que llevan inventario. Vacío = ninguna: no hay hojas de inventario.
  final Set<String> conInventario = {};

  /// Avisos para la hoja Resumen: límites aplicados y secciones que fallaron.
  final List<String> notas = [];

  DatosExportacion({
    required this.alcance,
    required this.desde,
    required this.hasta,
    required this.secciones,
    required this.variasSucursales,
    DateTime? generado,
  }) : generado = generado ?? DateTime.now();

  bool pide(SeccionExcel s) => secciones.contains(s);
}
