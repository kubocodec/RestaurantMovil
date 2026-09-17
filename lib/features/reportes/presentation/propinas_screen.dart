import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/reportes_repository.dart';

/// Subsección de Reportes para el administrador: propinas cobradas en el
/// período, que es lo que hay que repartir entre los meseros.
///
/// Solo cuenta comprobantes pagados: si un cobro se anuló, su propina no
/// entra. El backend manda además el desglose por mesero; hoy no se muestra
/// para no cargar la pantalla, pero el dato ya llega: activarlo será solo un
/// cambio de UI, sin tocar el servidor ni la base.
class PropinasScreen extends StatefulWidget {
  final String sucursalId;
  const PropinasScreen({super.key, required this.sucursalId});

  @override
  State<PropinasScreen> createState() => _PropinasScreenState();
}

enum _Periodo { hoy, semana, mes, personalizado }

class _PropinasScreenState extends State<PropinasScreen> {
  final _repo = ReportesRepository();
  final _fmt = NumberFormat('#,##0.00', 'es');

  _Periodo _periodo = _Periodo.hoy;
  DateTime _desde = DateTime.now();
  DateTime _hasta = DateTime.now();
  ReportePropinasModel? _reporte;
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
      final r = await _repo.getPropinas(
        widget.sucursalId, desde: _desde, hasta: _hasta);
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
        title: const Text('Propinas'),
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
      selectedColor: AppColors.success,
      onSelected: (_) => _cambiarPeriodo(p),
    );
  }

  Widget _buildBody() {
    final r = _reporte;
    if (r == null) return const SizedBox.shrink();
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildTotalCard(r),
          const SizedBox(height: 16),
          if (r.totalPropinas == 0)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No se registraron propinas en este período',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Es el total cobrado en propinas dentro del período, sumando '
                'efectivo y tarjeta. No incluye comprobantes anulados.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  color: AppColors.textSecondary, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(ReportePropinasModel r) {
    final n = r.comprobantesConPropina;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success.withValues(alpha: 0.85), AppColors.success],
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
          const Text('Total en propinas',
              style: TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 13)),
          Text('\$${_fmt.format(r.totalPropinas)}',
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 32)),
          const SizedBox(height: 4),
          Text('$n cobro${n == 1 ? '' : 's'} con propina en el período',
              style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
