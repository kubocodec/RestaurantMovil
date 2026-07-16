import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';

/// Banner de aviso de pago del servicio próximo a vencer.
/// Se muestra en los dashboards cuando el login devolvió un aviso
/// (2 días antes, 1 día antes y el día del vencimiento). Si el aviso
/// menciona "HOY" se pinta en rojo; si no, en ámbar.
class AvisoPagoBanner extends StatelessWidget {
  const AvisoPagoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthBloc>().state;
    final aviso = state is AuthAuthenticated ? state.user.avisoPago : null;
    if (aviso == null || aviso.isEmpty) return const SizedBox.shrink();

    final urgente = aviso.contains('HOY');
    final color = urgente ? AppColors.error : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(urgente ? Icons.error_outline_rounded : Icons.payments_outlined, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              aviso,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12.5, height: 1.35,
                fontWeight: FontWeight.w600, color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
