import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/settings/ajustes_texto.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/user_model.dart';
import '../../../features/caja/data/caja_repository.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';
import '../../../features/reportes/data/reportes_repository.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/aviso_pago_banner.dart';
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
  final _reportesRepo = ReportesRepository();
  final _ordenesRepo = OrdenesRepository();
  bool? _cajaAbierta; // null = cargando
  double _ventasHoy = 0;
  int _facturasHoy = 0;
  int _ordenesHoy = 0;
  int _ordenesActivas = 0;
  bool _cargandoStats = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkCajaStatus();
    // Ventas y órdenes cambian desde otros dispositivos (meseros):
    // refrescar el resumen sin depender del pull-to-refresh.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _checkCajaStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkCajaStatus() async {
    final sucursalId = widget.user?.sucursalId ?? '';
    if (sucursalId.isEmpty) {
      setState(() { _cajaAbierta = false; _cargandoStats = false; });
      return;
    }
    try {
      final cajas = await _cajaRepo.getCajasBySucursal(sucursalId);
      if (cajas.isEmpty) {
        setState(() => _cajaAbierta = false);
      } else {
        final apertura = await _cajaRepo.getAperturaActiva(cajas.first.cajaId);
        if (mounted) setState(() => _cajaAbierta = apertura?.isAbierta == true);
      }
    } catch (_) {
      if (mounted) setState(() => _cajaAbierta = false);
    }
    // Estadísticas del día (independientes del estado de la caja)
    try {
      final results = await Future.wait([
        _reportesRepo.getResumenDiario(sucursalId),
        _ordenesRepo.getOrdenesActivas(sucursalId),
      ]);
      if (!mounted) return;
      final resumen = results[0] as ResumenDiarioModel;
      final activas = results[1] as List;
      setState(() {
        _ventasHoy = resumen.totalVentas;
        _facturasHoy = resumen.totalFacturas;
        _ordenesHoy = resumen.totalOrdenes;
        _ordenesActivas = activas.length;
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
        onRefresh: _checkCajaStatus,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AvisoPagoBanner(),
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

  Future<void> _irACaja(BuildContext context) async {
    await context.push('/cajero/caja');
    if (mounted) _checkCajaStatus(); // refleja apertura/cierre al volver
  }

  /// Navega con push y refresca el resumen al volver (con go se perdía
  /// este dashboard y los datos quedaban desactualizados).
  Future<void> _irARuta(String ruta) async {
    await context.push(ruta);
    if (mounted) _checkCajaStatus();
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
              onPressed: () => _irACaja(context),
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
            onPressed: () => _irACaja(context),
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
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Columnas según el ancho real y altura fija de tarjeta: en
          // tablet vertical las proporciones fijas aplastaban el contenido.
          // La altura escala con el tamaño de texto elegido (accesibilidad).
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 150 * escalaTextoDe(context),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          children: [
            StatCard(
              title: 'Ventas del día',
              value: _cargandoStats ? '...' : '\$${_ventasHoy.toStringAsFixed(2)}',
              icon: Icons.attach_money, color: AppColors.success),
            StatCard(
              title: 'Facturas emitidas',
              value: _cargandoStats ? '...' : '$_facturasHoy',
              icon: Icons.receipt_outlined, color: AppColors.primary),
            StatCard(
              title: 'Órdenes del día',
              value: _cargandoStats ? '...' : '$_ordenesHoy',
              icon: Icons.check_circle_outline, color: AppColors.cajeroColor),
            StatCard(
              title: 'Órdenes por cobrar',
              value: _cargandoStats ? '...' : '$_ordenesActivas',
              icon: Icons.pending_outlined, color: AppColors.warning),
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
          onTap: () => _irACaja(context),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.receipt_long_outlined,
          label: 'Facturación',
          subtitle: 'Emitir y gestionar facturas',
          color: AppColors.primary,
          onTap: () => _irARuta('/cajero/ordenes'),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.history_rounded,
          label: 'Recibos y facturas',
          subtitle: 'Consultar y reimprimir comprobantes',
          color: AppColors.info,
          onTap: () => _irARuta('/cajero/comprobantes'),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.table_restaurant_outlined,
          label: 'Tomar pedidos',
          subtitle: 'Crear órdenes en las mesas',
          color: AppColors.earth2,
          onTap: () => _irARuta('/mesero/mesas'),
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
