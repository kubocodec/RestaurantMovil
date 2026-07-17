import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/mesa_model.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/comanda_printer.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';
import '../data/mesas_repository.dart';

class _CartItem {
  final PlatoModel plato;
  int cantidad = 1;
  String? notas;

  /// EN_MESA o PARA_LLEVAR: cada plato puede ser distinto (ej. comen en la
  /// mesa pero piden un postre para llevar).
  String tipoServicio;

  _CartItem(this.plato, {this.tipoServicio = 'EN_MESA'});
  double get subtotal => plato.precio * cantidad;
  bool get esParaLlevar => tipoServicio == 'PARA_LLEVAR';
}

class OrdenScreen extends StatefulWidget {
  /// Null cuando el cliente no ocupa mesa: pedido solo para llevar.
  final String? mesaId;
  final String mesaNombre;
  final bool isLibre;

  /// Orden para llevar ya creada: se abre para verla, agregar platos o
  /// cobrarla (las órdenes de mesa se encuentran por la mesa, no por id).
  final String? ordenId;

  const OrdenScreen({
    super.key,
    this.mesaId,
    this.mesaNombre = 'Para llevar',
    this.isLibre = true,
    this.ordenId,
  });

  bool get esParaLlevar => mesaId == null;

  @override
  State<OrdenScreen> createState() => _OrdenScreenState();
}

