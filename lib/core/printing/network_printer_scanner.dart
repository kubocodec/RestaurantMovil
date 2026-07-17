import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// Impresora detectada en la red local.
class ImpresoraRed {
  final String ip;
  final int puerto;
  /// Nombre del equipo si se anunció por mDNS (las térmicas baratas no lo hacen).
  final String? nombre;
  /// Cómo se encontró: 'mDNS' o 'escaneo'.
  final String fuente;
  const ImpresoraRed({
    required this.ip,
    required this.puerto,
    this.nombre,
    required this.fuente,
  });
}

/// Busca impresoras en la red WiFi combinando dos vías en paralelo:
///  1. mDNS/Bonjour: las impresoras que se anuncian responden con su nombre
///     y el puerto real configurado.
///  2. Escaneo de la subred /24 probando los puertos de impresión comunes
///     (cubre las térmicas ESC/POS que no se anuncian por mDNS).
/// Una impresora con puerto arbitrario y sin mDNS no aparecerá: para ese
/// caso queda la entrada manual de IP/puerto en el formulario.
class NetworkPrinterScanner {
  /// En orden de preferencia: RAW/JetDirect y variantes, IPP, LPR.
  static const puertosComunes = [9100, 9101, 9102, 631, 515];

  /// Tipos de servicio mDNS que anuncian las impresoras.
  static const _tiposMdns = [
    '_pdl-datastream._tcp.local', // RAW 9100
    '_printer._tcp.local',        // LPR
    '_ipp._tcp.local',            // IPP
  ];

  static const _timeoutSocket = Duration(milliseconds: 400);
  static const _timeoutMdns = Duration(seconds: 4);
  /// IPs sondeadas a la vez (cada una abre hasta 5 sockets).
  static const _ipsEnParalelo = 40;

  bool _cancelado = false;

  /// Detiene la búsqueda en curso; el stream se cierra en cuanto terminan
  /// las sondas ya lanzadas.
  void cancelar() => _cancelado = true;

  /// Emite cada impresora encontrada (sin duplicar IPs). [onAvance] reporta
  /// el progreso del escaneo de subred entre 0.0 y 1.0.
  Stream<ImpresoraRed> buscar({void Function(double avance)? onAvance}) {
    final controller = StreamController<ImpresoraRed>();
    _buscar(controller, onAvance).whenComplete(controller.close);
    return controller.stream;
  }

  Future<void> _buscar(
    StreamController<ImpresoraRed> controller,
    void Function(double)? onAvance,
  ) async {
    final reportadas = <String>{};
    void emitir(ImpresoraRed imp) {
      if (_cancelado || controller.isClosed) return;
      if (reportadas.add(imp.ip)) controller.add(imp);
    }

    final subred = await _subredLocal();
    await Future.wait([
      _buscarPorMdns(emitir),
      if (subred != null) _escanearSubred(subred, emitir, onAvance),
    ]);
  }

  /// Prefijo /24 de la IP WiFi del dispositivo (ej: '192.168.1'), o null si
  /// no hay una red privada conectada.
  Future<String?> _subredLocal() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback && _esIpPrivada(addr.address)) {
            final partes = addr.address.split('.');
            return '${partes[0]}.${partes[1]}.${partes[2]}';
          }
        }
      }
    } catch (_) {
      // Sin permiso o sin red: se sigue solo con mDNS.
    }
    return null;
  }

  static bool _esIpPrivada(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final segundo = int.tryParse(ip.split('.')[1]) ?? 0;
      return segundo >= 16 && segundo <= 31;
    }
    return false;
  }

  // ── Vía 1: mDNS/Bonjour ───────────────────────────────────────────────

  Future<void> _buscarPorMdns(void Function(ImpresoraRed) emitir) async {
    final client = MDnsClient();
    try {
      await client.start();
      await Future.wait(_tiposMdns.map((tipo) async {
        await for (final ptr in client
            .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(tipo),
                timeout: _timeoutMdns)) {
          if (_cancelado) return;
          await _resolverServicioMdns(client, ptr.domainName, emitir);
        }
      }));
    } catch (_) {
      // mDNS puede fallar en algunos dispositivos/emuladores; el escaneo
      // de subred sigue siendo la vía principal.
    } finally {
      client.stop();
    }
  }

  Future<void> _resolverServicioMdns(
    MDnsClient client,
    String servicio,
    void Function(ImpresoraRed) emitir,
  ) async {
    // 'EPSON TM-T88VI._ipp._tcp.local' -> nombre 'EPSON TM-T88VI'
    final nombre = servicio.split('._').first;
    await for (final srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(servicio), timeout: _timeoutMdns)) {
      await for (final a in client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target), timeout: _timeoutMdns)) {
        if (_cancelado) return;
        emitir(ImpresoraRed(
          ip: a.address.address,
          puerto: srv.port,
          nombre: nombre,
          fuente: 'mDNS',
        ));
        return; // basta la primera IP del servicio
      }
    }
  }

  // ── Vía 2: escaneo de la subred ───────────────────────────────────────

  Future<void> _escanearSubred(
    String subred,
    void Function(ImpresoraRed) emitir,
    void Function(double)? onAvance,
  ) async {
    final pendientes = List.generate(254, (i) => '$subred.${i + 1}');
    var hechas = 0;
    final total = pendientes.length;

    Future<void> worker() async {
      while (pendientes.isNotEmpty && !_cancelado) {
        final ip = pendientes.removeLast();
        final puerto = await _mejorPuertoAbierto(ip);
        if (puerto != null) {
          emitir(ImpresoraRed(ip: ip, puerto: puerto, fuente: 'escaneo'));
        }
        hechas++;
        onAvance?.call(hechas / total);
      }
    }

    await Future.wait(List.generate(_ipsEnParalelo, (_) => worker()));
  }

  /// Prueba los puertos comunes de la IP en paralelo y devuelve el de mayor
  /// prioridad que acepte conexión (9100 antes que 631/515), o null.
  Future<int?> _mejorPuertoAbierto(String ip) async {
    final abiertos = await Future.wait(puertosComunes.map((p) async {
      try {
        final socket = await Socket.connect(ip, p, timeout: _timeoutSocket);
        socket.destroy();
        return p;
      } catch (_) {
        return null;
      }
    }));
    for (final p in puertosComunes) {
      if (abiertos.contains(p)) return p;
    }
    return null;
  }
}
