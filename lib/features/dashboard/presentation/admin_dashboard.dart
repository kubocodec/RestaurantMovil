import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/settings/ajustes_texto.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/models/user_model.dart';
import '../../../features/adelantos/data/adelantos_repository.dart';
import '../../../features/adelantos/presentation/adelantos_screen.dart';
import '../../../features/inventario/data/inventario_repository.dart';
import '../../../features/inventario/presentation/inventario_screen.dart';
import '../../../features/mesas/data/mesas_repository.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';
import '../../../features/reportes/data/reportes_repository.dart';
import '../../../core/escritorio/escritorio.dart';
import '../../../shared/widgets/app_drawer.dart';
import '../../../shared/widgets/aviso_pago_banner.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../reportes/data/resumen_periodo_model.dart';
import 'panel_admin_escritorio.dart';

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
            title: Text(EscritorioScope.enUso(context) ? 'Panel' : 'Panel Administrador'),
            actions: [
              IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () {}),
            ],
          ),
          // Con el menú lateral de la web de escritorio, sin hamburguesa.
          drawer: user != null && !EscritorioScope.enUso(context) ? AppDrawer(user: user) : null,
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

  final _inventarioRepo = InventarioRepository();
  /// Aviso de stock. Llega vacío si el restaurante no lleva inventario, y
  /// entonces no se muestra nada.
  AlertasInventarioModel _alertas = const AlertasInventarioModel();
  final _adelantosRepo = AdelantosRepository();
  /// Solo los restaurantes con adelantos de reservas ven ese módulo.
  bool _adelantosHabilitados = false;

  // ── Solo en la web de escritorio (PanelAdminEscritorio) ────────────────
  // En el celular nada de esto se pide: el panel queda igual que siempre.
  bool _escritorio = false;
  List<OrdenModel> _ordenes = const [];
  int _mesasTotal = 0;
  List<VentaDia> _semanaPrevia = const [];
  List<PlatoVentaModel>? _masVendidos;
  DateTime? _ultimoTop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final escritorio = EscritorioScope.enUso(context);
    if (escritorio && !_escritorio) {
      _escritorio = true;
      _cargarSemana();
      _cargarMasVendidos();
    }
    _escritorio = escritorio;
  }

  /// Los 6 días anteriores, una sola vez: lo de días pasados no cambia. Hoy
  /// sale de las estadísticas de siempre, que se refrescan cada 30 s.
  Future<void> _cargarSemana() async {
    final sucursalId = user?.sucursalId ?? '';
    if (sucursalId.isEmpty) return;
    final hoy = DateTime.now();
    final dias = [for (var i = 6; i >= 1; i--) DateTime(hoy.year, hoy.month, hoy.day - i)];
    try {
      final r = await Future.wait(dias.map((d) => _reportesRepo.getResumenDiario(sucursalId, fecha: d)));
      if (!mounted) return;
      setState(() => _semanaPrevia = [
            for (var i = 0; i < dias.length; i++) (dia: dias[i], ventas: r[i].totalVentas - r[i].totalPropinas),
          ]);
    } catch (_) {
      // Sin la semana el panel sigue sirviendo: el gráfico muestra solo hoy.
    }
  }

  /// Lo más vendido de hoy. Es una consulta agregada: se renueva cada dos
  /// minutos y no en cada refresco de 30 s.
  Future<void> _cargarMasVendidos() async {
    final u = user;
    if (u == null || u.sucursalId.isEmpty) return;
    final ahora = DateTime.now();
    if (_ultimoTop != null && ahora.difference(_ultimoTop!) < const Duration(minutes: 2)) return;
    _ultimoTop = ahora;
    try {
      final r = await _reportesRepo.getResumenPeriodo(
          sucursalId: u.sucursalId, restaurantId: u.restaurantId, desde: ahora, hasta: ahora);
      if (!mounted) return;
      final top = r.platos.where((p) => p.unidades > 0).toList()
        ..sort((a, b) => b.unidades != a.unidades ? b.unidades.compareTo(a.unidades) : b.ventas.compareTo(a.ventas));
      setState(() => _masVendidos = top.take(5).toList());
    } catch (_) {
      if (mounted && _masVendidos == null) setState(() => _masVendidos = const []);
    }
  }

  Future<void> _abrirOrden(OrdenModel o) async {
    if (o.mesaId.isEmpty) {
      await context.push('/mesero/para-llevar?ordenId=${o.ordenId}');
    } else {
      await context.push('/mesero/orden/${o.mesaId}?nombre=${Uri.encodeComponent(o.numeroMesa)}&libre=false');
    }
    if (mounted) _loadStats();
  }

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
        _inventarioRepo.getAlertas(sucursalId),
        _adelantosRepo.listar(sucursalId),
      ]);
      if (!mounted) return;
      final resumen = results[0] as ResumenDiarioModel;
      final mesas = results[1] as List;
      final ordenes = results[2] as List<OrdenModel>;
      final alertas = results[3] as AlertasInventarioModel;
      final adelantos = results[4] as ListaAdelantos;
      setState(() {
        _alertas = alertas;
        _adelantosHabilitados = adelantos.habilitado;
        _ventasHoy = resumen.totalVentas;
        _facturasHoy = resumen.totalFacturas;
        _mesasOcupadas = mesas.where((m) => m.estado == 'OCUPADA').length;
        _ordenesActivas = ordenes.length;
        _ordenes = ordenes;
        _mesasTotal = mesas.length;
        _cargandoStats = false;
      });
      if (_escritorio) _cargarMasVendidos();
    } catch (_) {
      if (mounted) setState(() => _cargandoStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (EscritorioScope.enUso(context)) {
      return PanelAdminEscritorio(
        cargando: _cargandoStats,
        ventasHoy: _ventasHoy,
        facturasHoy: _facturasHoy,
        mesasOcupadas: _mesasOcupadas,
        mesasTotal: _mesasTotal,
        ordenes: _ordenes,
        semanaPrevia: _semanaPrevia,
        masVendidos: _masVendidos,
        avisoPago: const AvisoPagoBanner(),
        avisoInventario: _buildAvisoInventario(context),
        onAbrirOrden: _abrirOrden,
        onVerMesas: () => _irA('/mesero/mesas'),
        onVerReportes: () => _irA('/admin/reportes'),
      );
    }
    return SafeArea(
      child: RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AvisoPagoBanner(),
            _buildAvisoInventario(context),
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

  Future<void> _abrirAdelantos() async {
    final sucursalId = user?.sucursalId ?? '';
    if (sucursalId.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AdelantosScreen(sucursalId: sucursalId),
    ));
    if (mounted) _loadStats();
  }

  Future<void> _abrirInventario() async {
    final sucursalId = user?.sucursalId ?? '';
    if (sucursalId.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InventarioScreen(sucursalId: sucursalId, sucursalNombre: user?.sucursalNombre),
    ));
    if (mounted) _loadStats();
  }

  /// Aviso de stock para el administrador. Aparece solo (el dashboard ya se
  /// refresca cada 30 s) y lleva directo a Inventario para reponer.
  Widget _buildAvisoInventario(BuildContext context) {
    if (!_alertas.hayAlgoQueAvisar) return const SizedBox.shrink();
    final agotados = _alertas.totalAgotados;
    final bajos = _alertas.totalBajoMinimo;
    final insumos = _alertas.totalInsumosBajoMinimo;
    final soloInsumos = agotados == 0 && bajos == 0;
    final color = agotados > 0 || _alertas.insumosBajoMinimo.any((i) => i.negativo)
        ? AppColors.error
        : AppColors.warning;
    final nombres = soloInsumos
        ? _alertas.insumosBajoMinimo.take(3).map((i) => i.nombre).join(', ')
        : (agotados > 0 ? _alertas.agotados : _alertas.bajoMinimo)
            .take(3).map((i) => i.nombrePlato).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: _abrirInventario,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(agotados > 0 ? Icons.error_outline : Icons.warning_amber_rounded,
                  color: color, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agotados > 0
                          ? 'Sin stock: $agotados producto${agotados == 1 ? '' : 's'}'
                          : bajos > 0
                              ? 'Por agotarse: $bajos producto${bajos == 1 ? '' : 's'}'
                              : 'Insumos por reponer: $insumos',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 14, color: color),
                    ),
                    Text(
                      [
                        agotados > 0 && bajos > 0
                            ? '$nombres  ·  y $bajos por agotarse'
                            : nombres,
                        if (!soloInsumos && insumos > 0)
                          '$insumos insumo${insumos == 1 ? '' : 's'} por reponer',
                      ].join('  ·  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModules(BuildContext context) {
    final modules = [
      _Module(Icons.table_restaurant_outlined, 'Mesas', 'Ver y gestionar mesas', AppColors.primary, () => _irA('/mesero/mesas')),
      _Module(Icons.receipt_long_outlined, 'Órdenes', 'Órdenes activas', AppColors.earth2, () => _irA('/mesero/mesas')),
      _Module(Icons.point_of_sale_outlined, 'Caja', 'Aperturas y cierres', AppColors.cajeroColor, () => _irA('/cajero/caja')),
      _Module(Icons.history_rounded, 'Comprobantes', 'Notas de venta y facturas', AppColors.info, () => _irA('/cajero/comprobantes')),
      _Module(Icons.kitchen_outlined, 'Cocina', 'Estado de platos', AppColors.cocineroColor, () => _irA('/cocina')),
      _Module(Icons.bar_chart_outlined, 'Reportes', 'Estadísticas del día', AppColors.info, () => _irA('/admin/reportes')),
      _Module(Icons.settings_outlined, 'Configuración', 'Sucursal y menú', AppColors.textSecondary, () => _irA('/admin/configuracion')),
      // Solo para los restaurantes que llevan inventario.
      if (_alertas.habilitado)
        _Module(Icons.inventory_2_outlined, 'Inventario', 'Stock y reposición',
            AppColors.earth2, _abrirInventario),
      if (_adelantosHabilitados)
        _Module(Icons.event_available_outlined, 'Adelantos', 'Reservas pagadas por adelantado',
            AppColors.cajeroColor, _abrirAdelantos),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Módulos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Columnas según el ancho real y altura fija de módulo (responsive).
          // La altura escala con el tamaño de texto elegido (accesibilidad).
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisExtent: 128 * escalaTextoDe(context),
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
