import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

/// Un negocio publicado en la carta digital.
///
/// `token` es el de una mesa de la sucursal: el servicio de la carta lo usa
/// contra `/api/menu/publico/{token}` para saber de qué sucursal pedir el
/// menú. La mesa no se "ocupa" ni se entera; el token solo la ubica.
class NegocioCarta {
  final String slug;
  final String nombre;
  final String token;
  final double tarifaIva;

  /// De qué carta salió. Va en el modelo y no se toma de [ApiConstants]
  /// para que, apuntando el repositorio a una carta local, la url que se
  /// muestre sea esa y no la de producción.
  final String base;

  const NegocioCarta({
    required this.slug,
    required this.nombre,
    required this.token,
    required this.tarifaIva,
    required this.base,
  });

  factory NegocioCarta.fromJson(String slug, Map<String, dynamic> j, String base) =>
      NegocioCarta(
        slug: slug,
        nombre: j['nombre']?.toString() ?? slug,
        token: j['token']?.toString() ?? '',
        tarifaIva: (j['tarifaIva'] as num?)?.toDouble() ?? 0,
        base: base,
      );

  /// La dirección que se imprime en el QR.
  String get url => '$base/$slug';
}

/// Panel del servicio de la carta digital.
///
/// Se entra con una clave propia (`x-clave-panel`), no con el usuario de
/// Wasi: es otro servidor y no conoce a los usuarios del restaurante. La
/// clave la tiene el proveedor y se escribe una vez en el equipo.
class CartaRepository {
  /// Dio propio, NO el de [ApiClient]: ese le pega el JWT de Wasi a cada
  /// petición y este es otro servidor. Mandarle el token del usuario sería
  /// filtrárselo a un tercero sin ninguna necesidad.
  final Dio _dio;
  final String clave;
  final String base;

  /// [baseUrl] solo se pasa para apuntar a una carta que no es la de
  /// producción (una local, al probar). La app siempre usa la de
  /// [ApiConstants].
  CartaRepository(this.clave, {String? baseUrl})
      : base = baseUrl ?? ApiConstants.cartaBaseUrl,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? ApiConstants.cartaBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        ));

  Options get _opciones => Options(headers: {'x-clave-panel': clave});

  /// Todos los negocios publicados. Sirve además para comprobar la clave:
  /// con una clave mala el servicio responde 401.
  Future<List<NegocioCarta>> listar() async {
    final r = await _dio.get('/api/negocios', options: _opciones);
    final Map mapa = r.data['negocios'] ?? {};
    return mapa.entries
        .map((e) => NegocioCarta.fromJson(
            e.key.toString(), Map<String, dynamic>.from(e.value as Map), base))
        .toList()
      ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }

  /// Publica (o actualiza) la carta de una sucursal.
  ///
  /// El servicio comprueba el token contra el API de Wasi ANTES de guardar,
  /// así que si el token no sirve el error llega acá y no cuando el cliente
  /// ya pegó el QR en la mesa.
  Future<NegocioCarta> publicar({
    required String slug,
    required String token,
    required String nombre,
    double tarifaIva = 0,
  }) async {
    final r = await _dio.put(
      '/api/negocios/$slug',
      data: {'token': token, 'nombre': nombre, 'tarifaIva': tarifaIva},
      options: _opciones,
    );
    return NegocioCarta.fromJson(
        slug, Map<String, dynamic>.from(r.data['negocio'] as Map), base);
  }

  Future<void> quitar(String slug) async {
    await _dio.delete('/api/negocios/$slug', options: _opciones);
  }

  /// Vence el caché del servicio para que los cambios de precio o de
  /// disponibilidad se vean ya, sin esperar los 90 segundos.
  Future<void> refrescar(String slug) async {
    await _dio.post('/api/negocios/$slug/refrescar', options: _opciones);
  }

  /// Dirección sugerida a partir del nombre del negocio: minúsculas, sin
  /// tildes y con guiones. El servicio solo acepta `[a-z0-9-]`, de 2 a 40.
  static String slugDesde(String nombre) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const sin = 'aaaaaeeeeiiiiooooouuuunc';
    final b = StringBuffer();
    for (final c in nombre.toLowerCase().trim().runes) {
      final ch = String.fromCharCode(c);
      final i = con.indexOf(ch);
      b.write(i >= 0 ? sin[i] : ch);
    }
    final limpio = b
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return limpio.length > 40 ? limpio.substring(0, 40).replaceAll(RegExp(r'-+$'), '') : limpio;
  }

  /// Mismo criterio que `slugValido` del servicio: si acá se deja pasar algo
  /// que allá se rechaza, el error aparece recién al publicar.
  static bool slugValido(String slug) =>
      RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])$').hasMatch(slug);
}
