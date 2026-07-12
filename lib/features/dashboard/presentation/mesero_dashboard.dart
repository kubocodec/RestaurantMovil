import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/models/user_model.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';
import '../../../shared/widgets/app_drawer.dart';

class MeseroDashboard extends StatelessWidget {
  const MeseroDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Panel Mesero'),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {},
              ),
            ],
          ),
          drawer: user != null ? AppDrawer(user: user) : null,
          body: _MeseroBody(user: user),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.go('/mesero/mesas'),
            icon: const Icon(Icons.table_restaurant),
            label: const Text('Ver Mesas', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        );
      },
    );
  }
}

class _MeseroBody extends StatefulWidget {
  final UserModel? user;
  const _MeseroBody({this.user});

  @override
  State<_MeseroBody> createState() => _MeseroBodyState();
}

class _MeseroBodyState extends State<_MeseroBody> {
  final _ordenesRepo = OrdenesRepository();
  List<OrdenModel> _activas = [];
  bool _cargando = true;
  Timer? _timer;

  UserModel? get user => widget.user;

  @override
  void initState() {
    super.initState();
    _load();
    // Mantener las órdenes activas al día sin depender del pull-to-refresh
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final sucursalId = user?.sucursalId ?? '';
    if (sucursalId.isEmpty) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final activas = await _ordenesRepo.getOrdenesActivas(sucursalId);
      if (!mounted) return;
      setState(() { _activas = activas; _cargando = false; });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreeting(context),
              const SizedBox(height: 24),
              _buildQuickActions(context),
              const SizedBox(height: 24),
              _buildActiveOrdersSummary(context),
              const SizedBox(height: 80), // espacio para el FAB
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(BuildContext context) {
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' : hora < 19 ? 'Buenas tardes' : 'Buenas noches';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryVariant],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$saludo,',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Poppins'),
                ),
                Text(
                  user?.nombre ?? 'Mesero',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Listo para tomar órdenes',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Poppins'),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.room_service_outlined, color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Acciones rápidas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.table_restaurant_outlined,
                label: 'Mesas',
                subtitle: 'Ver estado',
                color: AppColors.primary,
                onTap: () => _irAMesas(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.takeout_dining_outlined,
                label: 'Para llevar',
                subtitle: 'Pedido sin mesa',
                color: AppColors.earth2,
                onTap: () => _irAParaLlevar(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _irAMesas(BuildContext context) async {
    await context.push('/mesero/mesas');
    if (mounted) _load(); // refleja las órdenes creadas/cobradas al volver
  }

  Future<void> _irAParaLlevar(BuildContext context) async {
    await context.push('/mesero/para-llevar');
    if (mounted) _load();
  }

  Widget _buildActiveOrdersSummary(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Órdenes activas (${_activas.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            TextButton(
              onPressed: () => context.go('/mesero/mesas'),
              child: const Text('Ver todo'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_cargando)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: AppColors.primary),
          ))
        else if (_activas.isEmpty)
          _buildEmptyOrders(context)
        else
          ..._activas.take(5).map((o) => _OrdenResumenTile(orden: o)),
      ],
    );
  }

  Widget _buildEmptyOrders(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              'No hay órdenes activas',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Ve a Mesas para comenzar',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdenResumenTile extends StatelessWidget {
  final OrdenModel orden;
  const _OrdenResumenTile({required this.orden});

  @override
  Widget build(BuildContext context) {
    final hora = orden.fechaCreacion.toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.mesaOcupada.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              orden.esParaLlevar ? Icons.takeout_dining_outlined : Icons.receipt_outlined,
              color: AppColors.mesaOcupada, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${orden.lugar} · Orden #${orden.numeroOrden}',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  'Desde ${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(orden.estado,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 10,
                fontWeight: FontWeight.w600, color: AppColors.warning)),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: const Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
            Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
