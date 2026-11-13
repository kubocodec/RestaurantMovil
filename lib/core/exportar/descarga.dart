// En el navegador, la descarga real; en el celular y en Windows, una que
// lanza error. La elección es en tiempo de compilación: así `package:web` no
// entra nunca en el APK.
export 'descarga_stub.dart' if (dart.library.js_interop) 'descarga_web.dart';

/// Tipo MIME de un libro de Excel (.xlsx).
const String mimeXlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
