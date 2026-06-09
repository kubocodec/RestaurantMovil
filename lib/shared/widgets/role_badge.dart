import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/user_model.dart';

class RoleBadge extends StatelessWidget {
  final UserRole role;
  const RoleBadge({super.key, required this.role});

  Color get _color {
    switch (role) {
      case UserRole.superadmin: return const Color(0xFF7B1FA2);
      case UserRole.admin:      return AppColors.adminColor;
      case UserRole.cajero:     return AppColors.cajeroColor;
      case UserRole.mesero:     return AppColors.meseroColor;
      case UserRole.cocinero:   return AppColors.cocineroColor;
      case UserRole.unknown:    return AppColors.textHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }
}
