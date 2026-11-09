import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/mesa_model.dart';
import '../../../core/network/api_client.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../../facturacion/data/facturacion_repository.dart';
import '../../mesas/data/mesas_repository.dart';
import '../data/carta_repository.dart';
import '../data/clave_panel.dart';

/// Carta digital: publica el menú de la sucursal en una página pública y
/// muestra el QR que el restaurante imprime y pega en la mesa o en la puerta.
///
/// El cliente solo MIRA: no pide ni paga desde ahí. La página la sirve otro
/// servidor (ver [CartaRepository]); acá solo se le dice qué sucursal
/// publicar y con qué dirección.
class CartaDigitalScreen extends StatefulWidget {
  final String sucursalId;
  final String? sucursalNombre;

  const CartaDigitalScreen({
    super.key,
    required this.sucursalId,
    this.sucursalNombre,
  });

  @override
  State<CartaDigitalScreen> createState() => _CartaDigitalScreenState();
}

class _CartaDigitalScreenState extends State<CartaDigitalScreen> {
  // Los controladores viven acá y no dentro de un diálogo: uno creado y
  // destruido dentro de showDialog revienta con "used after being disposed",
  // porque la animación de cierre vuelve a dibujar el campo.
  final _claveCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _ivaCtrl = TextEditingController();

  String _usuarioId = '';
  String? _clave;

  bool _cargando = true;
  bool _guardando = false;
  /// Mostrando el formulario aunque la carta ya esté publicada (al tocar
  /// "Cambiar datos"). Hace falta recordar [_negocio] para saber en qué
  /// dirección estaba, y no dejar dos cartas colgando de la misma mesa.
  bool _editando = false;
  String? _error;

