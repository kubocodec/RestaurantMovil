import 'dart:convert';
import 'dart:io';

import '../models/caja_model.dart';
import '../models/factura_model.dart';
import '../models/orden_model.dart';

/// Resultado de la impresión de una comanda.
class ResultadoImpresion {
  final String impresora;
  final bool ok;
  final String? error;
  const ResultadoImpresion(this.impresora, this.ok, [this.error]);
}

/// Línea de detalle para el recibo/factura impresa.
class ReciboItem {
  final String nombre;
  final int cantidad;
  final double subtotal;
  const ReciboItem({required this.nombre, required this.cantidad, required this.subtotal});
}

/// Imprime comandas en impresoras térmicas de red (ESC/POS por TCP, puerto
/// 9100 por defecto). Sin dependencias: genera los bytes ESC/POS a mano.
class ComandaPrinter {
  // Comandos ESC/POS
  static const _init = [0x1B, 0x40];
  static const _boldOn = [0x1B, 0x45, 0x01];
  static const _boldOff = [0x1B, 0x45, 0x00];
  static const _doubleSize = [0x1D, 0x21, 0x11];
  static const _normalSize = [0x1D, 0x21, 0x00];
  static const _center = [0x1B, 0x61, 0x01];
  static const _left = [0x1B, 0x61, 0x00];
  static const _cut = [0x1D, 0x56, 0x42, 0x00];
  static const _feed = [0x1B, 0x64, 0x04]; // 4 líneas antes del corte

  /// Agrupa los detalles por impresora y envía una comanda a cada una.
  /// Los detalles sin impresora asignada se ignoran (quedan solo en el KDS).
  /// Nunca lanza: devuelve el resultado por impresora para informar al mesero.
  static Future<List<ResultadoImpresion>> imprimirComandas({
    required String mesa,
    required int numeroOrden,
    required String mesero,
    required List<DetalleOrdenModel> detalles,
  }) async {
    final porImpresora = <String, List<DetalleOrdenModel>>{};
    for (final d in detalles) {
      final ip = d.impresoraIp;
      if (ip == null || ip.isEmpty) continue;
      porImpresora.putIfAbsent('$ip:${d.impresoraPuerto ?? 9100}', () => []).add(d);
    }

    final resultados = <ResultadoImpresion>[];
    for (final entry in porImpresora.entries) {
      final partes = entry.key.split(':');
      final nombre = entry.value.first.impresoraNombre ?? partes[0];
      try {
        await _imprimir(
          ip: partes[0],
          puerto: int.tryParse(partes[1]) ?? 9100,
          mesa: mesa,
          numeroOrden: numeroOrden,
          mesero: mesero,
          detalles: entry.value,
        );
        resultados.add(ResultadoImpresion(nombre, true));
      } catch (e) {
        resultados.add(ResultadoImpresion(nombre, false, e.toString()));
      }
    }
    return resultados;
  }

