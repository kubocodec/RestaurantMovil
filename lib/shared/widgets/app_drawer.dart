import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/user_model.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_event.dart';
import 'role_badge.dart';

class AppDrawer extends StatelessWidget {
  final UserModel user;
  const AppDrawer({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildMenu(context)),
          _buildLogout(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              user.nombre.isNotEmpty ? user.nombre[0].toUpperCase() : 'U',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.nombre,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            user.sucursalNombre.isNotEmpty ? user.sucursalNombre : 'Sucursal principal',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 8),
          RoleBadge(role: user.rol),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final items = _itemsForRole(user.rol);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: items.map((item) => _DrawerItem(
        icon: item.icon,
        label: item.label,
        route: item.route,
        onTap: () {
          Navigator.pop(context);
          context.go(item.route);
        },
      )).toList(),
    );
  }

  Widget _buildLogout(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout_rounded, color: AppColors.error),
        title: const Text(
          'Cerrar sesión',
          style: TextStyle(
            color: AppColors.error,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        onTap: () => _showLogoutDialog(context),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    // Capturar el bloc ANTES de cerrar diálogos/drawer: sus context dejan
    // de ser válidos al desmontarse y el logout nunca se disparaba.
    final authBloc = context.read<AuthBloc>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que deseas salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              authBloc.add(AuthLogoutRequested());
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  List<_MenuItem> _itemsForRole(UserRole role) {
    switch (role) {
      case UserRole.superadmin:
        return [
          _MenuItem(Icons.admin_panel_settings_rounded, 'Panel Super Admin', '/superadmin'),
        ];
      case UserRole.admin:
        return [
          _MenuItem(Icons.dashboard_outlined, 'Panel principal', '/admin'),
          _MenuItem(Icons.settings_outlined, 'Configuración', '/admin/configuracion'),
          _MenuItem(Icons.bar_chart_outlined, 'Reportes', '/admin/reportes'),
          _MenuItem(Icons.table_restaurant_outlined, 'Mesas', '/mesero/mesas'),
          _MenuItem(Icons.receipt_long_outlined, 'Órdenes activas', '/mesero'),
          _MenuItem(Icons.receipt_outlined, 'Facturación', '/cajero/ordenes'),
          _MenuItem(Icons.point_of_sale_outlined, 'Caja', '/cajero/caja'),
        ];
      case UserRole.cajero:
        return [
          _MenuItem(Icons.dashboard_outlined, 'Panel principal', '/cajero'),
          _MenuItem(Icons.point_of_sale_outlined, 'Caja', '/cajero/caja'),
          _MenuItem(Icons.receipt_long_outlined, 'Facturación', '/cajero/ordenes'),
          _MenuItem(Icons.table_restaurant_outlined, 'Tomar pedidos', '/mesero/mesas'),
        ];
      case UserRole.mesero:
        return [
          _MenuItem(Icons.dashboard_outlined, 'Panel principal', '/mesero'),
          _MenuItem(Icons.table_restaurant_outlined, 'Mesas', '/mesero/mesas'),
        ];
      case UserRole.cocinero:
        return [
          _MenuItem(Icons.dashboard_outlined, 'Panel principal', '/cocinero'),
          _MenuItem(Icons.kitchen_outlined, 'Órdenes cocina', '/cocina'),
        ];
      case UserRole.unknown:
        return [];
    }
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String route;
  const _MenuItem(this.icon, this.label, this.route);
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isActive = currentRoute == route;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary.withOpacity(0.1) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: isActive ? AppColors.primary : AppColors.textSecondary, size: 22),
        title: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? AppColors.primary : AppColors.textPrimary,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
