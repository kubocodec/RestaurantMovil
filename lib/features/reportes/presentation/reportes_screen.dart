import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/caja_model.dart';
import '../../../core/models/config_models.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../features/configuracion/data/configuracion_repository.dart';
import '../../../shared/widgets/cierre_detalle_sheet.dart';
import '../data/reportes_repository.dart';
import 'comparativo_sucursales_screen.dart';
import 'ordenes_anuladas_screen.dart';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  final _repo = ReportesRepository();
  final _fmt = NumberFormat('#,##0.00', 'es');
  ResumenDiarioModel? _resumen;
  ReporteCajasDiaModel? _cajas;
  DateTime _fecha = DateTime.now();
  bool _loading = true;
  String? _error;
  // El admin puede consultar cualquier sucursal de su restaurant;
  // por defecto se muestra la suya.
  List<SucursalModel> _sucursales = [];
  String? _sucursalSel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadSucursales();
    });
  }

  String get _sucursalId {
    if (_sucursalSel != null) return _sucursalSel!;
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  Future<void> _loadSucursales() async {
    try {
      final sucursales =
          await ConfiguracionRepository().getSucursalesByRestaurant(_restaurantId);
      if (mounted) {
        setState(() => _sucursales = sucursales.where((s) => s.activo).toList());
      }
    } catch (_) {
      // Sin la lista solo se pierde el selector; los reportes de la
      // sucursal propia siguen funcionando.
    }
  }

  String get _restaurantId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.restaurantId : '';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final futuros = await Future.wait([
        _repo.getResumenDiario(_sucursalId, fecha: _fecha),
        _repo.getCierresCajaDia(_sucursalId, fecha: _fecha),
      ]);
      if (!mounted) return;
      setState(() {
        _resumen = futuros[0] as ResumenDiarioModel;
        _cajas   = futuros[1] as ReporteCajasDiaModel;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (elegida != null) {
      setState(() => _fecha = elegida);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final esHoy = DateUtils.isSameDay(_fecha, DateTime.now());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cancel_outlined),
            tooltip: 'Órdenes anuladas',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OrdenesAnuladasScreen(sucursalId: _sucursalId),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Ventas por sucursal',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ComparativoSucursalesScreen(restaurantId: _restaurantId),
            )),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.cardBackground,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        esHoy ? 'Hoy' : DateFormat('EEEE d MMMM y', 'es').format(_fecha),
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _elegirFecha,
                        icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                        label: const Text('Cambiar fecha'),
                      ),
                    ],
                  ),
                  if (_sucursales.length > 1)
                    Row(
                      children: [
                        const Icon(Icons.storefront_outlined, size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _sucursales.any((s) => s.sucursalId == _sucursalId)
                                ? _sucursalId
                                : null,
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            hint: const Text('Elige la sucursal',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                            items: _sucursales.map((s) => DropdownMenuItem(
                              value: s.sucursalId,
                              child: Text(s.nombre,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                            )).toList(),
                            onChanged: (id) {
                              if (id == null || id == _sucursalId) return;
                              setState(() => _sucursalSel = id);
                              _load();
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? _buildError()
                      : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final r = _resumen;
    if (r == null) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildVentasCard(r),
          const SizedBox(height: 16),
          _buildDetalleCard(r),
          const SizedBox(height: 16),
          _buildGananciaCard(r),
          if (_cajas != null) ...[
            const SizedBox(height: 16),
            _buildCajasResumenCard(_cajas!),
            const SizedBox(height: 16),
            _buildCierresCard(_cajas!),
          ],
        ],
      ),
    );
  }

  Widget _buildVentasCard(ResumenDiarioModel r) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.nombreSucursal,
              style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Ventas totales',
              style: TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 13)),
          Text('\$${_fmt.format(r.totalVentas)}',
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 32)),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(label: 'Órdenes', value: '${r.totalOrdenes}'),
              const SizedBox(width: 24),
              _MiniStat(label: 'Facturas', value: '${r.totalFacturas}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleCard(ResumenDiarioModel r) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Desglose',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          _FilaReporte(label: 'Ventas netas (sin IVA ni propinas)', valor: r.totalNeto, fmt: _fmt),
          _FilaReporte(label: 'IVA cobrado', valor: r.totalIva, fmt: _fmt),
          _FilaReporte(label: 'Propinas', valor: r.totalPropinas, fmt: _fmt),
          _FilaReporte(label: 'Descuentos aplicados', valor: r.totalDescuentos, fmt: _fmt, negativo: true),
        ],
      ),
    );
  }

  Widget _buildGananciaCard(ResumenDiarioModel r) {
    final positiva = r.gananciaEstimada >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (positiva ? AppColors.success : AppColors.error).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rentabilidad estimada',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          _FilaReporte(label: 'Costo de platos vendidos', valor: r.totalCosto, fmt: _fmt, negativo: true),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ganancia estimada',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
              Text('\$${_fmt.format(r.gananciaEstimada)}',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: positiva ? AppColors.success : AppColors.error)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Basada en el costo registrado de cada plato',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  /// Resumen de caja del día: cuánto entró por cada método de pago,
  /// cuánto salió y el faltante/sobrante total de los turnos cerrados.
  Widget _buildCajasResumenCard(ReporteCajasDiaModel c) {
    final cuadrada = c.totalDiferencia.abs() < 0.01;
    final colorDif = cuadrada
        ? AppColors.success
        : c.totalDiferencia > 0 ? AppColors.warning : AppColors.error;
    // Ventas del día por método de pago, sumando todos los turnos
    final porMetodo = <String, double>{};
    for (final cierre in c.cierres) {
      for (final m in cierre.ventasPorMetodo) {
        porMetodo[m.metodo] = (porMetodo[m.metodo] ?? 0) + m.total;
      }
    }
    final metodosOrdenados = porMetodo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Caja del día',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          if (metodosOrdenados.isEmpty)
            _FilaReporte(label: 'Ventas en efectivo', valor: c.totalVentasEfectivo, fmt: _fmt)
          else
            ...metodosOrdenados.map((e) =>
                _FilaReporte(label: 'Ventas en ${e.key}', valor: e.value, fmt: _fmt)),
          _FilaReporte(label: 'Otros ingresos a caja', valor: c.totalIngresos, fmt: _fmt),
          _FilaReporte(label: 'Egresos (gastos) de caja', valor: c.totalEgresos, fmt: _fmt, negativo: true),
          const Divider(),
          _FilaReporte(label: 'Efectivo esperado en cajas', valor: c.totalEsperado, fmt: _fmt),
          _FilaReporte(label: 'Efectivo contado (cierres)', valor: c.totalContado, fmt: _fmt),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                cuadrada
                    ? 'Cajas cuadradas'
                    : c.totalDiferencia > 0 ? 'Sobrante del día' : 'Faltante del día',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: colorDif),
              ),
              Text('\$${_fmt.format(c.totalDiferencia.abs())}',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18, color: colorDif)),
            ],
          ),
        ],
      ),
    );
  }

  /// Turnos de caja del día: cada apertura/cierre con acceso al detalle
  /// completo (ingresos, egresos, ventas, métodos de pago).
  Widget _buildCierresCard(ReporteCajasDiaModel c) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text('Cierres de caja (${c.cierres.length})',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          if (c.cierres.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text('No hubo aperturas de caja este día',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
            )
          else ...[
            const Divider(height: 1),
            ...c.cierres.map(_buildCierreTile),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildCierreTile(CierreDetalladoModel cierre) {
    final dif = cierre.diferencia;
    final String estadoDif;
    final Color colorDif;
    if (!cierre.isCerrada) {
      estadoDif = 'Turno abierto';
      colorDif = AppColors.success;
    } else if (dif == null || dif.abs() < 0.01) {
      estadoDif = 'Cuadrada';
      colorDif = AppColors.success;
    } else if (dif > 0) {
      estadoDif = 'Sobrante \$${_fmt.format(dif)}';
      colorDif = AppColors.warning;
    } else {
      estadoDif = 'Faltante \$${_fmt.format(dif.abs())}';
      colorDif = AppColors.error;
    }
    final horaFmt = DateFormat('HH:mm', 'es');
    final horario = cierre.fechaCierre != null
        ? '${horaFmt.format(cierre.fechaApertura.toLocal())} - ${horaFmt.format(cierre.fechaCierre!.toLocal())}'
        : 'Desde ${horaFmt.format(cierre.fechaApertura.toLocal())}';
    return ListTile(
      onTap: () => mostrarCierreDetalle(context, cierre, sucursalId: _sucursalId),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorDif.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.point_of_sale_outlined, color: colorDif, size: 20),
      ),
      title: Text('${cierre.nombreCaja} · $horario',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text(
        'Ventas \$${_fmt.format(cierre.totalVentas)} · '
        'Egresos \$${_fmt.format(cierre.totalEgresos)} · '
        '${cierre.usuarioCierre ?? cierre.usuarioApertura}',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(estadoDif,
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12, color: colorDif)),
          const Text('Ver detalle',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Poppins')),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 11)),
      ],
    );
  }
}

class _FilaReporte extends StatelessWidget {
  final String label;
  final double valor;
  final NumberFormat fmt;
  final bool negativo;
  const _FilaReporte({required this.label, required this.valor, required this.fmt, this.negativo = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
          ),
          Text('${negativo && valor > 0 ? '-' : ''}\$${fmt.format(valor)}',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
