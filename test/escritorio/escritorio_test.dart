import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:restaurant_app/core/escritorio/escritorio.dart';
import 'package:restaurant_app/core/escritorio/estructura.dart';
import 'package:restaurant_app/core/escritorio/lateral.dart';
import 'package:restaurant_app/core/escritorio/menu_escritorio.dart';
import 'package:restaurant_app/core/escritorio/observador_rutas.dart';
import 'package:restaurant_app/core/models/user_model.dart';
import 'package:restaurant_app/core/theme/app_theme.dart';

// sucursalId vacío: el lateral no pregunta por los módulos y la prueba no
// hace ninguna llamada de red.
const _admin = UserModel(
  id: 'u1',
  nombre: 'Prueba Restaurante',
  usuario: 'prueba',
  correo: '',
  rol: UserRole.admin,
  sucursalId: '',
  restaurantId: 'r1',
  tenantId: 't1',
  sucursalNombre: 'Sucursal Centro',
  accessToken: '',
  refreshToken: '',
);

/// Pantalla con estado propio: si el árbol alrededor del Navigator cambiara
/// de forma, el contador volvería a 0.
class _Contador extends StatefulWidget {
  final String titulo;
  const _Contador(this.titulo);
  @override
  State<_Contador> createState() => _ContadorState();
}

class _ContadorState extends State<_Contador> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        body: Column(children: [
          Text('n=$n · escritorio=${EscritorioScope.enUso(context)}'),
          TextButton(onPressed: () => setState(() => n++), child: const Text('sumar')),
        ]),
      );
}

Future<(GoRouter, ObservadorRutas)> _montar(WidgetTester t,
    {double ancho = 1440, UserModel? user = _admin, double texto = 1}) async {
  t.view.physicalSize = Size(ancho, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final obs = ObservadorRutas();
  final router = GoRouter(
    initialLocation: '/admin',
    observers: [obs],
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const _Contador('Login')),
      GoRoute(path: '/admin', builder: (_, __) => const _Contador('Panel'), routes: [
        GoRoute(path: 'reportes', builder: (_, __) => const _Contador('Reportes')),
      ]),
      GoRoute(path: '/cajero/caja', builder: (_, __) => const _Contador('Caja')),
      GoRoute(path: '/mesero/mesas', builder: (_, __) => const _Contador('Mesas')),
    ],
  );
  await t.pumpWidget(MaterialApp.router(
    // El tema de la app: el de escritorio se arma sobre él.
    theme: AppTheme.lightTheme,
    routerConfig: router,
    builder: (context, child) => EstructuraEscritorio(
      router: router,
      observador: obs,
      textScaler: TextScaler.linear(texto),
      user: user,
      child: child!,
    ),
  ));
  await t.pumpAndSettle();
  return (router, obs);
}

