// Es un script de terminal: imprimir es justamente lo que tiene que hacer.
// ignore_for_file: avoid_print
//
// Prueba manual del repositorio de la carta digital contra un servicio
// LOCAL. No toca producción. Se corre a mano:
//
//   dart run tool/prueba_carta.dart http://127.0.0.1:4600 clave-de-prueba-larga
//
// Ejercita el camino entero —listar, publicar, refrescar, quitar— con el
// mismo código que usa la pantalla, así un cambio en el contrato del
// servicio se ve acá y no cuando el cliente ya pegó el QR.
import 'package:restaurant_app/features/carta/data/carta_repository.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args[0] : 'http://127.0.0.1:4600';
  final clave = args.length > 1 ? args[1] : 'clave-de-prueba-larga';
  final repo = CartaRepository(clave, baseUrl: base);

  var fallos = 0;
  void revisar(String que, bool ok, [String detalle = '']) {
    print('${ok ? "ok  " : "FALLA"}  $que${detalle.isEmpty ? "" : "  -> $detalle"}');
    if (!ok) fallos++;
  }

  // --- Direcciones sugeridas ---
  revisar('slug sin tildes ni símbolos',
      CartaRepository.slugDesde('Asadero El Jardín & Café') == 'asadero-el-jardin-cafe',
      CartaRepository.slugDesde('Asadero El Jardín & Café'));
  revisar('slug sin guiones sueltos en los bordes',
      CartaRepository.slugDesde('  ¡Hola!  ') == 'hola',
      CartaRepository.slugDesde('  ¡Hola!  '));
  revisar('slug válido', CartaRepository.slugValido('el-horno'));
  revisar('slug con mayúscula rechazado', !CartaRepository.slugValido('El-Horno'));
  revisar('slug de una letra rechazado', !CartaRepository.slugValido('a'));

  // --- Clave equivocada ---
  try {
    await CartaRepository('clave-que-no-es', baseUrl: base).listar();
    revisar('clave mala rechazada', false, 'no falló');
  } catch (e) {
    revisar('clave mala rechazada', true);
  }

  // --- Camino completo ---
  const token = '11111111-2222-3333-4444-555555555555';
  const slug = 'prueba-repo';
  try {
    final antes = await repo.listar();
    revisar('listar devuelve negocios', antes.isNotEmpty, '${antes.length}');

    final n = await repo.publicar(
        slug: slug, token: token, nombre: 'Prueba Repo', tarifaIva: 15);
    revisar('publicar guarda el nombre', n.nombre == 'Prueba Repo', n.nombre);
    revisar('publicar guarda el token', n.token == token, n.token);
    revisar('publicar guarda el IVA', n.tarifaIva == 15, '${n.tarifaIva}');
    revisar('la url lleva el slug', n.url.endsWith('/$slug'), n.url);

    final despues = await repo.listar();
    revisar('el negocio nuevo aparece al listar',
        despues.any((x) => x.slug == slug));

    await repo.refrescar(slug);
    revisar('refrescar no falla', true);

    await repo.quitar(slug);
    final final_ = await repo.listar();
    revisar('quitar lo borra', !final_.any((x) => x.slug == slug));
  } catch (e) {
    revisar('camino completo', false, '$e');
  }

  // --- Token que el API no reconoce ---
  try {
    await repo.publicar(
        slug: 'prueba-token-malo',
        token: '99999999-9999-9999-9999-999999999999',
        nombre: 'No existe');
    revisar('token inexistente rechazado', false, 'lo aceptó');
  } catch (e) {
    revisar('token inexistente rechazado', true);
  }

  print(fallos == 0 ? '\nTodo en orden.' : '\n$fallos fallo(s).');
}
