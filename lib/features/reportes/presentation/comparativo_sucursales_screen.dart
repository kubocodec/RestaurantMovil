import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/reportes_repository.dart';

/// Comparativo para el dueño: cuánto vendió cada sucursal del restaurant
/// en el período elegido (hoy, últimos 7 días, este mes o rango libre).
class ComparativoSucursalesScreen extends StatefulWidget {
  final String restaurantId;
  const ComparativoSucursalesScreen({super.key, required this.restaurantId});

  @override
  State<ComparativoSucursalesScreen> createState() => _ComparativoSucursalesScreenState();
}

enum _Periodo { hoy, semana, mes, personalizado }

class _ComparativoSucursalesScreenState extends State<ComparativoSucursalesScreen> {
  final _repo = ReportesRepository();
  final _fmt = NumberFormat('#,##0.00', 'es');

  _Periodo _periodo = _Periodo.hoy;
  DateTime _desde = DateTime.now();
  DateTime _hasta = DateTime.now();
  ReporteVentasSucursalesModel? _reporte;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await _repo.getVentasPorSucursal(
        widget.restaurantId, desde: _desde, hasta: _hasta);
      if (!mounted) return;
      setState(() { _reporte = r; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _cambiarPeriodo(_Periodo p) async {
    final hoy = DateTime.now();
    switch (p) {
      case _Periodo.hoy:
        _desde = hoy; _hasta = hoy;
        break;
      case _Periodo.semana:
        _desde = hoy.subtract(const Duration(days: 6)); _hasta = hoy;
        break;
      case _Periodo.mes:
        _desde = DateTime(hoy.year, hoy.month, 1); _hasta = hoy;
        break;
      case _Periodo.personalizado:
        final rango = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: hoy,
          initialDateRange: DateTimeRange(start: _desde, end: _hasta),
          locale: const Locale('es'),
        );
        if (rango == null) return;
        _desde = rango.start; _hasta = rango.end;
        break;
    }
    setState(() => _periodo = p);
    _load();
  }

  String get _tituloPeriodo {
    final f = DateFormat('d MMM y', 'es');
    if (DateUtils.isSameDay(_desde, _hasta)) {
      return DateUtils.isSameDay(_desde, DateTime.now()) ? 'Hoy' : f.format(_desde);
    }
    return '${f.format(_desde)} — ${f.format(_hasta)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ventas por sucursal'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSelectorPeriodo(),
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

  Widget _buildSelectorPeriodo() {
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(_tituloPeriodo,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _chip('Hoy', _Periodo.hoy),
              _chip('Últimos 7 días', _Periodo.semana),
              _chip('Este mes', _Periodo.mes),
              _chip('Elegir fechas', _Periodo.personalizado),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, _Periodo p) {
    final selected = _periodo == p;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          )),
      selected: selected,
      selectedColor: AppColors.primary,
      onSelected: (_) => _cambiarPeriodo(p),
    );
  }

  Widget _buildBody() {
    final r = _reporte;
    if (r == null) return const SizedBox.shrink();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildTotalCard(r),
          const SizedBox(height: 16),
          if (r.sucursales.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No hay sucursales activas',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
              ),
            )
          else
            ...r.sucursales.asMap().entries.map((e) =>
                _buildSucursalCard(e.key + 1, e.value, r)),
        ],
      ),
    );
  }

  Widget _buildTotalCard(ReporteVentasSucursalesModel r) {
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
          Text(r.nombreRestaurant,
              style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Ventas de toda la empresa',
              style: TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 13)),
          Text('\$${_fmt.format(r.totalVentas)}',
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 32)),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(label: 'Sucursales', value: '${r.sucursales.length}'),
              const SizedBox(width: 24),
              _MiniStat(label: 'Facturas', value: '${r.totalFacturas}'),
              const SizedBox(width: 24),
              _MiniStat(label: 'Órdenes', value: '${r.totalOrdenes}'),
              const SizedBox(width: 24),
              _MiniStat(label: 'Ganancia est.', value: '\$${_fmt.format(r.totalGananciaEstimada)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSucursalCard(int puesto, VentaSucursalModel s, ReporteVentasSucursalesModel r) {
    // Barra proporcional a la sucursal que más vendió en el período
    final maxVentas = r.sucursales.isEmpty ? 0.0 : r.sucursales.first.totalVentas;
    final proporcion = maxVentas > 0 ? (s.totalVentas / maxVentas).clamp(0.0, 1.0) : 0.0;
    final esPrimera = puesto == 1 && s.totalVentas > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: esPrimera
            ? Border.all(color: AppColors.success.withValues(alpha: 0.4))
            : Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (esPrimera ? AppColors.success : AppColors.primary).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text('$puesto',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
                        color: esPrimera ? AppColors.success : AppColors.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.nombreSucursal,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Text('\$${_fmt.format(s.totalVentas)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: proporcion,
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(
                  esPrimera ? AppColors.success : AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${s.totalFacturas} facturas · ${s.totalOrdenes} órdenes · '
            'Ganancia est.: \$${_fmt.format(s.gananciaEstimada)}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
          ),
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
                color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
        Text(label, style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 10)),
      ],
    );
  }
}
