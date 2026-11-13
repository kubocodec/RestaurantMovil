import '../../../core/models/caja_model.dart';
import '../../../core/network/api_client.dart';
import '../../facturacion/data/facturacion_repository.dart';
import '../../inventario/data/inventario_repository.dart';
import '../data/reportes_repository.dart';
import 'datos_exportacion.dart';

typedef AvisoProgreso = void Function(String paso, int hechas, int total);

/// Se marca desde el diálogo; el recolector la mira entre llamada y llamada.
class CancelacionExportacion {
  bool cancelada = false;
}

class ExportacionCancelada implements Exception {
  const ExportacionCancelada();
}

class _Tarea {
  final String paso;
  final Future<void> Function() hacer;
  const _Tarea(this.paso, this.hacer);
}

/// Reúne con los repositorios de siempre lo que va al Excel. No hace llamadas
/// HTTP propias ni toca el servidor: solo lee lo que la app ya lee.
class RecolectorExcel {
  /// Comprobantes, ventas y cierres se piden un día a la vez. Un mes son unas
  /// 90 llamadas; un año serían más de mil contra el servidor de producción,
  /// así que pasado este límite esas hojas no se arman y la hoja Resumen lo
  /// explica. Quitarlo pide un endpoint nuevo en el backend.
  static const maxDiasDetalle = 31;
  static const maxDiasPorSucursales = 62;

  /// Cada compra se pide aparte (el listado viene sin sus ítems).
  static const maxCompras = 200;

  /// Llamadas a la vez. Más acelera poco y carga al servidor de todos.
  static const _paralelo = 3;

  final ReportesRepository _reportes;
  final FacturacionRepository _facturas;
  final InventarioRepository _inventario;

  RecolectorExcel({
    ReportesRepository? reportes,
    FacturacionRepository? facturas,
    InventarioRepository? inventario,
  })  : _reportes = reportes ?? ReportesRepository(),
        _facturas = facturas ?? FacturacionRepository(),
        _inventario = inventario ?? InventarioRepository();

  /// Días del período, sin importar la hora de [desde] y [hasta]. Se suma
  /// día por día con el constructor (no con Duration) para que un cambio de
  /// hora no salte ni repita una fecha.
  static List<DateTime> diasEntre(DateTime desde, DateTime hasta) {
    final fin = DateTime(hasta.year, hasta.month, hasta.day);
    final dias = <DateTime>[];
    for (var i = 0;; i++) {
      final d = DateTime(desde.year, desde.month, desde.day + i);
      if (d.isAfter(fin)) break;
      dias.add(d);
    }
    return dias;
  }

  /// Si el detalle por día entra en los límites.
  static bool detallePorDiaPermitido(int dias, int sucursales) =>
      dias <= maxDiasDetalle && dias * sucursales <= maxDiasPorSucursales;