  static Future<void> _imprimir({
    required String ip,
    required int puerto,
    required String mesa,
    required int numeroOrden,
    required String mesero,
    required List<DetalleOrdenModel> detalles,
  }) async {
    final socket = await Socket.connect(ip, puerto, timeout: const Duration(seconds: 5));
    try {
      final bytes = <int>[
        ..._init,
        ..._center, ..._doubleSize, ..._boldOn,
        ..._texto('COMANDA #$numeroOrden\n'),
        ..._normalSize,
        ..._texto('$mesa\n'),
        ..._boldOff, ..._left,
        ..._texto('${'-' * 32}\n'),
        ..._texto('Hora: ${_horaActual()}   Mesero: $mesero\n'),
        ..._texto('${'-' * 32}\n'),
      ];
      for (final d in detalles) {
        bytes.addAll(_boldOn);
        bytes.addAll(_texto('${d.cantidad} x ${d.nombrePlato}\n'));
        bytes.addAll(_boldOff);
        final obs = d.observaciones;
        if (obs != null && obs.isNotEmpty) {
          bytes.addAll(_texto('   >> $obs\n'));
        }
      }
      bytes.addAll(_texto('${'-' * 32}\n'));
      bytes.addAll(_feed);
      bytes.addAll(_cut);

      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  /// Imprime el recibo o factura del cliente en la impresora indicada,
  /// con la cabecera del restaurant y su sucursal.
  static Future<void> imprimirRecibo({
    required String ip,
    int puerto = 9100,
    required FacturaModel factura,
    required List<ReciboItem> items,
    required String metodoPago,
    required bool esFactura,
  }) async {
    final socket = await Socket.connect(ip, puerto, timeout: const Duration(seconds: 5));
    try {
      final f = factura;
      final bytes = <int>[
        ..._init,
        // ── Cabecera: restaurant y sucursal ──
        ..._center, ..._doubleSize, ..._boldOn,
        ..._texto('${f.nombreRestaurant.isNotEmpty ? f.nombreRestaurant : f.nombreSucursal}\n'),
        ..._normalSize, ..._boldOff,
        if (f.razonSocial?.isNotEmpty ?? false) ..._texto('${f.razonSocial}\n'),
        if (f.rucSucursal?.isNotEmpty ?? false) ..._texto('RUC: ${f.rucSucursal}\n'),
        if (f.nombreSucursal.isNotEmpty) ..._texto('${f.nombreSucursal}\n'),
        if (f.direccionSucursal?.isNotEmpty ?? false) ..._texto('${f.direccionSucursal}\n'),
        if (f.telefonoSucursal?.isNotEmpty ?? false) ..._texto('Tel: ${f.telefonoSucursal}\n'),
        ..._left,
        ..._texto('${'-' * 32}\n'),
        ..._boldOn,
        ..._texto('${esFactura ? 'FACTURA' : 'RECIBO'} No. ${f.numeroFactura}\n'),
        ..._boldOff,
        ..._texto('Fecha: ${_fechaHora(f.fecha.toLocal())}\n'),
        ..._texto('Orden: #${f.numeroOrden}\n'),
        ..._texto('Cliente: ${f.nombreCliente ?? 'Consumidor Final'}\n'),
        if (f.cedulaRucCliente?.isNotEmpty ?? false)
          ..._texto('CI/RUC: ${f.cedulaRucCliente}\n'),
        ..._texto('${'-' * 32}\n'),
      ];
      for (final it in items) {
        bytes.addAll(_texto(_lineaMonto('${it.cantidad} x ${it.nombre}', it.subtotal)));
      }
      bytes.addAll(_texto('${'-' * 32}\n'));
      bytes.addAll(_texto(_lineaMonto('Subtotal', f.subtotal)));
      if (f.descuento > 0) bytes.addAll(_texto(_lineaMonto('Descuento', -f.descuento)));
      bytes.addAll(_texto(_lineaMonto('IVA ${f.ivaPorcentaje.toStringAsFixed(0)}%', f.iva)));
      if (f.propina > 0) bytes.addAll(_texto(_lineaMonto('Propina', f.propina)));
      bytes.addAll(_boldOn);
      bytes.addAll(_texto(_lineaMonto('TOTAL', f.total)));
      bytes.addAll(_boldOff);
      bytes.addAll(_texto('Pago: $metodoPago\n'));
      bytes.addAll(_texto('${'-' * 32}\n'));
      bytes.addAll(_center);
      bytes.addAll(_texto('¡Gracias por su visita!\n'));
      bytes.addAll(_left);
      bytes.addAll(_feed);
      bytes.addAll(_cut);

      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  /// Imprime el ticket de cierre de caja con todo el detalle del turno:
  /// arqueo, ventas por método de pago, cada ingreso/egreso y ventas por
  /// plato. Sirve para el cierre del cajero y para reimprimir desde
  /// Reportes.
  static Future<void> imprimirCierreCaja({
    required String ip,
    int puerto = 9100,
    required CierreDetalladoModel cierre,
    String? nombreSucursal,
  }) async {
    final socket = await Socket.connect(ip, puerto, timeout: const Duration(seconds: 5));
    try {
      final c = cierre;
      final bytes = <int>[
        ..._init,
        ..._center, ..._doubleSize, ..._boldOn,
        ..._texto('CIERRE DE CAJA\n'),
        ..._normalSize,
        ..._texto('${c.nombreCaja}\n'),
        ..._boldOff,
        if (nombreSucursal != null && nombreSucursal.isNotEmpty)
          ..._texto('$nombreSucursal\n'),
        ..._left,
        ..._texto('${'-' * 32}\n'),
        ..._texto('Apertura: ${_fechaHora(c.fechaApertura.toLocal())}\n'),
        ..._texto('  por ${c.usuarioApertura}\n'),
        if (c.fechaCierre != null) ...[
          ..._texto('Cierre:   ${_fechaHora(c.fechaCierre!.toLocal())}\n'),
          if (c.usuarioCierre?.isNotEmpty ?? false)
            ..._texto('  por ${c.usuarioCierre}\n'),
        ],
        ..._texto('${'-' * 32}\n'),
        // ── Arqueo ──
        ..._boldOn, ..._texto('ARQUEO (EFECTIVO)\n'), ..._boldOff,
        ..._texto(_lineaMonto('Monto inicial', c.montoInicial)),
        ..._texto(_lineaMonto('+ Ventas efectivo', c.totalVentasEfectivo)),
        ..._texto(_lineaMonto('+ Otros ingresos', c.totalIngresos)),
        ..._texto(_lineaMonto('- Egresos', -c.totalEgresos)),
        ..._texto(_lineaMonto('= Esperado', c.montoEsperado)),
        if (c.montoContado != null)
          ..._texto(_lineaMonto('Contado', c.montoContado!)),
      ];
      final dif = c.diferencia;
      if (dif != null) {
        final etiqueta = dif.abs() < 0.01
            ? 'CAJA CUADRADA'
            : dif > 0 ? 'SOBRANTE' : 'FALTANTE';
        bytes.addAll(_boldOn);
        bytes.addAll(_texto(_lineaMonto(etiqueta, dif)));
        bytes.addAll(_boldOff);
      }
      bytes.addAll(_texto('${'-' * 32}\n'));

      // ── Ventas por método de pago ──
      bytes.addAll(_boldOn);
      bytes.addAll(_texto('VENTAS POR METODO DE PAGO\n'));
      bytes.addAll(_boldOff);
      if (c.ventasPorMetodo.isEmpty) {
        bytes.addAll(_texto('(sin ventas)\n'));
      } else {
        for (final m in c.ventasPorMetodo) {
          bytes.addAll(_texto(_lineaMonto('${m.metodo} (${m.numPagos})', m.total)));
        }
        bytes.addAll(_boldOn);
        bytes.addAll(_texto(_lineaMonto(
            'TOTAL (${c.totalFacturas} fact.)', c.totalVentas)));
        bytes.addAll(_boldOff);
      }
      bytes.addAll(_texto('${'-' * 32}\n'));

      // ── Ingresos extra ──
      bytes.addAll(_boldOn);
      bytes.addAll(_texto('INGRESOS EXTRA (${c.ingresos.length})\n'));
      bytes.addAll(_boldOff);
      if (c.ingresos.isEmpty) {
        bytes.addAll(_texto('(ninguno)\n'));
      } else {
        for (final m in c.ingresos) {
          bytes.addAll(_texto(_lineaMonto(
              m.concepto.isEmpty ? 'Sin concepto' : m.concepto, m.monto)));
        }
        bytes.addAll(_texto(_lineaMonto('Total ingresos', c.totalIngresos)));
      }
      bytes.addAll(_texto('${'-' * 32}\n'));

      // ── Egresos ──
      bytes.addAll(_boldOn);
      bytes.addAll(_texto('EGRESOS / GASTOS (${c.egresos.length})\n'));
      bytes.addAll(_boldOff);
      if (c.egresos.isEmpty) {
        bytes.addAll(_texto('(ninguno)\n'));
      } else {
        for (final m in c.egresos) {
          bytes.addAll(_texto(_lineaMonto(
              m.concepto.isEmpty ? 'Sin concepto' : m.concepto, m.monto)));
        }
        bytes.addAll(_texto(_lineaMonto('Total egresos', c.totalEgresos)));
      }
      bytes.addAll(_texto('${'-' * 32}\n'));

      // ── Ventas por plato ──
      if (c.ventasPorPlato.isNotEmpty) {
        bytes.addAll(_boldOn);
        bytes.addAll(_texto('VENTAS POR PLATO\n'));
        bytes.addAll(_boldOff);
        for (final v in c.ventasPorPlato) {
          bytes.addAll(_texto(_lineaMonto('${v.cantidad} x ${v.plato}', v.total)));
        }
        bytes.addAll(_texto('${'-' * 32}\n'));
      }

      if ((c.observaciones ?? '').trim().isNotEmpty) {
        bytes.addAll(_texto('Obs: ${c.observaciones}\n'));
        bytes.addAll(_texto('${'-' * 32}\n'));
      }

      bytes.addAll(_center);
      bytes.addAll(_texto('Impreso: ${_fechaHora(DateTime.now())}\n'));
      bytes.addAll(_left);
      bytes.addAll(_feed);
      bytes.addAll(_cut);

      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  /// Concepto a la izquierda y monto alineado a la derecha (32 columnas).
  static String _lineaMonto(String concepto, double monto) {
    final valor = monto.toStringAsFixed(2);
    var nombre = concepto;
    final ancho = 32 - valor.length - 1;
    if (nombre.length > ancho) nombre = nombre.substring(0, ancho);
    return '$nombre${' ' * (32 - nombre.length - valor.length)}$valor\n';
  }

  static String _fechaHora(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Latin-1 cubre acentos y ñ en la página de códigos por defecto (CP437/850
  /// difieren en algunos signos, pero letras acentuadas comunes coinciden).
  static List<int> _texto(String s) => latin1.encode(_sinCaracteresRaros(s));

  static String _sinCaracteresRaros(String s) =>
      s.replaceAll(RegExp(r'[^\x20-\x7EáéíóúÁÉÍÓÚñÑüÜ¿¡°\n]'), '?');

  static String _horaActual() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }
}
