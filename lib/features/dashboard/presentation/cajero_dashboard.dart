import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/user_model.dart';
import '../../../features/caja/data/caja_repository.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/stat_card.dart';

class CajeroDashboard extends StatelessWidget {
  const CajeroDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Panel Cajero'),
          ),
          drawer: user != null ? AppDrawer(user: user) : null,
          body: _CajeroBody(user: user),
        );
      },
    );
  }
}

class _CajeroBody extends StatefulWidget {
  final UserModel? user;
  const _CajeroBody({this.user});

  @override
  State<_CajeroBody> createState() => _CajeroBodyState();
}

class _CajeroBodyState extends State<_CajeroBody> {
  final _cajaRepo = CajaRepository();
  bool? _cajaAbierta; // null = cargando

  @override
  void initState() {
    super.initState();
    _checkCajaStatus();
  }

  Future<void> _checkCajaStatus() async {
    final sucursalId = widget.user?.sucursalId ?? '';
    if (sucursalId.isEmpty) {
      setState(() => _cajaAbierta = false);
      return;
    }
    try {
      final cajas = await _cajaRepo.getCajasBySucursal(sucursalId);
      if (cajas.isEmpty) {
        setState(() => _cajaAbierta = false);
        return;
      }
      final apertura = await _cajaRepo.getAperturaActiva(cajas.first.cajaId);
      setState(() => _cajaAbierta = apertura?.isAbierta == true);
    } catch (_) {
      setState(() => _cajaAbierta = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGreeting(),
            const SizedBox(height: 24),
            _buildCajaStatus(context),
            const SizedBox(height: 24),
            _buildStats(context),
            const SizedBox(height: 24),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGreeting() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.cajeroColor, Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.cajeroColor.withOpacity(0.3),
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
                  'Hola, ${widget.user?.nombre ?? 'Cajero'}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.user?.sucursalNombre ?? 'Sucursal principal',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Poppins'),
                ),
              ],
            ),
          ),
          const Icon(Icons.point_of_sale_outlined, color: Colors.white, size: 40),
        ],
      ),
    );
  }

  Widget _buildCajaStatus(BuildContext context) {
    if (_cajaAbierta == null) {
      return const SizedBox(
        height: 52,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_cajaAbierta == true) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.successLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.success),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Caja abierta y lista para operar',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, color: AppColors.success, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () {
                context.go('/cajero/caja');
              },
              child: const Text('Ver caja', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.warning),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'La caja no ha sido abierta hoy',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, color: AppColors.warning, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/cajero/caja'),
            child: const Text('Abrir caja', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resumen del día', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: const [
            StatCard(title: 'Ventas del día', value: '\$0.00', icon: Icons.attach_money, color: AppColors.success),
            StatCard(title: 'Facturas emitidas', value: '0', icon: Icons.receipt_outlined, color: AppColors.primary),
            StatCard(title: 'Órdenes cerradas', value: '0', icon: Icons.check_circle_outline, color: AppColors.cajeroColor),
            StatCard(title: 'Pendientes de pago', value: '0', icon: Icons.pending_outlined, color: AppColors.warning),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Acciones', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.point_of_sale_outlined,
          label: 'Gestión de Caja',
          subtitle: 'Aperturas, cierres y movimientos',
          color: AppColors.cajeroColor,
          onTap: () => context.go('/cajero/caja'),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.receipt_long_outlined,
          label: 'Facturación',
          subtitle: 'Emitir y gestionar facturas',
          color: AppColors.primary,
          onTap: () => context.go('/cajero/ordenes'),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
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
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                  Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