  Future<DatosExportacion> recolectar({
    required String restaurantId,
    required List<SucursalExcel> sucursales,
    required bool todas,
    required String alcance,
    required DateTime desde,
    required DateTime hasta,
    required Set<SeccionExcel> secciones,
    required AvisoProgreso progreso,
    required CancelacionExportacion cancelacion,
  }) async {
    final dias = diasEntre(desde, hasta);
    String? notaLimite;
    if (secciones.any((s) => s.esPorDia) && !detallePorDiaPermitido(dias.length, sucursales.length)) {
      final pedidas = secciones.where((s) => s.esPorDia).map((s) => s.titulo).join(', ');
      notaLimite = 'No se incluyó el detalle día por día ($pedidas): el período tiene '
          '${dias.length} días${sucursales.length > 1 ? ' y ${sucursales.length} sucursales' : ''}. '
          'Para tenerlo, descarga de a un mes y de a una sucursal.';
      secciones = secciones.where((s) => !s.esPorDia).toSet();
    }

    final datos = DatosExportacion(
      alcance: alcance,
      desde: desde,
      hasta: hasta,
      secciones: secciones,
      variasSucursales: sucursales.length > 1,
    );
    if (notaLimite != null) datos.notas.add(notaLimite);

    var hechas = 0;
    var total = 0;

    Future<void> correr(List<_Tarea> tareas) async {
      total += tareas.length;
      var siguiente = 0;
      Future<void> trabajador() async {
        while (siguiente < tareas.length) {
          if (cancelacion.cancelada) throw const ExportacionCancelada();
          final t = tareas[siguiente++];
          progreso(t.paso, hechas, total);
          try {
            await t.hacer();
          } catch (e) {
            if (e is ExportacionCancelada) rethrow;
            datos.notas.add('No se pudo cargar: ${t.paso} (${ApiClient.parseError(e)}).');
          }
          hechas++;
          progreso(t.paso, hechas, total);
        }
      }

      await Future.wait([for (var i = 0; i < _paralelo; i++) trabajador()]);
      if (cancelacion.cancelada) throw const ExportacionCancelada();
    }

    // 1) ¿Qué sucursales llevan inventario? Solo si se pidió alguna hoja de inventario.
    if (secciones.any((s) => s.esInventario)) {
      await correr([
        for (final s in sucursales)
          _Tarea('Revisando el inventario de ${s.nombre}', () async {
            final alertas = await _inventario.getAlertas(s.id);
            if (alertas.habilitado) datos.conInventario.add(s.id);
          }),
      ]);
      if (datos.conInventario.isEmpty) {
        datos.notas.add('No se incluyó el inventario: ${sucursales.length > 1 ? 'ninguna sucursal lo lleva' : 'la sucursal no lo lleva'}.');
      }
    }

    // 2) Todo lo demás.
    final ventasDia = <(String, DateTime, ResumenDiarioModel)>[];
    final cierresPorId = <String, (String, CierreDetalladoModel)>{};
    final listadoCompras = <(String, String, DateTime)>[]; // sucursal, compraId, fecha
    final tareas = <_Tarea>[];

    if (secciones.any((s) => s.delResumen)) {
      tareas.add(_Tarea('Resumen del período', () async {
        datos.resumen = await _reportes.getResumenPeriodo(
          sucursalId: todas ? null : sucursales.first.id,
          restaurantId: restaurantId,
          desde: desde,
          hasta: hasta,
        );
      }));
    }

    for (final s in sucursales) {
      for (final d in dias) {
        final f = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
        final de = sucursales.length > 1 ? ' de ${s.nombre}' : '';
        if (secciones.contains(SeccionExcel.ventasDia)) {
          tareas.add(_Tarea('Ventas del $f$de', () async {
            ventasDia.add((s.nombre, d, await _reportes.getResumenDiario(s.id, fecha: d)));
          }));
        }
        if (secciones.contains(SeccionExcel.comprobantes) ||
            secciones.contains(SeccionExcel.detalleVendido)) {
          tareas.add(_Tarea('Comprobantes del $f$de', () async {
            final lista = await _facturas.getComprobantes(s.id, fecha: d);
            datos.comprobantes.addAll(lista.map((c) => (s.nombre, c)));
          }));
        }
        if (secciones.contains(SeccionExcel.cierres)) {
          tareas.add(_Tarea('Cierres de caja del $f$de', () async {
            final r = await _reportes.getCierresCajaDia(s.id, fecha: d);
            // Un turno que cruza la medianoche puede salir en dos días.
            for (final c in r.cierres) {
              cierresPorId[c.aperturaCierreCajaId] = (s.nombre, c);
            }
          }));
        }
      }

      final de = sucursales.length > 1 ? ' de ${s.nombre}' : '';
      if (secciones.contains(SeccionExcel.cortesias)) {
        tareas.add(_Tarea('Cortesías$de', () async {
          final r = await _reportes.getCortesias(s.id, desde: desde, hasta: hasta);
          datos.cortesias.addAll(r.items.map((c) => (s.nombre, c)));
        }));
      }
      if (secciones.contains(SeccionExcel.anuladas)) {
        tareas.add(_Tarea('Órdenes anuladas$de', () async {
          final r = await _reportes.getOrdenesAnuladas(s.id, desde: desde, hasta: hasta);
          datos.anuladas.addAll(r.ordenes.map((o) => (s.nombre, o)));
        }));
      }

      if (!datos.conInventario.contains(s.id)) continue;
      if (secciones.contains(SeccionExcel.insumos)) {
        tareas.add(_Tarea('Insumos$de', () async {
          final l = await _inventario.getInsumos(s.id, incluirInactivos: true);
          datos.insumos.addAll(l.map((i) => (s.nombre, i)));
        }));
      }
      if (secciones.contains(SeccionExcel.platosStock)) {
        tareas.add(_Tarea('Stock de platos$de', () async {
          final l = await _inventario.getInventario(s.id);
          datos.platosStock.addAll(l.map((i) => (s.nombre, i)));
        }));
      }
      if (secciones.contains(SeccionExcel.compras)) {
        tareas.add(_Tarea('Compras$de', () async {
          final l = await _inventario.getCompras(s.id, desde: desde, hasta: hasta);
          listadoCompras.addAll(l.map((c) => (s.id, c.compraId, c.fecha)));
        }));
      }
    }

    // Proveedores son del restaurante: con una sucursal que lleve inventario alcanza.
    if (secciones.contains(SeccionExcel.proveedores) && datos.conInventario.isNotEmpty) {
      final id = datos.conInventario.first;
      tareas.add(_Tarea('Proveedores', () async {
        datos.proveedores.addAll(await _inventario.getProveedores(id, incluirInactivos: true));
      }));
    }

    await correr(tareas);

    // 3) Cada compra con sus ítems.
    if (listadoCompras.isNotEmpty) {
      listadoCompras.sort((a, b) => b.$3.compareTo(a.$3));
      if (listadoCompras.length > maxCompras) {
        datos.notas.add('Compras: se incluyeron las $maxCompras más recientes de ${listadoCompras.length}.');
      }
      final nombres = {for (final s in sucursales) s.id: s.nombre};
      final comprasPorId = <String, (String, CompraModel)>{};
      await correr([
        for (final (sucId, compraId, _) in listadoCompras.take(maxCompras))
          _Tarea('Detalle de compras', () async {
            final c = await _inventario.getCompra(sucId, compraId);
            comprasPorId[compraId] = (nombres[sucId] ?? '', c);
          }),
      ]);
      datos.compras.addAll(comprasPorId.values);
    }

    // Orden estable, sin importar en qué orden respondió el servidor.
    ventasDia.sort((a, b) {
      final f = a.$2.compareTo(b.$2);
      return f != 0 ? f : a.$1.compareTo(b.$1);
    });
    datos.ventasDia.addAll(ventasDia);
    datos.comprobantes.sort((a, b) => a.$2.fecha.compareTo(b.$2.fecha));
    datos.cierres
      ..addAll(cierresPorId.values)
      ..sort((a, b) => a.$2.fechaApertura.compareTo(b.$2.fechaApertura));
    datos.cortesias.sort((a, b) => a.$2.fecha.compareTo(b.$2.fecha));
    datos.anuladas.sort((a, b) =>
        (a.$2.fechaCierre ?? a.$2.fechaCreacion).compareTo(b.$2.fechaCierre ?? b.$2.fechaCreacion));
    datos.compras.sort((a, b) => a.$2.fecha.compareTo(b.$2.fecha));
    return datos;
  }
}
