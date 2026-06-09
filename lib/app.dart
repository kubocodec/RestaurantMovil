import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';

class WasiApp extends StatefulWidget {
  const WasiApp({super.key});

  @override
  State<WasiApp> createState() => _WasiAppState();
}

class _WasiAppState extends State<WasiApp> {
  late final AuthBloc _authBloc;

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc();
    _authBloc.add(AuthCheckRequested());
  }

  @override
  void dispose() {
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _authBloc,
      child: Builder(
        builder: (context) {
          final router = AppRouter.router(_authBloc);
          return MaterialApp.router(
            title: 'Wasi',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            routerConfig: router,
            locale: const Locale('es', 'EC'),
          );
        },
      ),
    );
  }
}
