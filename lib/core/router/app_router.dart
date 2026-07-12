import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/admin_dashboard.dart';
import '../../features/dashboard/presentation/cajero_dashboard.dart';
import '../../features/dashboard/presentation/mesero_dashboard.dart';
import '../../features/dashboard/presentation/cocinero_dashboard.dart';
import '../../features/mesas/presentation/mesas_screen.dart';
import '../../features/mesas/presentation/orden_screen.dart';
import '../../features/cocina/presentation/cocina_screen.dart';
import '../../features/caja/presentation/caja_screen.dart';
import '../../features/facturacion/presentation/comprobantes_screen.dart';
import '../../features/facturacion/presentation/facturacion_screen.dart';
import '../../features/facturacion/presentation/ordenes_para_facturar_screen.dart';
import '../../features/superadmin/presentation/superadmin_dashboard.dart';
import '../../features/configuracion/presentation/configuracion_screen.dart';
import '../../features/reportes/presentation/reportes_screen.dart';
import '../models/user_model.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter router(AuthBloc authBloc) {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/login',
      refreshListenable: _AuthListenable(authBloc),
      redirect: (context, state) {
        final authState = authBloc.state;
        final isLoginRoute = state.matchedLocation == '/login';

        if (authState is AuthLoading || authState is AuthInitial) return null;
        if (authState is AuthUnauthenticated || authState is AuthError) {
          return isLoginRoute ? null : '/login';
        }
        if (authState is AuthAuthenticated) {
          if (isLoginRoute) return _homeForRole(authState.user.rol);
        }
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

        // Super Admin
        GoRoute(path: '/superadmin', builder: (_, __) => const SuperAdminDashboard()),

        // Admin
        GoRoute(
          path: '/admin',
          builder: (_, __) => const AdminDashboard(),
          routes: [
            GoRoute(path: 'configuracion', builder: (_, __) => const ConfiguracionScreen()),
            GoRoute(path: 'reportes', builder: (_, __) => const ReportesScreen()),
          ],
        ),

        // Cajero
        GoRoute(
          path: '/cajero',
          builder: (_, __) => const CajeroDashboard(),
          routes: [
            GoRoute(path: 'caja',    builder: (_, __) => const CajaScreen()),
            GoRoute(path: 'ordenes', builder: (_, __) => const OrdenesParaFacturarScreen()),
            GoRoute(path: 'comprobantes', builder: (_, __) => const ComprobantesScreen()),
            GoRoute(
              path: 'factura/:ordenId',
              builder: (_, state) => FacturacionScreen(
                ordenId: state.pathParameters['ordenId']!,
              ),
            ),
          ],
        ),

        // Mesero
        GoRoute(
          path: '/mesero',
          builder: (_, __) => const MeseroDashboard(),
          routes: [
            GoRoute(path: 'mesas', builder: (_, __) => const MesasScreen()),
            // Pedido para llevar: orden sin mesa
            GoRoute(path: 'para-llevar', builder: (_, __) => const OrdenScreen()),
            GoRoute(
              path: 'orden/:mesaId',
              builder: (_, state) => OrdenScreen(
                mesaId:     state.pathParameters['mesaId']!,
                mesaNombre: state.uri.queryParameters['nombre'] ?? 'Mesa',
                isLibre:    state.uri.queryParameters['libre'] == 'true',
              ),
            ),
          ],
        ),

        // Cocinero
        GoRoute(path: '/cocinero', builder: (_, __) => const CocineroDashboard()),
        GoRoute(path: '/cocina',   builder: (_, __) => const CocinaScreen()),
      ],
    );
  }

  static String _homeForRole(UserRole role) {
    switch (role) {
      case UserRole.superadmin: return '/superadmin';
      case UserRole.admin:      return '/admin';
      case UserRole.cajero:     return '/cajero';
      case UserRole.mesero:     return '/mesero';
      case UserRole.cocinero:   return '/cocinero';
      case UserRole.unknown:    return '/login';
    }
  }
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(AuthBloc bloc) {
    bloc.stream.listen((_) => notifyListeners());
  }
}
