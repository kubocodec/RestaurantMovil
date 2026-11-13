import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/adelantos/data/adelantos_repository.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_event.dart';
import '../../features/inventario/data/inventario_repository.dart';
import '../constants/app_colors.dart';
import '../models/user_model.dart';
import '../settings/ajustes_cobro.dart';
import '../settings/ajustes_texto.dart';
import 'escritorio.dart';
import 'menu_escritorio.dart';
import 'observador_rutas.dart';

/// Dónde está el usuario, también si la pantalla se abrió con context.push
/// (el último match es imperativo y trae su propia lista).
String ubicacionActual(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  if (config.isEmpty) return '';
  final ultimo = config.matches.last;
  final lista = ultimo is ImperativeRouteMatch ? ultimo.matches : config;
  return lista.uri.path;
}

/// Menú lateral fijo de la web de escritorio (estilo A · Café).
///
/// Vive FUERA del Navigator (ver app.dart y CLAUDE.md, "Web de escritorio"),
/// así que aquí no hay Overlay: nada de Tooltip, PopupMenuButton ni
/// DropdownButton, que lo necesitan y revientan. Tampoco hay
/// Navigator.of(context) ni GoRouterState.of(context): el router llega por
/// parámetro y los diálogos se abren con el contexto de su Navigator.
class LateralEscritorio extends StatefulWidget {
  final GoRouter router;
  final ObservadorRutas observador;
  final UserModel user;

  const LateralEscritorio({super.key, required this.router, required this.observador, required this.user});

  @override
  State<LateralEscritorio> createState() => _LateralEscritorioState();
}

class _LateralEscritorioState extends State<LateralEscritorio> {
  static const _fondo = AppColors.primaryDark;
  static const _texto = Color(0xB8FFFFFF); // blanco al 72 %
  static const _tenue = Color(0x8CFFFFFF); // blanco al 55 %
  static const _titulos = Color(0x73FFFFFF); // blanco al 45 %

