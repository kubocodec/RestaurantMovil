import 'package:flutter/foundation.dart';

/// Qué puede hacer la app según dónde corre.
///
/// La app nació en el celular del mesero (Android y iOS) y ahora también corre
/// en el navegador —administrar desde la PC— y en Windows de escritorio, que
/// es donde se toma la orden y se cobra en el mostrador con la térmica de red.
/// En vez de sembrar `if (Platform.isAndroid)` por las pantallas, cada
/// capacidad se declara aquí una vez y la UI pregunta.
///
/// **Siempre con `kIsWeb` y `defaultTargetPlatform`, nunca con `Platform` de
/// `dart:io`**: en el navegador `dart:io` compila pero `Platform.isAndroid`
/// revienta al ejecutarse con un `UnsupportedError`, y el error aparece lejos
/// de su causa.
abstract final class Capacidades {
  /// Impresión por red: socket TCP crudo al puerto 9100, el estándar de las
  /// térmicas ESC/POS. Funciona donde haya sockets, o sea en todos lados
  /// menos el navegador: una pestaña no puede abrir sockets crudos y no hay
  /// forma de sortearlo desde la página.
  static bool get impresionRed => !kIsWeb;

  /// Bluetooth clásico (SPP) contra la MAC de la impresora. Lo resuelve un
  /// canal propio en MainActivity.kt, así que existe solo en Android: en
  /// iPhone y iPad no hay Bluetooth clásico para esto, y en el navegador
  /// tampoco.
  static bool get impresionBluetooth =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Buscar impresoras por mDNS y escaneando la subred. Necesita sockets UDP
  /// y TCP, así que tampoco va en el navegador.
  static bool get descubrirImpresoras => !kIsWeb;

  /// Hay alguna vía para imprimir. Donde es `false` (el navegador) la UI
  /// esconde los botones de imprimir en vez de dejarlos fallar al tocarlos.
  static bool get puedeImprimir => impresionRed || impresionBluetooth;

  /// Bajar un archivo que arma la app (los reportes en Excel). En el
  /// navegador se entrega como descarga. En el celular habría que guardarlo
  /// y compartirlo, que es otro flujo; mientras tanto, el botón no aparece.
  static bool get descargarArchivos => kIsWeb;

  static bool get esWeb => kIsWeb;

  static bool get esEscritorio =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get esMovil =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Pantalla grande con teclado y mouse: web y escritorio. La usa el layout
  /// para no estirar a lo ancho una interfaz pensada para el celular.
  static bool get esPantallaGrande => kIsWeb || esEscritorio;
}
