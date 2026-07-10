import 'dart:convert';
import 'dart:io';

import '../models/orden_model.dart';

/// Resultado de la impresión de una comanda.
class ResultadoImpresion {
  final String impresora;
  final bool ok;
  final String? error;
  const ResultadoImpresion(this.impresora, this.ok, [this.error]);
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
