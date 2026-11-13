import 'dart:typed_data';

/// Fuera del navegador no hay descarga: los botones que la usan se esconden
/// con `Capacidades.descargarArchivos`, así que llegar aquí es un error de
/// programación, no algo que el usuario pueda provocar.
Future<void> descargarArchivo(Uint8List bytes, String nombre, String mime) async {
  throw UnsupportedError('Descargar archivos solo está disponible en la web');
}
