import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_theme.dart';

/// El tema del celular con lo que cambia en la estructura de escritorio
/// (estilo A · Café de la maqueta): barra superior blanca con el título a la
/// izquierda y pantallas que cambian sin animación, como en una web.
abstract final class TemaEscritorio {
  static final ThemeData tema = _crear();

  static ThemeData _crear() {
    final base = AppTheme.lightTheme;
    const transicion = _SinTransicion();
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.cardBackground,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        shape: const Border(bottom: BorderSide(color: AppColors.surfaceVariant)),
        titleTextStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        actionsIconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      // En el celular las pestañas son blancas porque van sobre la barra
      // marrón; sobre la barra blanca no se verían.
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: transicion,
        TargetPlatform.iOS: transicion,
        TargetPlatform.macOS: transicion,
        TargetPlatform.windows: transicion,
        TargetPlatform.linux: transicion,
        TargetPlatform.fuchsia: transicion,
      }),
    );
  }
}

class _SinTransicion extends PageTransitionsBuilder {
  const _SinTransicion();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}