  List<MesaModel> _mesas = const [];
  MesaModel? _mesaElegida;
  NegocioCarta? _negocio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _claveCtrl.dispose();
    _slugCtrl.dispose();
    _nombreCtrl.dispose();
    _ivaCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final estado = context.read<AuthBloc>().state;
    _usuarioId = estado is AuthAuthenticated ? estado.user.id : '';
    _clave = await ClavePanelCarta.leer(_usuarioId);
    if (!mounted) return;
    if (_clave == null) {
      setState(() => _cargando = false);
      return;
    }
    await _cargar();
  }

  /// Mesas de la sucursal + negocios ya publicados. El negocio de ESTA
  /// sucursal es aquel cuyo token sea el de alguna de sus mesas: el servicio
  /// de la carta no sabe de sucursales, solo de tokens.
  Future<void> _cargar() async {
    final clave = _clave;
    if (clave == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final mesas = await MesasRepository().getMesasBySucursal(widget.sucursalId);
      final negocios = await CartaRepository(clave).listar();
      if (!mounted) return;

      final conToken = mesas
          .where((m) => (m.tokenSesion ?? '').isNotEmpty)
          .toList();
      final tokens = conToken.map((m) => m.tokenSesion).toSet();
      NegocioCarta? mio;
      for (final n in negocios) {
        if (tokens.contains(n.token)) {
          mio = n;
          break;
        }
      }
      MesaModel? mesaDelNegocio;
      if (mio != null) {
        for (final m in conToken) {
          if (m.tokenSesion == mio.token) {
            mesaDelNegocio = m;
            break;
          }
        }
      }

      setState(() {
        _mesas = conToken;
        _negocio = mio;
        _editando = false;
        _mesaElegida =
            mesaDelNegocio ?? (conToken.isNotEmpty ? conToken.first : null);
        _cargando = false;
      });
      _rellenarFormulario();
    } catch (e) {
      if (!mounted) return;
      // Una clave equivocada da 401 y el servicio no dice más: se avisa con
      // palabras y se deja volver a escribirla.
      final mensaje = ApiClient.parseError(e);
      setState(() {
        _error = mensaje;
        _cargando = false;
      });
    }
  }

  Future<void> _rellenarFormulario() async {
    final nombre = _negocio?.nombre ??
        (widget.sucursalNombre?.trim().isNotEmpty == true
            ? widget.sucursalNombre!.trim()
            : '');
    _nombreCtrl.text = nombre;
    _slugCtrl.text = _negocio?.slug ?? CartaRepository.slugDesde(nombre);

    if (_negocio != null) {
      _ivaCtrl.text = _formatoIva(_negocio!.tarifaIva);
      return;
    }
    // Sugerencia: la tarifa vigente del negocio, que es la que se le suma al
    // precio para mostrarle al cliente lo que va a pagar.
    try {
      final iva = await FacturacionRepository().getIvaVigente(widget.sucursalId);
      if (mounted && _ivaCtrl.text.isEmpty) {
        setState(() => _ivaCtrl.text = _formatoIva(iva ?? 0));
      }
    } catch (_) {
      if (mounted && _ivaCtrl.text.isEmpty) _ivaCtrl.text = '0';
    }
  }

  static String _formatoIva(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // ── Acciones ───────────────────────────────────────────────────────────────

  Future<void> _entrarConClave() async {
    final clave = _claveCtrl.text.trim();
    if (clave.isEmpty) return;
    setState(() => _guardando = true);
    try {
      // Se comprueba contra el servicio ANTES de guardarla: si está mal, el
      // error sale ahora y no la próxima vez que se abra la pantalla.
      await CartaRepository(clave).listar();
      await ClavePanelCarta.guardar(_usuarioId, clave);
      if (!mounted) return;
      _claveCtrl.clear();
      setState(() {
        _clave = clave;
        _guardando = false;
      });
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = ApiClient.parseError(e);
      });
    }
  }

  Future<void> _olvidarClave() async {
    await ClavePanelCarta.borrar(_usuarioId);
    if (!mounted) return;
    setState(() {
      _clave = null;
      _negocio = null;
      _error = null;
    });
  }

  Future<void> _publicar() async {
    final clave = _clave;
    final mesa = _mesaElegida;
    if (clave == null || mesa == null) return;

    final slug = _slugCtrl.text.trim().toLowerCase();
    final nombre = _nombreCtrl.text.trim();
    if (!CartaRepository.slugValido(slug)) {
      _avisar('La dirección solo admite minúsculas, números y guiones, '
          'de 2 a 40 caracteres.', AppColors.warning);
      return;
    }
    if (nombre.isEmpty) {
      _avisar('Ponle un nombre al negocio: es el que ve el cliente.',
          AppColors.warning);
      return;
    }

    // Republicar con otra dirección deja la anterior viva y colgando de la
    // MISMA mesa: dos cartas con el mismo token, y la pantalla ya no sabría
    // cuál es la de esta sucursal. Se pregunta antes, porque quitarla rompe
    // los QR que ya estén pegados.
    final anterior = _negocio;
    var quitarAnterior = false;
    if (anterior != null && anterior.slug != slug) {
      final respuesta = await _preguntarPorLaAnterior(anterior.slug, slug);
      if (respuesta == null || !mounted) return;
      quitarAnterior = respuesta;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _guardando = true);
    try {
      final negocio = await CartaRepository(clave).publicar(
        slug: slug,
        token: mesa.tokenSesion!,
        nombre: nombre,
        tarifaIva: double.tryParse(_ivaCtrl.text.replaceAll(',', '.')) ?? 0,
      );
      if (quitarAnterior && anterior != null) {
        await CartaRepository(clave).quitar(anterior.slug);
      }
      if (!mounted) return;
      setState(() {
        _negocio = negocio;
        _editando = false;
        _guardando = false;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(quitarAnterior
            ? 'Carta publicada; la dirección anterior quedó fuera'
            : 'Carta publicada'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      messenger.showSnackBar(SnackBar(
        content: Text(ApiClient.parseError(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  /// `true` quitar la anterior, `false` dejar las dos, `null` cancelar.
  Future<bool?> _preguntarPorLaAnterior(String vieja, String nueva) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cambiar la dirección',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: Text(
            'La carta pasa de /$vieja a /$nueva.\n\n'
            'Si quitas la anterior, los QR que ya estén impresos con ella '
            'dejan de funcionar. Si la dejas, las dos direcciones muestran el '
            'mismo menú.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Dejar las dos')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Quitar la anterior')),
          ],
        ),
      );

  Future<void> _refrescar() async {
    final clave = _clave;
    final negocio = _negocio;
    if (clave == null || negocio == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _guardando = true);
    try {
      await CartaRepository(clave).refrescar(negocio.slug);
      if (!mounted) return;
      setState(() => _guardando = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('La carta ya muestra los precios de ahora'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      messenger.showSnackBar(SnackBar(
        content: Text(ApiClient.parseError(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _quitar() async {
    final clave = _clave;
    final negocio = _negocio;
    if (clave == null || negocio == null) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar la carta?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
          'Los QR ya impresos de ${negocio.slug} dejan de funcionar: '
          'quien los escanee no va a ver nada.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, quitar'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _guardando = true);
    try {
      await CartaRepository(clave).quitar(negocio.slug);
      if (!mounted) return;
      setState(() {
        _negocio = null;
        _guardando = false;
      });
      _rellenarFormulario();
      messenger.showSnackBar(const SnackBar(content: Text('Carta quitada')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      messenger.showSnackBar(SnackBar(
        content: Text(ApiClient.parseError(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _copiar(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _avisar('Enlace copiado', AppColors.success);
  }

  Future<void> _abrir(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo abrir el enlace'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  void _avisar(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: color));
  }

  // ── Pantalla ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Carta digital'),
        actions: [
          if (_clave != null) ...[
            IconButton(
              tooltip: 'Recargar',
              icon: const Icon(Icons.refresh),
              onPressed: _cargando ? null : _cargar,
            ),
            IconButton(
              tooltip: 'Olvidar la clave en este equipo',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _olvidarClave,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _clave == null
                    ? _formularioClave()
                    : _contenido(),
          ),
        ),
      ),
    );
  }

  Widget _formularioClave() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _aviso(
            Icons.key_rounded,
            'La carta vive en otro servidor, con su propia clave. Escríbela una '
            'vez y queda guardada en este equipo. Es la misma para todos los '
            'restaurantes, así que no se la des al dueño del local.',
            AppColors.info,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _claveCtrl,
            obscureText: true,
            autofillHints: const [],
            decoration: const InputDecoration(
              labelText: 'Clave del panel',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            onSubmitted: (_) => _entrarConClave(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppColors.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _guardando ? null : _entrarConClave,
              child: Text(_guardando ? 'Comprobando...' : 'Entrar'),
            ),
          ),
        ],
      );

  Widget _contenido() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                      onPressed: _cargar, child: const Text('Reintentar')),
                  TextButton(
                      onPressed: _olvidarClave,
                      child: const Text('Cambiar la clave')),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_mesas.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _aviso(
            Icons.table_restaurant_outlined,
            'Esta sucursal no tiene mesas, y hoy la carta se publica con el '
            'token QR de una mesa: es lo que el servidor usa para saber de qué '
            'sucursal es el menú. Crea una mesa (aunque no se use) o esperá a '
            'que el backend permita publicar por sucursal.',
            AppColors.warning,
          ),
        ],
      );
    }

    final negocio = _negocio;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: (negocio == null || _editando)
          ? _formularioPublicar()
          : _cartaPublicada(negocio),
    );
  }

  List<Widget> _formularioPublicar() => [
        _aviso(
          Icons.qr_code_2_rounded,
          'Publica el menú de esta sucursal en una página pública. El cliente '
          'escanea el QR y ve los platos con foto y precio: no pide ni paga '
          'desde ahí.',
          AppColors.info,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nombreCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre del negocio',
            helperText: 'El título que ve el cliente arriba de la carta',
          ),
          onChanged: (v) {
            // Mientras no la toquen, la dirección sigue al nombre.
            if (_slugCtrl.text.isEmpty ||
                _slugCtrl.text == CartaRepository.slugDesde(_nombreCtrl.text)) {
              _slugCtrl.text = CartaRepository.slugDesde(v);
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _slugCtrl,
          decoration: InputDecoration(
            labelText: 'Dirección de la carta',
            prefixText: '${Uri.parse(ApiConstants.cartaBaseUrl).host}/',
            helperText: 'Minúsculas, números y guiones',
          ),
        ),
        const SizedBox(height: 12),
        _selectorMesa(),
        const SizedBox(height: 12),
        TextField(
          controller: _ivaCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'IVA que se suma al precio (%)',
            helperText: 'Los precios del menú se guardan sin IVA. Poné 0 si en '
                'la carta querés mostrarlos tal cual.',
            helperMaxLines: 3,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _guardando ? null : _publicar,
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.public_rounded),
            label: Text(_guardando ? 'Publicando...' : 'Publicar la carta'),
          ),
        ),
      ];

  Widget _selectorMesa() => InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Mesa que identifica a la sucursal',
          helperText: 'Se usa solo su código QR para ubicar el menú; la mesa '
              'sigue libre y nadie la ocupa. Si después le regeneras el QR a '
              'esa mesa, la carta deja de funcionar.',
          helperMaxLines: 4,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<MesaModel>(
            isExpanded: true,
            value: _mesaElegida,
            items: [
              for (final m in _mesas)
                DropdownMenuItem(
                  value: m,
                  child: Text('${m.nombreSalon} · Mesa ${m.numeroMesa}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                ),
            ],
            onChanged: (m) => setState(() => _mesaElegida = m),
          ),
        ),
      );

  List<Widget> _cartaPublicada(NegocioCarta negocio) {
    final url = negocio.url;
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Text(negocio.nombre,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const SizedBox(height: 16),
            // Negro sobre blanco a propósito: es lo que mejor lee cualquier
            // cámara, y este QR se va a imprimir.
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              url,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _aviso(
        Icons.print_outlined,
        'Para pegarlo en la mesa: imprime esta pantalla desde el navegador '
        '(Ctrl+P) o sácale una captura. El QR no cambia mientras la carta siga '
        'publicada con la misma mesa.',
        AppColors.info,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _copiar(url),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar enlace'),
          ),
          OutlinedButton.icon(
            onPressed: () => _abrir(url),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Abrir'),
          ),
          OutlinedButton.icon(
            onPressed: _guardando ? null : _refrescar,
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Actualizar precios'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Text('Ajustes', style: _tituloSeccion),
      const SizedBox(height: 8),
      _dato('Mesa que la identifica', _nombreMesa(negocio.token)),
      _dato('IVA que se suma', '${_formatoIva(negocio.tarifaIva)} %'),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _guardando ? null : () => setState(() => _editando = true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Cambiar datos'),
          ),
          TextButton.icon(
            onPressed: _guardando ? null : _quitar,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            icon: const Icon(Icons.link_off_rounded, size: 18),
            label: const Text('Quitar la carta'),
          ),
        ],
      ),
    ];
  }

  String _nombreMesa(String token) {
    for (final m in _mesas) {
      if (m.tokenSesion == token) return '${m.nombreSalon} · Mesa ${m.numeroMesa}';
    }
    return 'una mesa que ya no existe';
  }

  static const _tituloSeccion = TextStyle(
      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15);

  Widget _dato(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(etiqueta,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(valor,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _aviso(IconData icono, String texto, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
}
