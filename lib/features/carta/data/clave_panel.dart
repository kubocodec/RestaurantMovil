import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// La clave del panel de la carta digital, guardada en el equipo.
///
/// NO viaja dentro de la app: va compilada en ningún lado. La escribe el
/// proveedor una vez en cada equipo desde el que administre cartas, y se
/// guarda por usuario, igual que las preferencias del cobro: si dos personas
/// comparten la PC, la de una no le sirve a la otra.
///
/// Se guarda en el almacenamiento seguro y no en SharedPreferences porque es
/// un secreto: con ella se pueden publicar o borrar las cartas de todos los
/// restaurantes.
class ClavePanelCarta {
  ClavePanelCarta._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _clave(String usuarioId) => 'carta_clave_panel_$usuarioId';

  static Future<String?> leer(String usuarioId) async {
    if (usuarioId.isEmpty) return null;
    try {
      return await _storage.read(key: _clave(usuarioId));
    } catch (_) {
      // En el navegador el almacenamiento puede estar bloqueado (modo
      // privado, datos del sitio borrados). Se pide la clave de nuevo en vez
      // de romper la pantalla.
      return null;
    }
  }

  static Future<void> guardar(String usuarioId, String clave) async {
    if (usuarioId.isEmpty) return;
    await _storage.write(key: _clave(usuarioId), value: clave);
  }

  static Future<void> borrar(String usuarioId) async {
    if (usuarioId.isEmpty) return;
    try {
      await _storage.delete(key: _clave(usuarioId));
    } catch (_) {}
  }
}
