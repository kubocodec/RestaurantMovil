import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/network/api_client.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final platos = await _repo.getPlatosBySucursal(_sucursalId);
      OrdenModel? existente;
      if (!widget.isLibre) {
        final activas = await _repo.getOrdenesActivas(_sucursalId);
        existente = activas.where((o) => o.mesaId == widget.mesaId).firstOrNull;
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
    try {
      String ordenId;
      if (_ordenExistente != null) {
        ordenId = _ordenExistente!.ordenId;
      } else {
        final orden = await _repo.crearOrden(
          mesaId: widget.mesaId,
          tipoOrden: _tipoOrden,
          tipoOrigen: 'MESERO',
        );
        ordenId = orden.ordenId;
      }

      for (final item in _carrito) {
        await _repo.agregarDetalle(
          ordenId: ordenId,
          platoId: item.plato.platoId,
          cantidad: item.cantidad,
          tipoServicio: _tipoOrden == 'EN_MESA' ? 'EN_MESA' : 'PARA_LLEVAR',
          observaciones: item.notas,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Orden enviada a cocina!'), backgroundColor: AppColors.success),
        );
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
      bottomNavigationBar: _totalItems > 0 ? _buildBottomBar() : null,
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildTipoOrden(),
        if (_ordenExistente != null) _buildOrdenActivaBanner(),
        Expanded(child: _buildPlatosList()),
      ],
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

  Widget _buildOrdenActivaBanner() {
    final o = _ordenExistente!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.mesaOcupada.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mesaOcupada.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_outlined, color: AppColors.mesaOcupada, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Orden #${o.numeroOrden} activa (${o.detalles.length} items). Puedes agregar más.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.mesaOcupada),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatosList() {
    if (_platos.isEmpty) {
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
      itemCount: _platos.length,
      itemBuilder: (_, i) => _PlatoTile(
        plato: _platos[i],
        cantidad: _inCart(_platos[i]),
        onAdd: () => _addToCart(_platos[i]),
        onRemove: () => _removeFromCart(_platos[i]),
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
          onConfirm: () { Navigator.pop(ctx); _confirmarOrden(); },
        ),
      ),
    );
  }
}

// ── Subwidgets ───────────────────────────────────────────────────────────────

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
  final VoidCallback onConfirm;

  const _CarritoSheet({
    required this.carrito,
    required this.total,
    required this.scrollController,
    required this.onRemove,
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
                      ],
                    ),
                  ),
                  Text('\$${i.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
