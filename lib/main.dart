import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/settings/ajustes_texto.dart';
import 'core/settings/ajustes_cobro.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  // Preferencia guardada de tamaño de texto (accesibilidad por dispositivo)
  await AjustesTexto.instancia.init();
  // Preferencias del cobro por cajero (calcular vuelto en efectivo)
  await AjustesCobro.instancia.init();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const WasiApp());
}
