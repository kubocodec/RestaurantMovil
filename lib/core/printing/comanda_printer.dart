import 'dart:convert';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/caja_model.dart';
import '../models/factura_model.dart';
import '../models/orden_model.dart';

/// Resultado de la impresión de una comanda.
class ResultadoImpresion {
  final String impresora;
  final bool ok;
  final String? error;
  /// Vía por la que se imprimió: 'red' o 'Bluetooth' (solo cuando ok).
  final String? via;
  const ResultadoImpresion(this.impresora, this.ok, {this.error, this.via});
}

/// Línea de detalle para el recibo/factura impresa.
class ReciboItem {
  final String nombre;
  final int cantidad;
  final double subtotal;
  const ReciboItem({required this.nombre, required this.cantidad, required this.subtotal});
}

/// Imprime en impresoras térmicas ESC/POS. Primero intenta por red (TCP,
/// puerto 9100 por defecto) y, si falla y la impresora tiene una MAC
/// Bluetooth configurada, reintenta por Bluetooth. Los bytes ESC/POS se
/// generan a mano y son los mismos por ambas vías.
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

  /// Columnas en fuente normal. Las impresoras del negocio son de 80mm
  /// (48 columnas); para papel de 58mm cambiar a 32.
  static const int _cols = 48;

  /// Agrupa los detalles por impresora y envía una comanda a cada una.
  /// Los detalles sin impresora asignada (sin IP ni Bluetooth) se ignoran
  /// (quedan solo en el KDS).
  /// Nunca lanza: devuelve el resultado por impresora para informar al mesero.
  static Future<List<ResultadoImpresion>> imprimirComandas({
    required String mesa,
    required int numeroOrden,
    required String mesero,
    required List<DetalleOrdenModel> detalles,
    bool esReimpresion = false,
  }) async {
    final porImpresora = <String, List<DetalleOrdenModel>>{};
    for (final d in detalles) {
      final ip = d.impresoraIp ?? '';
      final mac = d.impresoraMac ?? '';
      if (ip.isEmpty && mac.isEmpty) continue;
      porImpresora
          .putIfAbsent('$ip|${d.impresoraPuerto ?? 9100}|$mac', () => [])
          .add(d);
    }

    final resultados = <ResultadoImpresion>[];
    for (final entry in porImpresora.entries) {
      final primero = entry.value.first;
      final nombre = primero.impresoraNombre ?? primero.impresoraIp ?? 'Impresora';
      try {
        final via = await _enviar(
          ip: primero.impresoraIp,
          puerto: primero.impresoraPuerto ?? 9100,
          mac: primero.impresoraMac,
          bytes: _bytesComanda(
            mesa: mesa,
            numeroOrden: numeroOrden,
            mesero: mesero,
            detalles: entry.value,
            esReimpresion: esReimpresion,
          ),
        );
        resultados.add(ResultadoImpresion(nombre, true, via: via));
      } catch (e) {
        resultados.add(ResultadoImpresion(nombre, false, error: e.toString()));
      }
    }
    return resultados;
  }

  static bool _esParaLlevar(DetalleOrdenModel d) => d.tipoServicio == 'PARA_LLEVAR';

  static List<int> _bytesComanda({
    required String mesa,
    required int numeroOrden,
    required String mesero,
    required List<DetalleOrdenModel> detalles,
    bool esReimpresion = false,
  }) {
    // Si toda la comanda es para llevar se anuncia en grande en la cabecera;
    // si es mixta (mesa + algunos platos para llevar) se marca cada plato.
    final todoParaLlevar = detalles.every(_esParaLlevar);
    final bytes = <int>[
      ..._init,
      ..._center, ..._doubleSize, ..._boldOn,
      ..._texto('COMANDA #$numeroOrden\n'),
      // Cocina debe saber que ya recibió esta comanda: no es un pedido nuevo
      if (esReimpresion) ..._texto('* REIMPRESION *\n'),
      if (todoParaLlevar) ..._texto('* PARA LLEVAR *\n'),
      ..._normalSize,
      // La mesa se imprime siempre que exista (aun si todo va para llevar,
      // el mesero necesita saber a dónde entregar lo empacado); solo se
      // omite cuando la orden no tiene mesa (ya lo dice el banner).
      if (mesa != 'Para llevar') ..._texto('$mesa\n'),
      ..._boldOff, ..._left,
      ..._texto('${'-' * _cols}\n'),
      ..._texto('Hora: ${_horaActual()}   Mesero: $mesero\n'),
      ..._texto('${'-' * _cols}\n'),
    ];
    for (final d in detalles) {
      bytes.addAll(_boldOn);
      bytes.addAll(_texto('${d.cantidad} x ${d.nombrePlato}\n'));
      if (!todoParaLlevar && _esParaLlevar(d)) {
        bytes.addAll(_texto('   >> PARA LLEVAR\n'));
      }
      bytes.addAll(_boldOff);
      final obs = d.observaciones;
      if (obs != null && obs.isNotEmpty) {
        bytes.addAll(_texto('   >> $obs\n'));
      }
    }
    bytes.addAll(_texto('${'-' * _cols}\n'));
    bytes.addAll(_feed);
    bytes.addAll(_cut);
    return bytes;
  }

  /// Imprime un ticket corto de prueba para verificar la conexión al
  /// configurar la impresora. Devuelve la vía usada ('red' o 'Bluetooth').
  static Future<String> imprimirPrueba({
    String? ip,
    int puerto = 9100,
    String? mac,
    required String nombre,
    String? area,
  }) {
    final bytes = <int>[
      ..._init,
      ..._center, ..._doubleSize, ..._boldOn,
      ..._texto('PRUEBA DE\nIMPRESION\n'),
      ..._normalSize, ..._boldOff,
      ..._left,
      ..._texto('${'-' * _cols}\n'),
      ..._texto('Impresora: $nombre\n'),
      if (area != null && area.isNotEmpty) ..._texto('Area: $area\n'),
      if (ip != null && ip.isNotEmpty) ..._texto('Red: $ip:$puerto\n'),
      if (mac != null && mac.isNotEmpty) ..._texto('Bluetooth: $mac\n'),
      ..._texto('Fecha: ${_fechaHora(DateTime.now())}\n'),
      ..._texto('${'-' * _cols}\n'),
      ..._center, ..._boldOn,
      ..._texto('CONEXION OK\n'),
      ..._boldOff, ..._left,
      ..._feed,
      ..._cut,
    ];
    return _enviar(ip: ip, puerto: puerto, mac: mac, bytes: bytes);
  }

  // ── Transporte: red con respaldo Bluetooth ────────────────────────────

  /// Envía los bytes a la impresora. Intenta primero por red (si tiene IP)
  /// y, si falla, por Bluetooth (si tiene MAC). Devuelve la vía usada
  /// ('red' o 'Bluetooth') o lanza con el detalle de ambos errores.
  static Future<String> _enviar({
    String? ip,
    int puerto = 9100,
    String? mac,
    required List<int> bytes,
  }) async {
    final tieneIp = ip != null && ip.isNotEmpty;
    final tieneMac = mac != null && mac.isNotEmpty;
    if (!tieneIp && !tieneMac) {
      throw Exception('La impresora no tiene IP ni Bluetooth configurados');
    }

    Object? errorRed;
    if (tieneIp) {
      try {
        await _enviarPorRed(ip, puerto, bytes);
        return 'red';
      } catch (e) {
        errorRed = e;
      }
    }

    if (tieneMac) {
      try {
        await _enviarPorBluetooth(mac, bytes);
        return 'Bluetooth';
      } catch (e) {
        throw Exception(tieneIp
            ? 'Fallo por red ($errorRed) y por Bluetooth ($e)'
            : 'Fallo por Bluetooth: $e');
      }
    }
    throw Exception('Fallo por red: $errorRed');
  }

  /// El primer intento tras un rato de inactividad suele fallar por timeout
  /// (el Wi-Fi del dispositivo despierta y se resuelve ARP recién con ese
  /// intento), así que se reintenta antes de rendirse.
  static const _intentosRed = 3;

  static Future<void> _enviarPorRed(String ip, int puerto, List<int> bytes) async {
    Object? ultimoError;
    for (var intento = 1; intento <= _intentosRed; intento++) {
      try {
        final socket =
            await Socket.connect(ip, puerto, timeout: const Duration(seconds: 5));
        try {
          socket.add(bytes);
          await socket.flush();
        } finally {
          await socket.close();
        }
        return;
      } catch (e) {
        ultimoError = e;
        if (intento < _intentosRed) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    throw ultimoError!;
  }

  static Future<void> _enviarPorBluetooth(String mac, List<int> bytes) async {
    await _pedirPermisoBluetooth();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw Exception('El Bluetooth del dispositivo esta apagado');
    }
    // Cierra cualquier conexión previa que haya quedado abierta.
    if (await PrintBluetoothThermal.connectionStatus) {
      await PrintBluetoothThermal.disconnect;
    }
    final conectado = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!conectado) {
      throw Exception('No se pudo conectar a la impresora Bluetooth. '
          'Verifica que este encendida y emparejada con este dispositivo');
    }
    try {
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) throw Exception('No se pudieron enviar los datos por Bluetooth');
    } finally {
      await PrintBluetoothThermal.disconnect;
    }
  }

  /// Impresoras Bluetooth ya emparejadas con el dispositivo, para elegir
  /// una al configurar (nombre + MAC).
  static Future<List<BluetoothInfo>> impresorasBluetoothEmparejadas() async {
    await _pedirPermisoBluetooth();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw Exception('El Bluetooth del dispositivo esta apagado');
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<void> _pedirPermisoBluetooth() async {
    // Solo Android 12+ exige BLUETOOTH_CONNECT en tiempo de ejecución; en
    // versiones anteriores el permiso se reporta como concedido.
    if (!Platform.isAndroid) return;
    final estado = await Permission.bluetoothConnect.request();
    if (!estado.isGranted) {
      throw Exception('Permiso de Bluetooth denegado');
    }
  }

  /// Imprime el recibo o factura del cliente en la impresora indicada,
  /// con la cabecera del restaurant y su sucursal.
  /// Devuelve la vía usada ('red' o 'Bluetooth').
  static Future<String> imprimirRecibo({
    String? ip,
    int puerto = 9100,
    String? mac,
    required FacturaModel factura,
    required List<ReciboItem> items,
    required String metodoPago,
    required bool esFactura,
  }) async {
    {
      final f = factura;
      final esElectronica = f.sriClaveAcceso?.isNotEmpty ?? false;
      final titulo = esElectronica
          ? 'FACTURA ELECTRONICA'
          : esFactura ? 'FACTURA' : 'RECIBO';

      final bytes = <int>[
        ..._init,
        // ── Cabecera: emisor (como exige el RIDE) ──
        ..._center, ..._doubleSize, ..._boldOn,
        ..._texto('${f.nombreRestaurant.isNotEmpty ? f.nombreRestaurant : f.nombreSucursal}\n'),
        ..._normalSize, ..._boldOff,
        if (f.razonSocial?.isNotEmpty ?? false) ..._texto('${f.razonSocial}\n'),
        if (f.rucSucursal?.isNotEmpty ?? false) ..._texto('RUC: ${f.rucSucursal}\n'),
        if (f.nombreSucursal.isNotEmpty) ..._texto('${f.nombreSucursal}\n'),
        if (f.direccionSucursal?.isNotEmpty ?? false) ..._texto('${f.direccionSucursal}\n'),
        if (f.telefonoSucursal?.isNotEmpty ?? false) ..._texto('Tel: ${f.telefonoSucursal}\n'),
        ..._texto('${'=' * _cols}\n'),
        // ── Tipo y número de comprobante ──
        ..._boldOn,
        ..._texto('$titulo\n'),
        ..._texto('No. ${f.numeroFactura}\n'),
        ..._boldOff,
        if (esElectronica)
          ..._texto('AMBIENTE: ${_ambienteSri(f)}\n'),
        ..._left,
        ..._texto('Fecha: ${_fechaHora(f.fecha.toLocal())}\n'),
      ];

      // ── Autorización / clave de acceso SRI (la clave de 49 dígitos se
      // parte en líneas de 32 columnas, centrada como en el RIDE) ──
      if (esElectronica) {
        final clave = f.sriClaveAcceso!;
        bytes.addAll(_texto('${'-' * _cols}\n'));
        bytes.addAll(_center);
        bytes.addAll(_boldOn);
        bytes.addAll(_texto('AUTORIZACION / CLAVE DE ACCESO\n'));
        bytes.addAll(_boldOff);
        if (clave.length <= _cols) {
          bytes.addAll(_texto('$clave\n'));
        } else {
          // Partida en dos líneas balanceadas (25 + 24 en 49 dígitos)
          final mitad = (clave.length + 1) ~/ 2;
          bytes.addAll(_texto('${clave.substring(0, mitad)}\n'));
          bytes.addAll(_texto('${clave.substring(mitad)}\n'));
        }
        bytes.addAll(_left);
      }

      // ── Quién atendió y a quién se factura ──
      bytes.addAll(_texto('${'-' * _cols}\n'));
      if (f.cajero?.isNotEmpty ?? false) bytes.addAll(_texto('Cajero: ${f.cajero}\n'));
      bytes.addAll(_texto('${f.lugar?.isNotEmpty ?? false ? '${f.lugar} - ' : ''}Orden #${f.numeroOrden}\n'));
      bytes.addAll(_texto('Cliente: ${f.nombreCliente ?? 'Consumidor Final'}\n'));
      bytes.addAll(_texto('CI/RUC: ${(f.cedulaRucCliente?.isNotEmpty ?? false) ? f.cedulaRucCliente : '9999999999999'}\n'));

      // ── Detalle ──
      bytes.addAll(_texto('${'-' * _cols}\n'));
      for (final it in items) {
        bytes.addAll(_texto(_lineaMonto('${it.cantidad} x ${it.nombre}', it.subtotal)));
      }
      bytes.addAll(_texto('${'-' * _cols}\n'));
      bytes.addAll(_texto(_lineaMonto('Subtotal', f.subtotal)));
      if (f.descuento > 0) bytes.addAll(_texto(_lineaMonto('Descuento', -f.descuento)));
      bytes.addAll(_texto(_lineaMonto('IVA ${f.ivaPorcentaje.toStringAsFixed(0)}%', f.iva)));
      if (f.propina > 0) bytes.addAll(_texto(_lineaMonto('Propina', f.propina)));
      bytes.addAll(_boldOn);
      bytes.addAll(_texto(_lineaMonto('TOTAL', f.total)));
      bytes.addAll(_boldOff);
      bytes.addAll(_texto('Son: ${_totalEnLetras(f.total)}\n'));
      bytes.addAll(_texto(_tituloSeparador('Forma de pago')));
      if (f.pagos.isNotEmpty) {
        for (final p in f.pagos) {
          bytes.addAll(_texto(_lineaMonto(p.nombreMetodoPago, p.monto)));
        }
      } else {
        bytes.addAll(_texto(_lineaMonto(metodoPago, f.total)));
      }
      bytes.addAll(_texto('${'=' * _cols}\n'));

      // ── Pie ──
      bytes.addAll(_center);
      bytes.addAll(_texto('¡Gracias por su preferencia!\n'));
      if (esElectronica) {
        bytes.addAll(_texto('Su factura electronica fue enviada\n'));
        bytes.addAll(_texto('al correo registrado. Verifiquela con\n'));
        bytes.addAll(_texto('la clave de acceso en www.sri.gob.ec\n'));
      } else {
        bytes.addAll(_texto('Documento interno sin validez tributaria.\n'));
      }
      bytes.addAll(_left);
      bytes.addAll(_feed);
      bytes.addAll(_cut);

      return _enviar(ip: ip, puerto: puerto, mac: mac, bytes: bytes);
    }
  }

  /// Título centrado entre guiones al ancho del papel:
  /// "---------- Forma de pago ----------".
  static String _tituloSeparador(String titulo) {
    final resto = _cols - titulo.length - 2;
    if (resto < 2) return '$titulo\n';
    final izq = resto ~/ 2;
    return '${'-' * izq} $titulo ${'-' * (resto - izq)}\n';
  }

  /// Ambiente SRI para el ticket: por la autorización de pruebas (prefijo
  /// TEST) o por el dígito 24 de la clave de acceso (1=pruebas 2=producción).
  static String _ambienteSri(FacturaModel f) {
    if (f.sriAutorizacion?.startsWith('TEST') ?? false) return 'PRUEBAS';
    final clave = f.sriClaveAcceso ?? '';
    if (clave.length == 49 && clave[23] == '1') return 'PRUEBAS';
    return 'PRODUCCION';
  }

  /// Total en letras como en los comprobantes impresos:
  /// 8.25 → "OCHO DOLARES CON 25/100".
  static String _totalEnLetras(double total) {
    final entero = total.floor();
    final centavos = ((total - entero) * 100).round();
    final palabra = entero == 1 ? 'DOLAR' : 'DOLARES';
    return '${_numeroEnLetras(entero)} $palabra CON ${centavos.toString().padLeft(2, '0')}/100';
  }

  static String _numeroEnLetras(int n) {
    const unidades = ['CERO', 'UNO', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS',
      'SIETE', 'OCHO', 'NUEVE', 'DIEZ', 'ONCE', 'DOCE', 'TRECE', 'CATORCE',
      'QUINCE', 'DIECISEIS', 'DIECISIETE', 'DIECIOCHO', 'DIECINUEVE', 'VEINTE'];
    const decenas = ['', '', 'VEINTI', 'TREINTA', 'CUARENTA', 'CINCUENTA',
      'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA'];
    const centenas = ['', 'CIENTO', 'DOSCIENTOS', 'TRESCIENTOS', 'CUATROCIENTOS',
      'QUINIENTOS', 'SEISCIENTOS', 'SETECIENTOS', 'OCHOCIENTOS', 'NOVECIENTOS'];

    if (n <= 20) return unidades[n];
    if (n < 30) return 'VEINTI${unidades[n - 20]}';
    if (n < 100) {
      final d = n ~/ 10, u = n % 10;
      return u == 0 ? decenas[d] : '${decenas[d]} Y ${unidades[u]}';
    }
    if (n == 100) return 'CIEN';
    if (n < 1000) {
      final c = n ~/ 100, resto = n % 100;
      return resto == 0 ? centenas[c] : '${centenas[c]} ${_numeroEnLetras(resto)}';
    }
    if (n < 1000000) {
      final miles = n ~/ 1000, resto = n % 1000;
      final prefijo = miles == 1 ? 'MIL' : '${_numeroEnLetras(miles)} MIL';
      return resto == 0 ? prefijo : '$prefijo ${_numeroEnLetras(resto)}';
    }
    return '$n';
  }

  /// Imprime el ticket de cierre de caja con todo el detalle del turno:
  /// arqueo, ventas por método de pago, cada ingreso/egreso y ventas por
  /// plato. Sirve para el cierre del cajero y para reimprimir desde
  /// Reportes.
  static Future<String> imprimirCierreCaja({
    String? ip,
    int puerto = 9100,
    String? mac,
    required CierreDetalladoModel cierre,
    String? nombreSucursal,
  }) async {
    {
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
        ..._texto('${'-' * _cols}\n'),
        ..._texto('Apertura: ${_fechaHora(c.fechaApertura.toLocal())}\n'),
        ..._texto('  por ${c.usuarioApertura}\n'),
        if (c.fechaCierre != null) ...[
          ..._texto('Cierre:   ${_fechaHora(c.fechaCierre!.toLocal())}\n'),
          if (c.usuarioCierre?.isNotEmpty ?? false)
            ..._texto('  por ${c.usuarioCierre}\n'),
        ],
        ..._texto('${'-' * _cols}\n'),
        // ── Total de caja del turno: todo el dinero, con su desglose ──
        ..._boldOn, ..._texto('TOTAL DE CAJA DEL TURNO\n'), ..._boldOff,
        ..._texto(_lineaMonto('Fondo inicial', c.montoInicial)),
        if (c.ventasPorMetodo.isEmpty && c.totalVentas > 0.009)
          ..._texto(_lineaMonto('+ Ventas', c.totalVentas))
        else
          for (final m in c.ventasPorMetodo)
            ..._texto(_lineaMonto('+ Ventas ${m.metodo}', m.total)),
        ..._texto(_lineaMonto('+ Otros ingresos', c.totalIngresos)),
        ..._texto(_lineaMonto('- Egresos', -c.totalEgresos)),
        ..._center, ..._doubleSize, ..._boldOn,
        ..._texto('TOTAL: ${c.totalCaja.toStringAsFixed(2)}\n'),
        ..._normalSize, ..._boldOff, ..._left,
        ..._texto('(efectivo + tarjeta + transf.)\n'),
        ..._texto('${'-' * _cols}\n'),
        // ── Arqueo: solo el efectivo fisico del cajon ──
        ..._boldOn, ..._texto('ARQUEO (SOLO EFECTIVO)\n'), ..._boldOff,
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
      bytes.addAll(_texto('${'-' * _cols}\n'));

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
      bytes.addAll(_texto('${'-' * _cols}\n'));

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
      bytes.addAll(_texto('${'-' * _cols}\n'));

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
      bytes.addAll(_texto('${'-' * _cols}\n'));

      // ── Ventas por plato ──
      if (c.ventasPorPlato.isNotEmpty) {
        bytes.addAll(_boldOn);
        bytes.addAll(_texto('VENTAS POR PLATO\n'));
        bytes.addAll(_boldOff);
        for (final v in c.ventasPorPlato) {
          bytes.addAll(_texto(_lineaMonto('${v.cantidad} x ${v.plato}', v.total)));
        }
        bytes.addAll(_texto('${'-' * _cols}\n'));
      }

      if ((c.observaciones ?? '').trim().isNotEmpty) {
        bytes.addAll(_texto('Obs: ${c.observaciones}\n'));
        bytes.addAll(_texto('${'-' * _cols}\n'));
      }

      bytes.addAll(_center);
      bytes.addAll(_texto('Impreso: ${_fechaHora(DateTime.now())}\n'));
      bytes.addAll(_left);
      bytes.addAll(_feed);
      bytes.addAll(_cut);

      return _enviar(ip: ip, puerto: puerto, mac: mac, bytes: bytes);
    }
  }

  /// Concepto a la izquierda y monto alineado a la derecha (32 columnas).
  static String _lineaMonto(String concepto, double monto) {
    final valor = monto.toStringAsFixed(2);
    var nombre = concepto;
    final ancho = _cols - valor.length - 1;
    if (nombre.length > ancho) nombre = nombre.substring(0, ancho);
    return '$nombre${' ' * (_cols - nombre.length - valor.length)}$valor\n';
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
