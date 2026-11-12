import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Entrega un archivo al navegador como descarga.
///
/// Solo existe en la web: se importa a través de `descarga.dart`, que en el
/// celular y en Windows elige `descarga_stub.dart`. Si este archivo se
/// importara directo, el APK dejaría de compilar.
Future<void> descargarArchivo(Uint8List bytes, String nombre, String mime) async {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final enlace = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = nombre;
  enlace.style.display = 'none';
  web.document.body!.appendChild(enlace);
  enlace.click();
  enlace.remove();
  // Safari cancela la descarga si la URL se revoca en el mismo instante.
  await Future<void>.delayed(const Duration(seconds: 2));
  web.URL.revokeObjectURL(url);
}
