import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Factor efectivo del texto (sistema × preferencia, ya limitado en app.dart).
/// Úsalo para escalar alturas fijas (mainAxisExtent, SizedBox) junto con la
/// letra y que las tarjetas no se desborden con tamaños grandes.
double escalaTextoDe(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);

/// Ajuste de accesibilidad por dispositivo: tamaño del texto de toda la app.
///
/// Se aplica como factor sobre MediaQuery.textScaler (ver app.dart) y se
/// guarda en el teléfono/tablet, así cada equipo mantiene su preferencia
/// (útil para usuarios que necesitan letra más grande). Las opciones están
/// acotadas para que el texto crezca sin romper tarjetas ni cuadrículas.
class AjustesTexto {
  AjustesTexto._();
  static final AjustesTexto instancia = AjustesTexto._();

  static const _clave = 'factor_texto';

  static const opciones = [
    (etiqueta: 'Normal', factor: 1.0),
    (etiqueta: 'Mediano', factor: 1.1),
    (etiqueta: 'Grande', factor: 1.2),
    (etiqueta: 'Muy grande', factor: 1.3),
  ];

  final ValueNotifier<double> factor = ValueNotifier(1.0);
  SharedPreferences? _prefs;

  /// Etiqueta de la opción activa (para mostrar en el menú).
  String get etiquetaActual {
    for (final o in opciones) {
      if ((factor.value - o.factor).abs() < 0.01) return o.etiqueta;
    }
    return 'Normal';
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final guardado = _prefs?.getDouble(_clave);
    if (guardado != null) factor.value = guardado.clamp(1.0, 1.3);
  }

  Future<void> cambiar(double nuevo) async {
    factor.value = nuevo.clamp(1.0, 1.3);
    await _prefs?.setDouble(_clave, factor.value);
  }
}
