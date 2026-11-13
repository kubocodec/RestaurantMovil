import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Sigue la pila del Navigator para que el menú lateral, que vive FUERA de
/// él, sepa si hay un diálogo abierto.
///
/// Los diálogos se abren en el Navigator, así que su velo oscurece solo el
/// contenido; el lateral se oscurece y deja de recibir clics por su cuenta
/// mirando [hayModal] y [fondoOscurecido]. Sin esto, se podía cambiar de
/// pantalla con el diálogo de cobro abierto.
class ObservadorRutas extends NavigatorObserver {
  final List<Route<dynamic>> _pila = [];

  /// Hay un diálogo, hoja inferior o menú desplegable abierto.
  final ValueNotifier<bool> hayModal = ValueNotifier(false);

  /// …y además oscurece el fondo (un desplegable no lo hace).
  final ValueNotifier<bool> fondoOscurecido = ValueNotifier(false);

  Route<dynamic>? get rutaSuperior => _pila.isEmpty ? null : _pila.last;

  void _actualizar() {
    final arriba = rutaSuperior;
    final modal = arriba is PopupRoute;
    final oscuro = modal && (arriba.barrierColor?.a ?? 0) > 0;
    void aplicar() {
      hayModal.value = modal;
      fondoOscurecido.value = oscuro;
    }

    // El Navigator a veces avisa en pleno build: cambiar un ValueNotifier ahí
    // lanza "setState() called during build".
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => aplicar());
    } else {
      aplicar();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pila.add(route);
    _actualizar();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pila.remove(route);
    _actualizar();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pila.remove(route);
    _actualizar();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pila.indexOf(oldRoute);
    if (newRoute != null) {
      if (i >= 0) {
        _pila[i] = newRoute;
      } else {
        _pila.add(newRoute);
      }
    } else if (i >= 0) {
      _pila.removeAt(i);
    }
    _actualizar();
  }
}
