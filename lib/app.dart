import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/router/app_router.dart';
import 'core/settings/ajustes_texto.dart';
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
  late final router = AppRouter.router(_authBloc);

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
      child: MaterialApp.router(
        title: 'Wasi',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: router,
        // Tamaño de texto elegido por el usuario (accesibilidad): se combina
        // con el ajuste del sistema y se limita el total para que la letra
        // crezca sin romper tarjetas, cuadrículas ni la responsividad.
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: AjustesTexto.instancia.factor,
          builder: (context, factor, _) {
            final mq = MediaQuery.of(context);
            final total = (mq.textScaler.scale(1.0) * factor).clamp(0.85, 1.4);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(total)),
              child: child!,
            );
          },
        ),
        locale: const Locale('es', 'EC'),
        // Sin estos delegates, showDatePicker (y otros widgets Material)
        // fallan con locale 'es'
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es', 'EC'),
          Locale('es'),
          Locale('en'),
        ],
      ),
    );
  }
}