void main() {
  group('menú por rol', () {
    test('la opción activa es la del prefijo más largo', () {
      final ops = opcionesDe(UserRole.admin);
      expect(opcionActiva(ops, '/admin')?.etiqueta, 'Panel');
      expect(opcionActiva(ops, '/admin/reportes')?.etiqueta, 'Reportes');
      expect(opcionActiva(ops, '/mesero/orden/123')?.etiqueta, 'Mesas');
      expect(opcionActiva(ops, '/cajero/factura/9')?.etiqueta, 'Por cobrar');
      expect(opcionActiva(ops, '/administrador'), isNull);
    });

    test('cada rol solo entra a lo suyo', () {
      expect(rutaPermitida(UserRole.admin, '/cajero/caja'), isTrue);
      expect(rutaPermitida(UserRole.admin, '/superadmin'), isFalse);
      expect(rutaPermitida(UserRole.cajero, '/mesero/orden/1'), isTrue);
      expect(rutaPermitida(UserRole.cajero, '/admin/reportes'), isFalse);
      expect(rutaPermitida(UserRole.mesero, '/cajero/factura/1'), isFalse);
      expect(rutaPermitida(UserRole.cocinero, '/cocina'), isTrue);
      expect(rutaPermitida(UserRole.cocinero, '/cocinero'), isTrue);
      expect(rutaPermitida(UserRole.cocinero, '/mesero'), isFalse);
      expect(rutaPermitida(UserRole.superadmin, '/admin'), isTrue);
      for (final r in UserRole.values) {
        expect(rutaPermitida(r, '/login'), isTrue);
      }
    });

    test('el inicio de cada rol está permitido para ese rol', () {
      for (final r in UserRole.values.where((r) => r != UserRole.unknown)) {
        expect(rutaPermitida(r, inicioDe(r)), isTrue, reason: '$r');
        for (final o in opcionesDe(r)) {
          expect(rutaPermitida(r, o.ruta), isTrue, reason: '$r → ${o.ruta}');
        }
      }
    });
  });

  group('estructura de escritorio', () {
    testWidgets('a 1440 px hay lateral y el contenido sabe que está en escritorio', (t) async {
      await _montar(t);
      expect(find.byType(LateralEscritorio), findsOneWidget);
      expect(find.text('Reportes'), findsOneWidget);
      expect(find.textContaining('escritorio=true'), findsOneWidget);
    });

    testWidgets('por debajo de 1000 px no hay lateral', (t) async {
      await _montar(t, ancho: 900);
      expect(find.byType(LateralEscritorio), findsNothing);
      expect(find.textContaining('escritorio=false'), findsOneWidget);
    });

    testWidgets('sin sesión no hay lateral', (t) async {
      await _montar(t, user: null);
      expect(find.byType(LateralEscritorio), findsNothing);
    });

    testWidgets('el menú navega y marca la opción', (t) async {
      final (router, _) = await _montar(t);
      await t.tap(find.text('Reportes'));
      await t.pumpAndSettle();
      expect(ubicacionActual(router), '/admin/reportes');
      expect(find.textContaining('n=0'), findsOneWidget);
    });

    testWidgets('cruzar los 1000 px no pierde lo que hay en pantalla', (t) async {
      await _montar(t);
      await t.tap(find.text('sumar'));
      await t.pump();
      expect(find.textContaining('n=1'), findsOneWidget);
      t.view.physicalSize = const Size(900, 900);
      await t.pumpAndSettle();
      expect(find.byType(LateralEscritorio), findsNothing);
      expect(find.textContaining('n=1 · escritorio=false'), findsOneWidget);
      t.view.physicalSize = const Size(1440, 900);
      await t.pumpAndSettle();
      expect(find.textContaining('n=1 · escritorio=true'), findsOneWidget);
    });

    testWidgets('con un diálogo abierto el lateral no navega', (t) async {
      final (router, obs) = await _montar(t);
      showDialog<void>(
        context: router.routerDelegate.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Cobrar')),
      );
      await t.pumpAndSettle();
      expect(obs.hayModal.value, isTrue);
      expect(obs.fondoOscurecido.value, isTrue);
      await t.tap(find.text('Caja'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(ubicacionActual(router), '/admin');
      expect(find.text('Cobrar'), findsOneWidget);
    });

    testWidgets('las pantallas abiertas con Navigator.push se cierran al cambiar de sección', (t) async {
      final (router, _) = await _montar(t);
      router.routerDelegate.navigatorKey.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => const _Contador('Inventario')));
      await t.pumpAndSettle();
      expect(find.text('Inventario'), findsOneWidget);
      await t.tap(find.text('Mesas').first);
      await t.pumpAndSettle();
      expect(ubicacionActual(router), '/mesero/mesas');
      expect(find.text('Inventario'), findsNothing);
    });

    testWidgets('con el texto en "Muy grande" el lateral no se desborda', (t) async {
      await _montar(t, texto: 1.4);
      expect(t.takeException(), isNull);
      expect(find.byType(LateralEscritorio), findsOneWidget);
    });
  });

  test('el observador sigue la pila y avisa de los diálogos', () {
    final obs = ObservadorRutas();
    final pagina = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    final dialogo = RawDialogRoute<void>(
        pageBuilder: (_, __, ___) => const SizedBox(), barrierColor: Colors.black54);
    obs.didPush(pagina, null);
    expect(obs.hayModal.value, isFalse);
    obs.didPush(dialogo, pagina);
    expect(obs.hayModal.value, isTrue);
    expect(obs.fondoOscurecido.value, isTrue);
    obs.didPop(dialogo, pagina);
    expect(obs.hayModal.value, isFalse);
    expect(obs.rutaSuperior, pagina);
  });
}
