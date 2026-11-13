import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../models/user_model.dart';
import 'escritorio.dart';
import 'lateral.dart';
import 'observador_rutas.dart';
import 'tema_escritorio.dart';

/// Menú lateral fijo a la izquierda y la app a la derecha (web, 1000 px o más,
/// con sesión). Ver CLAUDE.md, "Web de escritorio".
///
/// El lateral va AL LADO del Navigator y no dentro de un ShellRoute: así la
/// navegación queda idéntica a la del celular (un solo Navigator) y el cobro
/// y las anulaciones no cambian en nada.
///
/// El árbol alrededor de [child] (el Navigator) NO cambia de forma nunca: la
/// Row existe siempre y, con la ventana angosta o sin sesión, el lateral mide
/// 0. Si [child] cambiara de lugar al cruzar los 1000 px o al iniciar sesión,
/// se reconstruiría el router y se perdería lo abierto. Por eso además va en
/// un KeyedSubtree con una GlobalKey propia.
class EstructuraEscritorio extends StatefulWidget {
  final GoRouter router;
  final ObservadorRutas observador;
  final TextScaler textScaler;
  /// null = sin sesión: no hay lateral.
  final UserModel? user;
  final Widget child;

  const EstructuraEscritorio({
    super.key,
    required this.router,
    required this.observador,
    required this.textScaler,
    required this.user,
    required this.child,
  });

  @override
  State<EstructuraEscritorio> createState() => _EstructuraEscritorioState();
}

class _EstructuraEscritorioState extends State<EstructuraEscritorio> {
  final _claveContenido = GlobalKey(debugLabel: 'contenido');

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_alNavegar);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_alNavegar);
    super.dispose();
  }

  /// El Router avisa a veces en pleno build (al leer la ruta inicial):
  /// marcar para reconstruir ahí lanza "setState() called during build".
  void _alNavegar() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final user = widget.user;
    final enLogin = ubicacionActual(widget.router).startsWith('/login');
    final activo = user != null && !enLogin && mq.size.width >= MedidasEscritorio.anchoMinimo;

    final anchoLateral = activo ? MedidasEscritorio.anchoLateral : 0.0;
    final disponible = mq.size.width - anchoLateral;
    // Sin el lateral (inicio de sesión, ventana angosta) la app usa todo el
    // ancho: el inicio de sesión tiene su diseño partido y por debajo de
    // 1000 px no hace falta tope.
    final ancho = activo ? disponible.clamp(0.0, MedidasEscritorio.anchoMaximoContenido) : disponible;

    final contenido = KeyedSubtree(
      key: _claveContenido,
      child: MediaQuery(
        data: mq.copyWith(textScaler: widget.textScaler, size: Size(ancho, mq.size.height)),
        child: Theme(
          data: activo ? TemaEscritorio.tema : Theme.of(context),
          child: EscritorioScope(activo: activo, child: widget.child),
        ),
      ),
    );

    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: anchoLateral,
            child: activo
                ? MediaQuery(
                    data: mq.copyWith(textScaler: widget.textScaler),
                    child: _LateralConVelo(
                      observador: widget.observador,
                      child: LateralEscritorio(router: widget.router, observador: widget.observador, user: user),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: ancho, child: contenido),
            ),
          ),
        ],
      ),
    );
  }
}

/// Con un diálogo abierto, el lateral se oscurece como el resto y no
/// responde: el velo del diálogo solo cubre el Navigator.
class _LateralConVelo extends StatelessWidget {
  final ObservadorRutas observador;
  final Widget child;

  const _LateralConVelo({required this.observador, required this.child});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: observador.hayModal,
        builder: (_, modal, __) => ValueListenableBuilder<bool>(
          valueListenable: observador.fondoOscurecido,
          builder: (_, oscuro, __) => Stack(
            fit: StackFit.expand,
            children: [
              AbsorbPointer(absorbing: modal, child: child),
              IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  color: oscuro ? Colors.black54 : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      );
}
