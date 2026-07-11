import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/comanda_printer.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';

class _CartItem {
  final PlatoModel plato;
  int cantidad = 1;
  String? notas;

  _CartItem(this.plato);
  double get subtotal => plato.precio * cantidad;
}

class OrdenScreen extends StatefulWidget {
  final String mesaId;
  final String mesaNombre;
  final bool isLibre;

  const OrdenScreen({
    super.key,
    required this.mesaId,
    required this.mesaNombre,
    required this.isLibre,
  });

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
  String _tipoOrden = 'EN_MESA';
  String? _categoriaFiltro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      final platos = await _repo.getPlatosBySucursal(_sucursalId);
      OrdenModel? existente;
      if (!widget.isLibre) {
        final activas = await _repo.getOrdenesActivas(_sucursalId);
        final resumen = activas.where((o) => o.mesaId == widget.mesaId).firstOrNull;
        if (resumen != null) {
          // El listado de activas no incluye los ítems: cargar la orden completa
          existente = await _repo.getOrden(resumen.ordenId);
        }
      }
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
        _carrito.add(_CartItem(plato));
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
            Text('Mesa: ${widget.mesaNombre}'),
            Text('Tipo: ${_tipoOrden == 'EN_MESA' ? 'En mesa' : 'Para llevar'}'),
            const Divider(),
            ..._carrito.map((i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('${i.cantidad}x ${i.plato.nombrePlato}',
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
          tipoOrden: _tipoOrden,
          tipoOrigen: 'MESERO',
        );
      }

      for (final item in _carrito) {
        await _repo.agregarDetalle(
          ordenId: orden.ordenId,
          platoId: item.plato.platoId,
          cantidad: item.cantidad,
          tipoServicio: _tipoOrden == 'EN_MESA' ? 'EN_MESA' : 'PARA_LLEVAR',
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
                : '¡Orden enviada! Comandas impresas: ${resultados.map((r) => r.impresora).join(', ')}'),
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
        title: Text(widget.mesaNombre),
        actions: [
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _buildError()
              : _buildBody(),
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
    final totalPorCobrar = orden.detallesNoFacturados.fold(0.0, (s, d) => s + d.subtotal);
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
        _buildCategorias(),
        Expanded(child: _buildPlatosList()),
      ],
    );
  }

  List<String> get _categorias =>
      _platos.map((p) => p.categoria).where((c) => c.isNotEmpty).toSet().toList()..sort();

  Widget _buildCategorias() {
    final categorias = _categorias;
    if (categorias.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TipoChip(
                label: 'Todos',
                icon: Icons.restaurant_menu_outlined,
                selected: _categoriaFiltro == null,
                onTap: () => setState(() => _categoriaFiltro = null),
              ),
            ),
            ...categorias.map((c) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TipoChip(
                label: c,
                icon: Icons.label_outline,
                selected: _categoriaFiltro == c,
                onTap: () => setState(() => _categoriaFiltro = c),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoOrden() {
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text('Tipo:', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(width: 12),
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

  Widget _buildOrdenActivaBanner(OrdenModel o) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.mesaOcupada.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mesaOcupada.withValues(alpha: 0.4)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: const Icon(Icons.receipt_outlined, color: AppColors.mesaOcupada, size: 20),
          title: Text(
            'Orden #${o.numeroOrden} · ${o.detalles.length} items · \$${o.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w600, color: AppColors.mesaOcupada),
          ),
          subtitle: const Text(
            'Toca para ver el pedido. Puedes agregar más platos.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
          ),
          children: [
            // Altura acotada con scroll interno: con muchos ítems el panel
            // no debe comerse la pantalla ni solaparse con el menú.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: o.detalles.map((d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Text('${d.cantidad}x',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 12, color: AppColors.mesaOcupada)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.nombrePlato,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5)),
                              if (d.observaciones != null && d.observaciones!.isNotEmpty)
                                Text('Nota: ${d.observaciones}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 10.5,
                                    color: AppColors.warning, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        _EstadoDetalleChip(estado: d.estado),
                        const SizedBox(width: 8),
                        Text('\$${d.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatosList() {
    final visibles = _categoriaFiltro == null
        ? _platos
        : _platos.where((p) => p.categoria == _categoriaFiltro).toList();
    if (visibles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_food_outlined, size: 64, color: AppColors.textHint),
            SizedBox(height: 12),
            Text('No hay platos disponibles',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
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

class _CarritoSheet extends StatelessWidget {
  final List<_CartItem> carrito;
  final double total;
  final ScrollController scrollController;
  final Function(PlatoModel) onRemove;
  final Function(_CartItem) onNota;
  final VoidCallback onConfirm;

  const _CarritoSheet({
    required this.carrito,
    required this.total,
    required this.scrollController,
    required this.onRemove,
    required this.onNota,
    required this.onConfirm,
  });

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
          padding: const EdgeInsets.all(20),
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
