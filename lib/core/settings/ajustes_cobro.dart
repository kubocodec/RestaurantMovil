import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del cobro que elige cada cajero.
///
/// Se guardan en el equipo pero POR USUARIO: si dos cajeros comparten la
/// tablet, cada uno conserva la suya. Vienen apagadas: quien no las activa
/// cobra exactamente igual que antes.
class AjustesCobro {
  AjustesCobro._();
  static final AjustesCobro instancia = AjustesCobro._();

  SharedPreferences? _prefs;

  /// Avisa a quien muestre el interruptor que cambió algún ajuste.
  final ValueNotifier<int> cambios = ValueNotifier(0);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String _claveVuelto(String usuarioId) => 'calcular_vuelto_$usuarioId';

  /// Al cobrar en efectivo, pedir lo recibido y mostrar el vuelto.
  bool calcularVuelto(String usuarioId) =>
      usuarioId.isNotEmpty && (_prefs?.getBool(_claveVuelto(usuarioId)) ?? false);

  Future<void> cambiarCalcularVuelto(String usuarioId, bool activo) async {
    if (usuarioId.isEmpty) return;
    await _prefs?.setBool(_claveVuelto(usuarioId), activo);
    cambios.value++;
  }
}
