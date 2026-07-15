import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/user_model.dart';
import '../../../features/mesas/data/mesas_repository.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';
import '../../../features/reportes/data/reportes_repository.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/stat_card.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Panel Administrador'),
            actions: [
              IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () {}),
            ],
          ),
          drawer: user != null ? AppDrawer(user: user) : null,
          body: _AdminBody(user: user),
        );
      },
    );
  }
}

class _AdminBody extends StatefulWidget {
  final UserModel? user;
  const _AdminBody({this.user});

  @override
  State<_AdminBody> createState() => _AdminBodyState();
}

class _AdminBodyState extends State<_AdminBody> {
  final _reportesRepo = ReportesRepository();
  final _mesasRepo = MesasRepository();
  final _ordenesRepo = OrdenesRepository();

  UserModel? get user => widget.user;

  double _ventasHoy = 0;
  int _facturasHoy = 0;
  int _mesasOcupadas = 0;
  int _ordenesActivas = 0;
  bool _cargandoStats = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadStats();
    // Las ventas/mesas/órdenes cambian desde otros dispositivos:
    // refrescar el resumen sin depender del pull-to-refresh.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadStats());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Navega y refresca las estadísticas al volver (push mantiene este
  /// dashboard vivo debajo; con go se perdía y no había refresco).
  Future<void> _irA(String ruta) async {
    await context.push(ruta);
    if (mounted) _loadStats();
  }

  Future<void> _loadStats() async {
    final sucursalId = user?.sucursalId ?? '';
    if (sucursalId.isEmpty) {
      setState(() => _cargandoStats = false);
      return;
    }
    try {
      final results = await Future.wait([
        _reportesRepo.getResumenDiario(sucursalId),
        _mesasRepo.getMesasBySucursal(sucursalId),
        _ordenesRepo.getOrdenesActivas(sucursalId),
      ]);
      if (!mounted) return;
      final resumen = results[0] as ResumenDiarioModel;
      final mesas = results[1] as List;
      final ordenes = results[2] as List;
      setState(() {
        _ventasHoy = resumen.totalVentas;
        _facturasHoy = resumen.totalFacturas;
        _mesasOcupadas = mesas.where((m) => m.estado == 'OCUPADA').length;
        _ordenesActivas = ordenes.length;
        _cargandoStats = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildStats(context),
            const SizedBox(height: 24),
            _buildModules(context),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withOpacity(0.4),
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
                  'Bienvenido,',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 13),
                ),
                Text(
                  user?.nombre ?? 'Administrador',
                  style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Vista completa del sistema',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Poppins'),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.admin_panel_settings_outlined, color: Colors.white, size: 44),
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
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Columnas según el ancho real y altura fija de tarjeta: en
          // tablet vertical las proporciones fijas aplastaban el contenido
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 150,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          children: [
            StatCard(
              title: 'Ventas totales',
              value: _cargandoStats ? '...' : '\$${_ventasHoy.toStringAsFixed(2)}',
              icon: Icons.attach_money, color: AppColors.success),
            StatCard(
              title: 'Mesas ocupadas',
              value: _cargandoStats ? '...' : '$_mesasOcupadas',
              icon: Icons.table_restaurant_outlined, color: AppColors.primary),
            StatCard(
              title: 'Órdenes en curso',
              value: _cargandoStats ? '...' : '$_ordenesActivas',
              icon: Icons.receipt_outlined, color: AppColors.warning),
            StatCard(
              title: 'Facturas emitidas',
              value: _cargandoStats ? '...' : '$_facturasHoy',
              icon: Icons.receipt_long_outlined, color: AppColors.cajeroColor),
          ],
        ),
      ],
    );
  }

  Widget _buildModules(BuildContext context) {
    final modules = [
      _Module(Icons.table_restaurant_outlined, 'Mesas', 'Ver y gestionar mesas', AppColors.primary, () => _irA('/mesero/mesas')),
      _Module(Icons.receipt_long_outlined, 'Órdenes', 'Órdenes activas', AppColors.earth2, () => _irA('/mesero/mesas')),
      _Module(Icons.point_of_sale_outlined, 'Caja', 'Aperturas y cierres', AppColors.cajeroColor, () => _irA('/cajero/caja')),
      _Module(Icons.history_rounded, 'Comprobantes', 'Recibos y facturas', AppColors.info, () => _irA('/cajero/comprobantes')),
      _Module(Icons.kitchen_outlined, 'Cocina', 'Estado de platos', AppColors.cocineroColor, () => _irA('/cocina')),
      _Module(Icons.bar_chart_outlined, 'Reportes', 'Estadísticas del día', AppColors.info, () => _irA('/admin/reportes')),
      _Module(Icons.settings_outlined, 'Configuración', 'Sucursal y menú', AppColors.textSecondary, () => _irA('/admin/configuracion')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Módulos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Columnas según el ancho real y altura fija de módulo (responsive)
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisExtent: 128,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: modules.length,
          itemBuilder: (_, i) {
            final m = modules[i];
            return GestureDetector(
              onTap: m.onTap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: const Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: m.color.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(m.icon, color: m.color, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(m.label, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(m.subtitle, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Module {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _Module(this.icon, this.label, this.subtitle, this.color, this.onTap);
}
