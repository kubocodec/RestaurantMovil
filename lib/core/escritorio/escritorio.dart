import 'package:flutter/widgets.dart';

/// Medidas de la estructura de escritorio (maqueta aprobada el 2026-11-12,
/// docs/maqueta-web/).
abstract final class MedidasEscritorio {
  /// Por debajo de este ancho la web se ve igual que siempre: la pantalla
  /// del celular, con su menú de hamburguesa.
  static const double anchoMinimo = 1000;
  static const double anchoLateral = 248;

  /// Tope del contenido: las pantallas nacieron para el celular y en un
  /// monitor de 2560 px quedarían desparramadas.
  static const double anchoMaximoContenido = 1440;
}

/// Dice a las pantallas si están dentro de la estructura de escritorio (menú
/// lateral fijo). Sin uno arriba —en el celular, en Windows o en la web con
/// la ventana angosta— [enUso] devuelve false y todo queda como siempre.
class EscritorioScope extends InheritedWidget {
  final bool activo;

  const EscritorioScope({super.key, required this.activo, required super.child});

  static bool enUso(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EscritorioScope>()?.activo ?? false;

  @override
  bool updateShouldNotify(EscritorioScope oldWidget) => oldWidget.activo != activo;
}
