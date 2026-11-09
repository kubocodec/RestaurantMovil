import 'package:shared_preferences/shared_preferences.dart';
import '../../features/caja/data/caja_repository.dart';
import '../models/caja_model.dart';

/// Qué caja (y qué turno abierto) usa el usuario que está en el equipo.
///
/// Antes cada pantalla tomaba `cajas.first`: con varias cajas en la sucursal
/// (un evento con 14 cajeros) todos abrían y cobraban en la primera, y su
/// cierre mezclaba las ventas de todos. La regla vive aquí para que Caja,
/// Cobro, Adelantos y el panel del cajero decidan lo mismo.
///
/// **Con una sola caja se comporta exactamente como antes**: esa caja y su
/// turno abierto, lo haya abierto quien lo haya abierto. Es el caso de todos
/// los restaurantes de hoy.
///
/// Con varias, cada cajero cobra solo en el turno que abrió él (si no, su
/// arqueo no cuadra). El admin, que ayuda en la fila sin turno propio, puede
/// elegir una caja abierta por otro y la venta va al cierre de esa caja.
class CajaActual {
  CajaActual._();

  static final _repo = CajaRepository();

  static String _clave(String usuarioId) => 'caja_elegida_$usuarioId';

  /// Caja que el usuario eligió en este equipo (null si nunca eligió).
  static Future<String?> guardada(String usuarioId) async {
    if (usuarioId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clave(usuarioId));
  }

  static Future<void> guardar(String usuarioId, String cajaId) async {
    if (usuarioId.isEmpty || cajaId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave(usuarioId), cajaId);
  }

  /// Resuelve la caja del usuario.
  ///
  /// Con varias cajas intenta primero la guardada (una sola consulta: el
  /// cobro se abre muchas veces por turno) y solo si no sirve consulta el
  /// turno de todas.
  static Future<EstadoCajas> resolver({
    required String sucursalId,
    required String usuarioId,
    required bool esAdmin,
  }) async {
    final cajas = await _repo.getCajasBySucursal(sucursalId);
    if (cajas.isEmpty) return EstadoCajas(cajas: cajas);

    if (cajas.length == 1) {
      final caja = cajas.first;
      final apertura = await _repo.getAperturaActiva(caja.cajaId);
      return EstadoCajas(
        cajas: cajas,
        caja: caja,
        apertura: apertura?.isAbierta == true ? apertura : null,
        aperturas: {caja.cajaId: apertura},
      );
    }

    bool sirve(AperturaCajaModel? a) =>
        a != null && a.isAbierta && (esAdmin || a.usuarioAperturaId == usuarioId);

    final guardadaId = await guardada(usuarioId);
    final cajaGuardada = cajas.where((c) => c.cajaId == guardadaId).firstOrNull;
    if (cajaGuardada != null) {
      final a = await _repo.getAperturaActiva(cajaGuardada.cajaId);
      if (sirve(a)) {
        return EstadoCajas(
          cajas: cajas, caja: cajaGuardada, apertura: a,
          aperturas: {cajaGuardada.cajaId: a},
          completo: false,
        );
      }
    }

    final aperturas = await estadoDeTodas(cajas);
    // El turno propio gana siempre, también para el admin.
    final propia = cajas.where((c) {
      final a = aperturas[c.cajaId];
      return a != null && a.isAbierta && a.usuarioAperturaId == usuarioId;
    }).firstOrNull;
    if (propia != null) {
      await guardar(usuarioId, propia.cajaId);
      return EstadoCajas(
        cajas: cajas, caja: propia, apertura: aperturas[propia.cajaId],
        aperturas: aperturas,
      );
    }
    return EstadoCajas(cajas: cajas, aperturas: aperturas, cajaGuardada: cajaGuardada);
  }

  /// Turno activo de cada caja, en paralelo.
  static Future<Map<String, AperturaCajaModel?>> estadoDeTodas(List<CajaModel> cajas) async {
    final lista = await Future.wait(cajas.map((c) => _repo.getAperturaActiva(c.cajaId)));
    return {
      for (var i = 0; i < cajas.length; i++)
        cajas[i].cajaId: lista[i]?.isAbierta == true ? lista[i] : null,
    };
  }
}

class EstadoCajas {
  final List<CajaModel> cajas;

  /// Caja del usuario (null si con varias cajas todavía no tiene una).
  final CajaModel? caja;

  /// Turno abierto donde el usuario cobra (null = no puede cobrar todavía).
  final AperturaCajaModel? apertura;

  /// Turno abierto de cada caja consultada (null = cerrada).
  final Map<String, AperturaCajaModel?> aperturas;

  /// false cuando se resolvió por la caja guardada sin consultar las demás.
  final bool completo;

  /// Caja que el usuario usó la última vez, aunque hoy esté cerrada.
  final CajaModel? cajaGuardada;

  const EstadoCajas({
    required this.cajas,
    this.caja,
    this.apertura,
    this.aperturas = const {},
    this.completo = true,
    this.cajaGuardada,
  });

  bool get varias => cajas.length > 1;

  /// Cajas abiertas por otros: el admin puede elegir una para cobrar.
  List<CajaModel> get abiertas =>
      cajas.where((c) => aperturas[c.cajaId] != null).toList();
}