class _OrdenScreenState extends State<OrdenScreen> {
  final _repo = OrdenesRepository();
  List<PlatoModel> _platos = [];
  OrdenModel? _ordenExistente;
  bool _loading = true;
  bool _enviando = false;
  String? _error;
  final List<_CartItem> _carrito = [];
  late String _tipoOrden = widget.esParaLlevar ? 'PARA_LLEVAR' : 'EN_MESA';
  String? _categoriaFiltro;
  // Con muchas categorías el scroll horizontal era incómodo: por defecto se
  // muestran todas en varias filas y el mesero puede colapsarlas a una.
  bool _categoriasExpandidas = true;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  /// Solo cajero y admin pueden cobrar (el mesero toma pedidos).
  bool get _puedeCobrar {
    final s = context.read<AuthBloc>().state;
    if (s is! AuthAuthenticated) return false;
    final rol = s.user.rol;
    return rol == UserRole.cajero || rol == UserRole.admin || rol == UserRole.superadmin;
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // En paralelo: menú y órdenes activas en un solo viaje de red.
      // La orden activa de la mesa se busca SIEMPRE (no confiar en el query
      // param 'libre': la pantalla anterior puede tener el estado desfasado
      // y crearíamos una orden duplicada sobre una mesa ocupada).
      final resultados = await Future.wait([
        _repo.getPlatosBySucursal(_sucursalId),
        _repo.getOrdenesActivas(_sucursalId),
      ]);
      final platos  = resultados[0] as List<PlatoModel>;
      final activas = resultados[1] as List<OrdenModel>;
      OrdenModel? existente;
      if (widget.ordenId != null) {
        // Orden para llevar existente: se abre directo por su id
        existente = await _repo.getOrden(widget.ordenId!);
        // Ya cobrada/cancelada: avisar y salir; esta pantalla ya no
        // tiene nada que hacer (evita agregar platos a una orden cerrada)
        if (existente.estado == 'CERRADA' || existente.estado == 'CANCELADA') {
          if (!mounted) return;
          final cerrada = existente.estado == 'CERRADA';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(cerrada
                ? 'La orden #${existente.numeroOrden} ya fue cobrada y cerrada'
                : 'La orden #${existente.numeroOrden} fue cancelada'),
            backgroundColor: cerrada ? AppColors.success : AppColors.warning,
          ));
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/mesero/mesas');
          }
          return;
        }
      } else if (!widget.esParaLlevar) {
        final resumen = activas.where((o) => o.mesaId == widget.mesaId).firstOrNull;
        if (resumen != null) {
          // El listado de activas no incluye los ítems: cargar la orden completa
          existente = await _repo.getOrden(resumen.ordenId);
        }
      }
      // Sin ordenId y sin mesa: pedido para llevar nuevo, no reutiliza órdenes
      if (!mounted) return;
      setState(() {
        _platos = platos;
        _ordenExistente = existente;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  void _addToCart(PlatoModel plato) {
    setState(() {
      final idx = _carrito.indexWhere((i) => i.plato.platoId == plato.platoId);
      if (idx >= 0) {
        _carrito[idx].cantidad++;
      } else {
        // Hereda el tipo elegido arriba; se puede cambiar por plato en el carrito
        _carrito.add(_CartItem(plato, tipoServicio: _tipoOrden));
      }
    });
  }

  void _removeFromCart(PlatoModel plato) {
    setState(() {
      final idx = _carrito.indexWhere((i) => i.plato.platoId == plato.platoId);
      if (idx >= 0) {
        if (_carrito[idx].cantidad > 1) {
          _carrito[idx].cantidad--;
        } else {
          _carrito.removeAt(idx);
        }
      }
    });
  }

  int _inCart(PlatoModel plato) {
    final matches = _carrito.where((i) => i.plato.platoId == plato.platoId);
    return matches.isEmpty ? 0 : matches.first.cantidad;
  }

  double get _total => _carrito.fold(0, (s, i) => s + i.subtotal);
  int get _totalItems => _carrito.fold(0, (s, i) => s + i.cantidad);

  Future<void> _confirmarOrden() async {
    if (_carrito.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar orden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.esParaLlevar ? 'Pedido para llevar' : 'Mesa: ${widget.mesaNombre}'),
            const Divider(),
            ..._carrito.map((i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(
                    '${i.cantidad}x ${i.plato.nombrePlato}${i.esParaLlevar ? ' (llevar)' : ''}',
                    style: const TextStyle(fontSize: 13, fontFamily: 'Poppins'))),
                  Text('\$${i.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Poppins', fontSize: 13)),
                ],
              ),
            )),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
                Text('\$${_total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontFamily: 'Poppins', fontSize: 16)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar a cocina')),
        ],
      ),
    );
    if (confirmed == true) await _enviarOrden();
  }

  Future<void> _enviarOrden() async {
    setState(() => _enviando = true);
    final authState = context.read<AuthBloc>().state;
    final mesero = authState is AuthAuthenticated ? authState.user.nombre : '';
    try {
      OrdenModel orden;
      if (_ordenExistente != null) {
        orden = _ordenExistente!;
      } else {
        orden = await _repo.crearOrden(
          mesaId: widget.mesaId,
          // Sin mesa el backend necesita la sucursal para la orden
          sucursalId: widget.esParaLlevar ? _sucursalId : null,
          tipoOrden: widget.esParaLlevar ? 'PARA_LLEVAR' : _tipoOrden,
          tipoOrigen: 'MESERO',
        );
      }

      for (final item in _carrito) {
        await _repo.agregarDetalle(
          ordenId: orden.ordenId,
          platoId: item.plato.platoId,
          cantidad: item.cantidad,
          tipoServicio: item.tipoServicio,
          observaciones: item.notas,
        );
      }

      // Marca los ítems como ENVIADO y obtiene su impresora asignada
      final enviados = await _repo.enviarACocina(orden.ordenId);

      // Imprime las comandas agrupadas por impresora (cocina, barra, etc.)
      final resultados = await ComandaPrinter.imprimirComandas(
        mesa: widget.mesaNombre,
        numeroOrden: orden.numeroOrden,
        mesero: mesero,
        detalles: enviados,
      );

      if (mounted) {
        final fallidas = resultados.where((r) => !r.ok).toList();
        if (fallidas.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(resultados.isEmpty
                ? '¡Orden enviada a cocina!'
                : '¡Orden enviada! Comandas impresas: ${resultados.map((r) => r.via == 'Bluetooth' ? '${r.impresora} (BT)' : r.impresora).join(', ')}'),
            backgroundColor: AppColors.success,
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Orden enviada, pero falló la impresión en: ${fallidas.map((r) => r.impresora).join(', ')}. Revisa la impresora.'),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 5),
          ));
        }
        // pop (no go): así el await del push en MesasScreen se completa
        // y la pantalla de mesas recarga mostrando la mesa OCUPADA.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/mesero/mesas');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// El cliente se cambió de mesa: elegir una mesa libre y mover la orden
  /// para que el mesero no la pierda de vista.
  Future<void> _cambiarMesa() async {
    final orden = _ordenExistente;
    if (orden == null) return;

    List<MesaModel> libres;
    try {
      final mesas = await MesasRepository().getMesasBySucursal(_sucursalId);
      libres = mesas.where((m) => m.isLibre && m.mesaId != widget.mesaId).toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
      );
      return;
    }
    if (!mounted) return;
    if (libres.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay mesas libres para mover la orden'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    final destino = await showModalBottomSheet<MesaModel>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ElegirMesaSheet(
        titulo: 'Mover orden #${orden.numeroOrden}',
        subtitulo: 'De ${widget.mesaNombre} a una mesa libre:',
        mesas: libres,
      ),
    );
    if (destino == null || !mounted) return;

    setState(() => _enviando = true);
    try {
      await _repo.cambiarMesa(orden.ordenId, destino.mesaId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Orden #${orden.numeroOrden} movida a la mesa ${destino.numeroMesa}'),
        backgroundColor: AppColors.success,
      ));
      // Volver a mesas: esta pantalla quedó apuntando a la mesa anterior
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/mesero/mesas');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// El cliente ya no quiere todos los platos aquí (ej. pidió 3 tigrillos y
  /// se queda con 1): elegir cantidades por ítem y pasarlas a otra mesa.
  /// Si la mesa destino tiene orden abierta se suman a ella; si está libre
  /// se crea una orden nueva.
  Future<void> _moverItems() async {
    final orden = _ordenExistente;
    if (orden == null) return;

    final movibles = orden.detalles
        .where((d) => d.estado != 'CANCELADO' && d.cantidad - d.cantidadFacturada > 0)
        .toList();
    if (movibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay items que se puedan mover (ya están cobrados o cancelados)'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    // Paso 1: elegir qué items y cuántas unidades
    final seleccion = await showModalBottomSheet<Map<String, int>>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MoverItemsSheet(numeroOrden: orden.numeroOrden, detalles: movibles),
    );
    if (seleccion == null || seleccion.isEmpty || !mounted) return;

    // Paso 2: elegir mesa destino (libre u ocupada; ocupada = se suma a su orden)
    List<MesaModel> candidatas;
    try {
      final mesas = await MesasRepository().getMesasBySucursal(_sucursalId);
      candidatas = mesas
          .where((m) => (m.isLibre || m.isOcupada) && m.mesaId != widget.mesaId)
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
      );
      return;
    }
    if (!mounted) return;
    if (candidatas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay otras mesas disponibles'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    final totalUnidades = seleccion.values.fold(0, (s, n) => s + n);
    final destino = await showModalBottomSheet<MesaModel>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ElegirMesaSheet(
        titulo: 'Mover $totalUnidades item${totalUnidades == 1 ? '' : 's'} de la orden #${orden.numeroOrden}',
        subtitulo: 'Elige la mesa destino (si está ocupada, se suman a su orden):',
        mesas: candidatas,
      ),
    );
    if (destino == null || !mounted) return;

    // Paso 3: mover
    setState(() => _enviando = true);
    try {
      final ordenDestino = await _repo.moverItems(
        ordenId: orden.ordenId,
        mesaDestinoId: destino.mesaId,
        cantidadesPorDetalle: seleccion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Items movidos a la mesa ${destino.numeroMesa} (orden #${ordenDestino.numeroOrden})'),
        backgroundColor: AppColors.success,
      ));
      // Recargar: la orden origen quedó con menos items (o cancelada si se movió todo)
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Anula la orden con motivo OBLIGATORIO. No se borra nada: queda
  /// registrada con su detalle, el motivo y quién anuló, y el admin la ve
  /// en Reportes → Órdenes anuladas (ej. el cliente pidió pero se fue).
  Future<void> _anularOrden() async {
    final orden = _ordenExistente;
    if (orden == null) return;
    if (orden.detalles.any((d) => d.estado != 'CANCELADO' && d.cantidadFacturada > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('La orden tiene unidades ya cobradas: anula primero sus comprobantes'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    final ctrl = TextEditingController();
    String? errorMotivo;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Anular orden #${orden.numeroOrden}',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La orden no se borra: queda registrada con sus '
                '${orden.detalles.length} items y este motivo para que el '
                'administrador vea qué pasó.',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 2,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Motivo (obligatorio)',
                  hintText: 'ej: el cliente tuvo que irse',
                  errorText: errorMotivo,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                if (ctrl.text.trim().isEmpty) {
                  setDialog(() => errorMotivo = 'Escribe el motivo de la anulación');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Anular orden'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _enviando = true);
    try {
      await _repo.anularOrden(orden.ordenId, ctrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Orden #${orden.numeroOrden} anulada'),
        backgroundColor: AppColors.success,
      ));
      // Volver a mesas: la mesa quedó libre
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/mesero/mesas');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.esParaLlevar && _ordenExistente != null
            ? 'Para llevar · #${_ordenExistente!.numeroOrden}'
            : widget.mesaNombre),
        actions: [
          // El cliente se cambió de sitio: mover la orden a otra mesa libre
          if (!widget.esParaLlevar && _ordenExistente != null)
            IconButton(
              tooltip: 'Cambiar de mesa',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: _enviando ? null : _cambiarMesa,
            ),
          // Mover solo algunos items (o unidades) a otra mesa
          if (_ordenExistente != null)
            IconButton(
              tooltip: 'Mover items a otra mesa',
              icon: const Icon(Icons.call_split_rounded),
              onPressed: _enviando ? null : _moverItems,
            ),
          // Anular con motivo obligatorio (queda registrada para el admin).
          // Solo cajero/admin: el mesero no puede anular órdenes.
          if (_ordenExistente != null && _puedeCobrar)
            IconButton(
              tooltip: 'Anular orden',
              icon: const Icon(Icons.cancel_outlined),
              onPressed: _enviando ? null : _anularOrden,
            ),
          if (_totalItems > 0)
            Stack(
              children: [
                IconButton(icon: const Icon(Icons.shopping_cart_outlined), onPressed: _mostrarCarrito),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$_totalItems',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
      bottomNavigationBar: _totalItems > 0
          ? _buildBottomBar()
          : (_mostrarCobrar ? _buildCobrarBar() : null),
    );
  }

  bool get _mostrarCobrar =>
      !_loading &&
      _ordenExistente != null &&
      _ordenExistente!.detallesNoFacturados.isNotEmpty &&
      _puedeCobrar;

  Widget _buildCobrarBar() {
    final orden = _ordenExistente!;
    // Con cuentas divididas puede haber unidades ya cobradas: solo lo pendiente
    final totalPorCobrar = orden.detallesNoFacturados.fold(0.0, (s, d) => s + d.subtotalPendiente);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Por cobrar',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
              Text('\$${totalPorCobrar.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 18, color: AppColors.cajeroColor)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.cajeroColor),
              onPressed: () async {
                await context.push('/cajero/factura/${orden.ordenId}');
                if (mounted) _load();
              },
              icon: const Icon(Icons.point_of_sale_rounded),
              label: const Text('Cobrar'),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildTipoOrden(),
        if (_ordenExistente != null) _buildOrdenActivaBanner(_ordenExistente!),
        _buildBusqueda(),
        _buildCategorias(),
        Expanded(child: _buildPlatosList()),
      ],
    );
  }

  Widget _buildBusqueda() {
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: _busquedaCtrl,
          onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar plato...',
            hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
            suffixIcon: _busqueda.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      _busquedaCtrl.clear();
                      setState(() => _busqueda = '');
                    },
                  ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  List<String> get _categorias =>
      _platos.map((p) => p.categoria).where((c) => c.isNotEmpty).toSet().toList()..sort();

  Widget _buildCategorias() {
    final categorias = _categorias;
    if (categorias.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[
      _TipoChip(
        label: 'Todos',
        icon: Icons.restaurant_menu_outlined,
        selected: _categoriaFiltro == null,
        onTap: () => setState(() => _categoriaFiltro = null),
      ),
      ...categorias.map((c) => _TipoChip(
        label: c,
        icon: Icons.label_outline,
        selected: _categoriaFiltro == c,
        onTap: () => setState(() => _categoriaFiltro = c),
      )),
    ];

    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _categoriasExpandidas
                // Todas visibles en varias filas: un toque para elegir
                ? Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Wrap(spacing: 8, runSpacing: 8, children: chips),
                  )
                // Colapsado: una fila con scroll horizontal (modo compacto)
                : SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 16),
                      children: [
                        for (final chip in chips)
                          Padding(padding: const EdgeInsets.only(right: 8), child: chip),
                      ],
                    ),
                  ),
          ),
          IconButton(
            tooltip: _categoriasExpandidas ? 'Colapsar categorías' : 'Ver todas las categorías',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              _categoriasExpandidas ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _categoriasExpandidas = !_categoriasExpandidas),
          ),
        ],
      ),
    );
  }

  Widget _buildTipoOrden() {
    // Pedido sin mesa: todo va para llevar, no hay nada que elegir
    if (widget.esParaLlevar) {
      return Container(
        color: AppColors.cardBackground,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.earth2.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.takeout_dining_outlined, color: AppColors.earth2, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Pedido para llevar · sin mesa',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.earth2)),
            ),
          ],
        ),
      );
    }
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Expanded(
            child: Text('Los platos nuevos se agregan como:',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
          _TipoChip(
            label: 'En mesa', icon: Icons.table_restaurant_outlined,
            selected: _tipoOrden == 'EN_MESA',
            onTap: () => setState(() => _tipoOrden = 'EN_MESA'),
          ),
          const SizedBox(width: 8),
          _TipoChip(
            label: 'Para llevar', icon: Icons.takeout_dining_outlined,
            selected: _tipoOrden == 'PARA_LLEVAR',
            onTap: () => setState(() => _tipoOrden = 'PARA_LLEVAR'),
          ),
        ],
      ),
    );
  }

  /// Barra compacta de una sola línea: el detalle completo se abre en una
  /// hoja inferior para no quitarle espacio al menú ni solaparse con las
  /// categorías.
  Widget _buildOrdenActivaBanner(OrdenModel o) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.mesaOcupada.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mesaOcupada.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _mostrarPedidoActual(o),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.receipt_outlined, color: AppColors.mesaOcupada, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Orden #${o.numeroOrden} · ${o.detalles.length} items · \$${o.total.toStringAsFixed(2)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12.5,
                    fontWeight: FontWeight.w600, color: AppColors.mesaOcupada),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.mesaOcupada,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('Ver pedido',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarPedidoActual(OrdenModel o) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        expand: false,
        builder: (_, ctrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Pedido · Orden #${o.numeroOrden}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${o.detalles.length} items',
                    style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                itemCount: o.detalles.length,
                itemBuilder: (_, i) {
                  final d = o.detalles[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.mesaOcupada.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${d.cantidad}x',
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                              fontSize: 12, color: AppColors.mesaOcupada)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.nombrePlato,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                              if (d.observaciones != null && d.observaciones!.isNotEmpty)
                                Text('Nota: ${d.observaciones}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 11,
                                    color: AppColors.warning, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        _EstadoDetalleChip(estado: d.estado),
                        const SizedBox(width: 8),
                        Text('\$${d.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(ctx).padding.bottom),
              decoration: const BoxDecoration(
                color: AppColors.cardBackground,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15)),
                  Text('\$${o.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 18, color: AppColors.mesaOcupada)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatosList() {
    var visibles = _categoriaFiltro == null
        ? _platos
        : _platos.where((p) => p.categoria == _categoriaFiltro).toList();
    if (_busqueda.isNotEmpty) {
      visibles = visibles
          .where((p) => p.nombrePlato.toLowerCase().contains(_busqueda))
          .toList();
    }
    if (visibles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_food_outlined, size: 64, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              _busqueda.isNotEmpty
                  ? 'Sin resultados para "$_busqueda"'
                  : 'No hay platos disponibles',
              style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: visibles.length,
      itemBuilder: (_, i) => _PlatoTile(
        plato: visibles[i],
        cantidad: _inCart(visibles[i]),
        onAdd: () => _addToCart(visibles[i]),
        onRemove: () => _removeFromCart(visibles[i]),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_totalItems items',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
              Text('\$${_total.toStringAsFixed(2)}',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primary)),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _enviando ? null : _confirmarOrden,
              icon: _enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined),
              label: Text(_enviando ? 'Enviando...' : 'Enviar a cocina'),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Poppins')),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      ),
    );
  }

  void _mostrarCarrito() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => _CarritoSheet(
          carrito: _carrito,
          total: _total,
          soloParaLlevar: widget.esParaLlevar,
          scrollController: ctrl,
          onRemove: (plato) { Navigator.pop(ctx); _removeFromCart(plato); },
          onNota: (item) { Navigator.pop(ctx); _editarNota(item); },
          onConfirm: () { Navigator.pop(ctx); _confirmarOrden(); },
        ),
      ),
    );
  }

  void _editarNota(_CartItem item) {
    final ctrl = TextEditingController(text: item.notas ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.plato.nombrePlato,
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Nota para cocina',
            hintText: 'ej: sin cebolla, término medio',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                final texto = ctrl.text.trim();
                item.notas = texto.isEmpty ? null : texto;
              });
              _mostrarCarrito();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

