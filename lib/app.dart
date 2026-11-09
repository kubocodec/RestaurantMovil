import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/constants/app_colors.dart';
import 'core/plataforma/capacidades.dart';
import 'core/router/app_router.dart';
import 'core/settings/ajustes_texto.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';

/// Ancho máximo de la app en pantallas grandes. Da lugar de sobra a las
/// cuadrículas de platos y a las tablas de reportes sin que la interfaz del
/// celular quede desparramada a lo ancho de un monitor.
const double _anchoMaximoEscritorio = 1200;

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
            // En la PC (navegador o Windows) la app no se estira a todo lo
            // ancho del monitor: está pensada para el celular y a 2560 px las
            // tarjetas quedan larguísimas y los formularios ilegibles.
            //
            // Se recorta también el `size` del MediaQuery, no solo el ancho
            // dibujado: si no, una pantalla que decide por ancho creería
            // tener el monitor entero mientras se dibuja en 1200.
            final limitar = Capacidades.esPantallaGrande &&
                mq.size.width > _anchoMaximoEscritorio;
            final contenido = MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(total),
                size: limitar
                    ? Size(_anchoMaximoEscritorio, mq.size.height)
                    : null,
              ),
              child: child!,
            );
            if (!limitar) return contenido;
            return ColoredBox(
              color: AppColors.surfaceVariant,
              child: Center(
                child: SizedBox(
                  width: _anchoMaximoEscritorio,
                  child: contenido,
                ),
              ),
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
