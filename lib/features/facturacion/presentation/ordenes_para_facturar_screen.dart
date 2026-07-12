import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';

class OrdenesParaFacturarScreen extends StatefulWidget {
  const OrdenesParaFacturarScreen({super.key});

  @override
  State<OrdenesParaFacturarScreen> createState() => _OrdenesParaFacturarScreenState();
}

class _OrdenesParaFacturarScreenState extends State<OrdenesParaFacturarScreen> {
  final _repo = OrdenesRepository();
  final _fmt  = NumberFormat('#,##0.00', 'es');
  List<OrdenModel> _ordenes = [];
  bool _loading = true;
  String? _error;

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
      final todas = await _repo.getOrdenesActivas(_sucursalId);
      // Solo mostrar órdenes que tengan ítems facturables
      final facturables = todas.where((o) => o.detallesNoFacturados.isNotEmpty).toList();
      if (mounted) setState(() { _ordenes = facturables; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Seleccionar orden'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_ordenes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 72, color: AppColors.textHint),
            SizedBox(height: 16),
            Text('No hay órdenes pendientes de facturar',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _ordenes.length,
        itemBuilder: (_, i) => _OrdenCard(
          orden: _ordenes[i],
          fmt: _fmt,
          onTap: () async {
            await context.push('/cajero/factura/${_ordenes[i].ordenId}');
            if (mounted) _load(); // la orden cobrada desaparece de la lista
          },
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
}

class _OrdenCard extends StatelessWidget {
  final OrdenModel orden;
  final NumberFormat fmt;
  final VoidCallback onTap;

  const _OrdenCard({required this.orden, required this.fmt, required this.onTap});

  Color get _estadoColor {
    switch (orden.estado) {
      case 'ABIERTA':    return AppColors.mesaLibre;
      case 'EN_PROCESO': return AppColors.estadoEnProceso;
      case 'LISTA':      return AppColors.estadoListo;
      default:           return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final facturables = orden.detallesNoFacturados;
    final total = facturables.fold(0.0, (s, d) => s + d.subtotal);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                orden.esParaLlevar ? Icons.takeout_dining_outlined : Icons.table_restaurant_outlined,
                color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(orden.lugar,
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _estadoColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(orden.estado,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: _estadoColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('Orden #${orden.numeroOrden}  •  ${facturables.length} ítem${facturables.length != 1 ? 's' : ''}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${fmt.format(total)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.primary)),
                const SizedBox(height: 2),
                const Icon(Icons.arrow_forward_ios, size: 13, color: AppColors.textHint),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