// ── Subwidgets ───────────────────────────────────────────────────────────────

/// Hoja para elegir la mesa a la que se mueve una orden o algunos items.
/// Colorea cada mesa según su estado (libre/ocupada).
class _ElegirMesaSheet extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final List<MesaModel> mesas;

  const _ElegirMesaSheet({
    required this.titulo,
    required this.subtitulo,
    required this.mesas,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(titulo,
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitulo,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
              itemCount: mesas.length,
              itemBuilder: (ctx, i) {
                final m = mesas[i];
                final color = m.isOcupada ? AppColors.mesaOcupada : AppColors.mesaLibre;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: ListTile(
                    onTap: () => Navigator.pop(ctx, m),
                    leading: Icon(
                      m.isOcupada ? Icons.people_alt_outlined : Icons.table_restaurant_outlined,
                      color: color),
                    title: Text(m.numeroMesa,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(
                      [
                        if (m.nombreSalon.isNotEmpty) m.nombreSalon,
                        m.isOcupada ? 'Ocupada' : 'Libre',
                      ].join(' · '),
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                        color: m.isOcupada ? AppColors.mesaOcupada : AppColors.textSecondary)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 2),
                        Text('${m.capacidad}',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja para elegir qué items (y cuántas unidades de cada uno) se mueven
/// a otra mesa. Solo se ofrecen las unidades aún no cobradas.
class _MoverItemsSheet extends StatefulWidget {
  final int numeroOrden;
  final List<DetalleOrdenModel> detalles;

  const _MoverItemsSheet({required this.numeroOrden, required this.detalles});

  @override
  State<_MoverItemsSheet> createState() => _MoverItemsSheetState();
}

class _MoverItemsSheetState extends State<_MoverItemsSheet> {
  /// detalleId -> unidades a mover (0 = no se mueve)
  final Map<String, int> _seleccion = {};

  int _max(DetalleOrdenModel d) => d.cantidad - d.cantidadFacturada;
  int _de(DetalleOrdenModel d) => _seleccion[d.ordenDetalleId] ?? 0;

  void _cambiar(DetalleOrdenModel d, int delta) {
    setState(() {
      final nuevo = (_de(d) + delta).clamp(0, _max(d));
      if (nuevo == 0) {
        _seleccion.remove(d.ordenDetalleId);
      } else {
        _seleccion[d.ordenDetalleId] = nuevo;
      }
    });
  }

  int get _totalSeleccionado => _seleccion.values.fold(0, (s, n) => s + n);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.call_split_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Mover items de la orden #${widget.numeroOrden}',
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Elige cuántas unidades de cada plato pasan a otra mesa:',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.all(16),
              itemCount: widget.detalles.length,
              itemBuilder: (_, i) {
                final d = widget.detalles[i];
                final sel = _de(d);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: sel > 0
                        ? Border.all(color: AppColors.primary, width: 1.5)
                        : Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.nombrePlato,
                              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              d.cantidadFacturada > 0
                                  ? 'En la mesa: ${d.cantidad} (${d.cantidadFacturada} ya cobrados) · se pueden mover ${_max(d)}'
                                  : 'En la mesa: ${d.cantidad}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      // Stepper - N +
                      GestureDetector(
                        onTap: sel > 0 ? () => _cambiar(d, -1) : null,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: sel > 0 ? AppColors.surfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.remove, size: 18,
                            color: sel > 0 ? AppColors.textPrimary : AppColors.textHint),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('$sel',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16,
                            color: sel > 0 ? AppColors.primary : AppColors.textHint)),
                      ),
                      GestureDetector(
                        onTap: sel < _max(d) ? () => _cambiar(d, 1) : null,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: sel < _max(d) ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add, size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: AppColors.cardBackground,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _totalSeleccionado == 0
                    ? null
                    : () => Navigator.pop(context, Map<String, int>.from(_seleccion)),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(_totalSeleccionado == 0
                    ? 'Elige al menos un item'
                    : 'Elegir mesa destino ($_totalSeleccionado item${_totalSeleccionado == 1 ? '' : 's'})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoDetalleChip extends StatelessWidget {
  final String estado;
  const _EstadoDetalleChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (estado) {
      'PENDIENTE'      => ('Pendiente', AppColors.textSecondary),
      'ENVIADO'        => ('En cocina', AppColors.warning),
      'EN_PREPARACION' => ('Preparando', AppColors.estadoEnProceso),
      'LISTO'          => ('Listo', AppColors.estadoListo),
      'ENTREGADO'      => ('Entregado', AppColors.success),
      'CANCELADO'      => ('Cancelado', AppColors.error),
      _                => (estado, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 9.5,
          fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TipoChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _PlatoTile extends StatelessWidget {
  final PlatoModel plato;
  final int cantidad;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _PlatoTile({required this.plato, required this.cantidad, required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: cantidad > 0 ? Border.all(color: AppColors.primary, width: 1.5) : null,
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plato.nombrePlato,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                // Descripción del plato: discreta, máximo 2 líneas
                if (plato.descripcionPlato?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(plato.descripcionPlato!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 11.5, height: 1.3,
                      color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 6),
                Text('\$${plato.precio.toStringAsFixed(2)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (cantidad == 0)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            )
          else
            Row(
              children: [
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.remove, size: 18, color: AppColors.textPrimary),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('$cantidad',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add, size: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CarritoSheet extends StatefulWidget {
  final List<_CartItem> carrito;
  final double total;
  /// Pedido sin mesa: no se puede cambiar ningún plato a "en mesa".
  final bool soloParaLlevar;
  final ScrollController scrollController;
  final Function(PlatoModel) onRemove;
  final Function(_CartItem) onNota;
  final VoidCallback onConfirm;

  const _CarritoSheet({
    required this.carrito,
    required this.total,
    this.soloParaLlevar = false,
    required this.scrollController,
    required this.onRemove,
    required this.onNota,
    required this.onConfirm,
  });

  @override
  State<_CarritoSheet> createState() => _CarritoSheetState();
}

class _CarritoSheetState extends State<_CarritoSheet> {
  List<_CartItem> get carrito => widget.carrito;
  double get total => widget.total;
  ScrollController get scrollController => widget.scrollController;
  Function(PlatoModel) get onRemove => widget.onRemove;
  Function(_CartItem) get onNota => widget.onNota;
  VoidCallback get onConfirm => widget.onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tu orden', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('${carrito.length} items',
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: carrito.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: Text('${i.cantidad}',
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.plato.nombrePlato,
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('\$${i.plato.precio.toStringAsFixed(2)} c/u',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        // Cada plato puede ir en mesa o para llevar
                        // (salvo pedidos sin mesa: todo va para llevar)
                        GestureDetector(
                          onTap: widget.soloParaLlevar ? null : () => setState(() =>
                            i.tipoServicio = i.esParaLlevar ? 'EN_MESA' : 'PARA_LLEVAR'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: i.esParaLlevar
                                  ? AppColors.earth2.withValues(alpha: 0.15)
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: i.esParaLlevar ? AppColors.earth2 : AppColors.divider),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  i.esParaLlevar
                                      ? Icons.takeout_dining_outlined
                                      : Icons.table_restaurant_outlined,
                                  size: 12,
                                  color: i.esParaLlevar ? AppColors.earth2 : AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  i.esParaLlevar ? 'Para llevar' : 'En mesa',
                                  style: TextStyle(
                                    fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
                                    color: i.esParaLlevar ? AppColors.earth2 : AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                        if (i.notas != null && i.notas!.isNotEmpty)
                          Text('Nota: ${i.notas}',
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 11,
                              color: AppColors.warning, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  Text('\$${i.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => onNota(i),
                    child: Icon(
                      (i.notas?.isNotEmpty ?? false) ? Icons.edit_note : Icons.note_add_outlined,
                      size: 20,
                      color: (i.notas?.isNotEmpty ?? false) ? AppColors.warning : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => onRemove(i.plato),
                    child: const Icon(Icons.close, size: 18, color: AppColors.textHint),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        Container(
          // Deja libre la franja de los botones de navegación del sistema
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: AppColors.cardBackground,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total estimado',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 16)),
                  Text('\$${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Confirmar y enviar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
