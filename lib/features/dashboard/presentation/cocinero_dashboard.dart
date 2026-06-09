import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/user_model.dart';
import '../../../shared/widgets/app_drawer.dart';

class CocineroDashboard extends StatelessWidget {
  const CocineroDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Panel Cocina'),
            backgroundColor: AppColors.cocineroColor,
          ),
          drawer: user != null ? AppDrawer(user: user) : null,
          body: _CocinaBody(user: user),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppColors.cocineroColor,
            onPressed: () => context.go('/cocina'),
            icon: const Icon(Icons.kitchen),
            label: const Text('Ver Órdenes', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        );
      },
    );
  }
}

class _CocinaBody extends StatelessWidget {
  final UserModel? user;
  const _CocinaBody({this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          _buildStatusCards(context),
          const SizedBox(height: 24),
          _buildGoToKitchen(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.cocineroColor, Color(0xFFBF360C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.cocineroColor.withOpacity(0.3),
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
                  'Hola, ${user?.nombre ?? 'Cocinero'}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'Poppins'),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Estado: En servicio',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Poppins'),
                ),
              ],
            ),
          ),
          const Icon(Icons.soup_kitchen_outlined, color: Colors.white, size: 40),
        ],
      ),
    );
  }

  Widget _buildStatusCards(BuildContext context) {
    final cards = [
      {'label': 'Pendientes', 'value': '-', 'color': AppColors.estadoPendiente, 'icon': Icons.pending_outlined},
      {'label': 'En preparación', 'value': '-', 'color': AppColors.estadoEnProceso, 'icon': Icons.restaurant_outlined},
      {'label': 'Listos', 'value': '-', 'color': AppColors.estadoListo, 'icon': Icons.check_circle_outline},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resumen del turno', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(
          children: cards.map((c) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: cards.indexOf(c) < 2 ? 8 : 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: const Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Icon(c['icon'] as IconData, color: c['color'] as Color, size: 24),
                  const SizedBox(height: 6),
                  Text(c['value'] as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: c['color'] as Color)),
                  Text(c['label'] as String, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: 'Poppins'), textAlign: TextAlign.center),
                ],
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildGoToKitchen(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/cocina'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cocineroColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cocineroColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.kitchen_outlined, color: AppColors.cocineroColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ver todas las órdenes', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.cocineroColor)),
                  Text('Gestiona el estado de cada plato', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.cocineroColor),
          ],
        ),
      ),
    );
  }
}
