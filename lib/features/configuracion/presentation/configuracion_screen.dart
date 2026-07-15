import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../data/configuracion_repository.dart';
import 'tasa_iva_screen.dart';
import 'salones_mesas_screen.dart';
import 'menu_config_screen.dart';
import 'cajas_config_screen.dart';
import 'metodos_pago_config_screen.dart';
import 'usuarios_config_screen.dart';
import 'impresoras_config_screen.dart';

class ConfiguracionScreen extends StatefulWidget {
  final String? overrideSucursalId;
  final String? overrideRestaurantId;
  final String? overrideTenantId;
  final String? sucursalNombre;

  const ConfiguracionScreen({
    super.key,
    this.overrideSucursalId,
    this.overrideRestaurantId,
    this.overrideTenantId,
    this.sucursalNombre,
  });

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _repo = ConfiguracionRepository();
  SetupStatus? _status;
  bool _loading = true;
  String? _error;

  late String _sucursalId;
  late String _restaurantId;
  late String _tenantId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _init() {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    _sucursalId  = widget.overrideSucursalId  ?? user?.sucursalId  ?? '';
    _restaurantId = widget.overrideRestaurantId ?? user?.restaurantId ?? '';
    _tenantId    = widget.overrideTenantId    ?? user?.tenantId    ?? '';
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (_sucursalId.isEmpty) {
      setState(() { _loading = false; _error = 'No se encontró la sucursal'; });
      return;
    }
    try {
      setState(() { _loading = true; _error = null; });
      final status = await _repo.getSetupStatus(
        sucursalId:   _sucursalId,
        tenantId:     _tenantId,
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      setState(() { _status = status; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.sucursalNombre != null
            ? 'Config: ${widget.sucursalNombre}'
            : 'Configuración de sucursal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadStatus,
            tooltip: 'Actualizar checklist',
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadStatus, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final s = _status;
    if (s == null) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressCard(s),
            const SizedBox(height: 24),
            Text('Elementos a configurar',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _buildItem(
              icon: Icons.percent_rounded,
              label: 'Tasa de IVA',
              subtitle: 'Requerida para emitir facturas',
              done: s.tieneTasaIva,
              color: AppColors.cajeroColor,
              onTap: () => _goTo(TasaIvaScreen(tenantId: _tenantId)),
            ),
            _buildItem(
              icon: Icons.table_restaurant_outlined,
              label: 'Salones y Mesas',
              subtitle: 'Necesarios para crear órdenes',
              done: s.tieneSalones && s.tieneMesas,
              color: AppColors.primary,
              onTap: () => _goTo(SalonesMesasScreen(sucursalId: _sucursalId)),
            ),
            _buildItem(
              icon: Icons.restaurant_menu_outlined,
              label: 'Menú (Categorías y Platos)',
              subtitle: 'Platos con precio asignado a la sucursal',
              done: s.tienePlatos,
              color: AppColors.cocineroColor,
              onTap: () => _goTo(MenuConfigScreen(
                sucursalId:   _sucursalId,
                restaurantId: _restaurantId,
              )),
            ),
            _buildItem(
              icon: Icons.point_of_sale_outlined,
              label: 'Cajas registradoras',
              subtitle: 'Al menos una caja activa',
              done: s.tieneCaja,
              color: AppColors.earth2,
              onTap: () => _goTo(CajasConfigScreen(sucursalId: _sucursalId)),
            ),
            _buildItem(
              icon: Icons.payments_outlined,
              label: 'Métodos de pago',
              subtitle: 'Efectivo, tarjetas, transferencias...',
              done: true,
              color: AppColors.success,
              onTap: () => _goTo(MetodosPagoConfigScreen(sucursalId: _sucursalId)),
            ),
            _buildItem(
              icon: Icons.people_outline_rounded,
              label: 'Usuarios del personal',
              subtitle: 'Cajero, mesero, cocinero',
              done: s.tieneUsuarios,
              color: AppColors.info,
              onTap: () => _goTo(UsuariosConfigScreen(sucursalId: _sucursalId)),
            ),
            _buildItem(
              icon: Icons.print_outlined,
              label: 'Impresoras de comandas',
              subtitle: 'Cocina, barra: comandas por categoría',
              done: true,
              color: AppColors.earth2,
              onTap: () => _goTo(ImpresorasConfigScreen(
                sucursalId:   _sucursalId,
                restaurantId: _restaurantId,
              )),
            ),
            const SizedBox(height: 24),
            if (s.isComplete)
              _buildCompleteBanner()
            else
              _buildPendingBanner(s),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(SetupStatus s) {
    final pct = s.completedCount / 5;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: s.isComplete
              ? [const Color(0xFF2E7D32), const Color(0xFF388E3C)]
              : [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                s.isComplete ? Icons.check_circle_rounded : Icons.settings_outlined,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.isComplete ? '¡Sucursal lista para operar!' : 'Configuración de sucursal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '${s.completedCount}/5',
                style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.isComplete
                ? 'Todos los elementos están configurados'
                : '${5 - s.completedCount} elemento(s) pendiente(s)',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontFamily: 'Poppins', fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool done,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                      Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: done ? AppColors.success.withOpacity(0.12) : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        done ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 14,
                        color: done ? AppColors.success : AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        done ? 'Listo' : 'Pendiente',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: done ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompleteBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.rocket_launch_rounded, color: AppColors.success, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sucursal completamente configurada',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 13)),
                Text('El personal puede comenzar a usar la app sin problemas.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingBanner(SetupStatus s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configuración incompleta',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.warning, fontSize: 13)),
                Text(
                  'Completa los ${5 - s.completedCount} elementos pendientes para evitar errores en la app.',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _goTo(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadStatus();
  }
}