  /// Módulos que tiene el local. Hasta saberlo no se muestran: mejor que
  /// aparezcan un instante después que mostrar uno que no tiene.
  Set<ModuloOpcional> _modulos = {};

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_alNavegar);
    _cargarModulos();
  }

  @override
  void didUpdateWidget(LateralEscritorio old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router.routerDelegate.removeListener(_alNavegar);
      widget.router.routerDelegate.addListener(_alNavegar);
    }
    if (old.user.id != widget.user.id || old.user.sucursalId != widget.user.sucursalId) {
      _modulos = {};
      _cargarModulos();
    }
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

  /// Igual que el panel: los dos repositorios ya responden "no habilitado"
  /// si algo falla, así que esto nunca rompe el menú.
  Future<void> _cargarModulos() async {
    final sucursalId = widget.user.sucursalId;
    final rol = widget.user.rol;
    if (sucursalId.isEmpty || !(rol == UserRole.admin || rol == UserRole.cajero)) return;
    final id = widget.user.id;
    final r = await Future.wait([
      rol == UserRole.admin
          ? InventarioRepository().getAlertas(sucursalId).then((a) => a.habilitado)
          : Future.value(false),
      AdelantosRepository().listar(sucursalId).then((a) => a.habilitado),
    ]).catchError((_) => [false, false]);
    if (!mounted || widget.user.id != id) return;
    setState(() => _modulos = {
          if (r[0]) ModuloOpcional.inventario,
          if (r[1]) ModuloOpcional.adelantos,
        });
  }

  NavigatorState? get _navegador => widget.router.routerDelegate.navigatorKey.currentState;

  void _ir(String ruta) {
    final obs = widget.observador;
    if (obs.hayModal.value) return;
    final nav = _navegador;
    final arriba = obs.rutaSuperior;
    if (nav != null && arriba != null && arriba.popDisposition == RoutePopDisposition.doNotPop) {
      // La pantalla tiene cambios sin guardar (la receta): que pregunte ella.
      nav.maybePop();
      return;
    }
    // Las pantallas abiertas con Navigator.push (Inventario desde el panel,
    // Resumen del período…) no son de go_router: si no se cierran, quedarían
    // encima de la ruta nueva.
    nav?.popUntil((r) => r.settings is Page);
    widget.router.go(ruta);
  }

  @override
  Widget build(BuildContext context) {
    final opciones = opcionesDe(widget.user.rol)
        .where((o) => o.modulo == null || _modulos.contains(o.modulo))
        .toList();
    final activa = opcionActiva(opciones, ubicacionActual(widget.router));

    return Material(
      color: _fondo,
      child: SizedBox(
        width: MedidasEscritorio.anchoLateral,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _marca(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                children: [
                  for (final o in opciones) ...[
                    if (o.grupo != null) _grupo(o.grupo!),
                    _Opcion(
                      icono: o.icono,
                      etiqueta: o.etiqueta,
                      activa: identical(o, activa),
                      onTap: () => _ir(o.ruta),
                    ),
                  ],
                ],
              ),
            ),
            _pie(),
          ],
        ),
      ),
    );
  }

  Widget _marca() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.restaurant, size: 20, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Wasi',
                      maxLines: 1,
                      style: TextStyle(
                          fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  if (widget.user.sucursalNombre.isNotEmpty)
                    Text(widget.user.sucursalNombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Poppins', color: _tenue, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _grupo(String titulo) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
        child: Text(titulo.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: 'Poppins', color: _titulos, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1)),
      );

  Widget _pie() {
    final u = widget.user;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1FFFFFFF)))),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : 'U',
                      style: const TextStyle(
                          fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Poppins', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(nombreDelRol(u.rol),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Poppins', color: _tenue, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _Opcion(icono: Icons.tune_rounded, etiqueta: 'Preferencias', activa: false, onTap: _preferencias),
          _Opcion(icono: Icons.logout_rounded, etiqueta: 'Cerrar sesión', activa: false, onTap: _cerrarSesion),
        ],
      ),
    );
  }

  bool get _cobra =>
      widget.user.rol == UserRole.cajero || widget.user.rol == UserRole.admin || widget.user.rol == UserRole.superadmin;

  void _preferencias() {
    final ctx = _navegador?.context;
    if (ctx == null || widget.observador.hayModal.value) return;
    showDialog<void>(context: ctx, builder: (_) => _PreferenciasDialogo(usuarioId: widget.user.id, cobra: _cobra));
  }

  void _cerrarSesion() {
    final ctx = _navegador?.context;
    if (ctx == null || widget.observador.hayModal.value) return;
    // Capturar el bloc antes de abrir el diálogo, como en AppDrawer.
    final authBloc = context.read<AuthBloc>();
    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que deseas salir?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(d);
              authBloc.add(AuthLogoutRequested());
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final bool activa;
  final VoidCallback onTap;

  const _Opcion({required this.icono, required this.etiqueta, required this.activa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = activa ? Colors.white : _LateralEscritorioState._texto;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: activa ? const Color(0x1AFFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: const Color(0x0FFFFFFF),
          child: Stack(
            children: [
              if (activa)
                const Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: SizedBox(
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Icon(icono, size: 20, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(etiqueta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: color,
                            fontSize: 13.5,
                            fontWeight: activa ? FontWeight.w600 : FontWeight.w500,
                          )),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tamaño del texto y, para quien cobra, las dos preferencias del cobro.
/// Lo mismo que el pie del menú del celular, en un diálogo.
class _PreferenciasDialogo extends StatelessWidget {
  final String usuarioId;
  final bool cobra;

  const _PreferenciasDialogo({required this.usuarioId, required this.cobra});

  @override
  Widget build(BuildContext context) {
    const titulo = TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 14);
    const detalle = TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary);
    return AlertDialog(
      title: const Text('Preferencias'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tamaño del texto', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
              const Text('Se aplica a toda la app en este equipo.', style: detalle),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: AjustesTexto.instancia.factor,
                builder: (_, actual, __) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in AjustesTexto.opciones)
                      ChoiceChip(
                        label: Text(o.etiqueta),
                        selected: (actual - o.factor).abs() < 0.01,
                        showCheckmark: false,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: (actual - o.factor).abs() < 0.01 ? Colors.white : AppColors.textPrimary,
                        ),
                        onSelected: (_) => AjustesTexto.instancia.cambiar(o.factor),
                      ),
                  ],
                ),
              ),
              if (cobra) ...[
                const SizedBox(height: 18),
                const Text('Cobro', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                ValueListenableBuilder<int>(
                  valueListenable: AjustesCobro.instancia.cambios,
                  builder: (_, __, ___) => Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Calcular vuelto en efectivo', style: titulo),
                        subtitle: const Text('Al cobrar, ingresa lo que te entregan', style: detalle),
                        value: AjustesCobro.instancia.calcularVuelto(usuarioId),
                        activeThumbColor: AppColors.success,
                        onChanged: (v) => AjustesCobro.instancia.cambiarCalcularVuelto(usuarioId, v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Preguntar propina al cobrar', style: titulo),
                        subtitle: const Text('Apágala si tu local no recibe propinas', style: detalle),
                        value: AjustesCobro.instancia.pedirPropina(usuarioId),
                        activeThumbColor: AppColors.success,
                        onChanged: (v) => AjustesCobro.instancia.cambiarPedirPropina(usuarioId, v),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
    );
  }
}
