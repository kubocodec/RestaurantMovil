import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/network/api_client.dart';
import '../data/reportes_repository.dart';

/// Subsección de Reportes para el administrador: órdenes anuladas del
/// período con su motivo (obligatorio al anular), quién la anuló y el
/// detalle completo de lo que tenía pedido.
class OrdenesAnuladasScreen extends StatefulWidget {
  final String sucursalId;
  const OrdenesAnuladasScreen({super.key, required this.sucursalId});

  @override
  State<OrdenesAnuladasScreen> createState() => _OrdenesAnuladasScreenState();
}

enum _Periodo { hoy, semana, mes, personalizado }

class _OrdenesAnuladasScreenState extends State<OrdenesAnuladasScreen> {
  final _repo = ReportesRepository();
  final _fmt = NumberFormat('#,##0.00', 'es');

  _Periodo _periodo = _Periodo.hoy;
  DateTime _desde = DateTime.now();
  DateTime _hasta = DateTime.now();
  ReporteOrdenesAnuladasModel? _reporte;
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
      final r = await _repo.getOrdenesAnuladas(
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
        title: const Text('Órdenes anuladas'),
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
      selectedColor: AppColors.error,
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
          _buildResumenCard(r),
          const SizedBox(height: 16),
          if (r.ordenes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No hay órdenes anuladas en este período 🎉',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
              ),
            )
          else
            ...r.ordenes.map(_buildOrdenCard),
        ],
      ),
    );
  }

  Widget _buildResumenCard(ReporteOrdenesAnuladasModel r) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.error.withValues(alpha: 0.85), AppColors.error],
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
          const Text('Total en órdenes anuladas',
              style: TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 13)),
          Text('\$${_fmt.format(r.totalAnulado)}',
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 32)),
          const SizedBox(height: 4),
          Text('${r.totalOrdenes} orden${r.totalOrdenes == 1 ? '' : 'es'} anulada${r.totalOrdenes == 1 ? '' : 's'} en el período',
              style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _buildOrdenCard(OrdenModel o) {
    final fecha = (o.fechaCierre ?? o.fechaCreacion).toLocal();
    final fechaTxt = DateFormat('d MMM · HH:mm', 'es').format(fecha);
    final items = o.detalles.where((d) => d.estado != 'CANCELADO').toList();
    final total = items.fold(0.0, (s, d) => s + d.subtotal);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Theme(
        // Sin las líneas divisorias por defecto del ExpansionTile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Container(
            width: 38, height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
          ),
          title: Text('Orden #${o.numeroOrden} · ${o.lugar}',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text('$fechaTxt · ${items.length} item${items.length == 1 ? '' : 's'}'
                  '${o.canceladaPor?.isNotEmpty ?? false ? ' · Anuló: ${o.canceladaPor}' : ''}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary)),
              if (o.motivoCancelacion?.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Motivo: ${o.motivoCancelacion}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 11.5,
                          fontStyle: FontStyle.italic, color: AppColors.error)),
                ),
              ],
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${_fmt.format(total)}',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 14, color: AppColors.error)),
              const Text('ver detalle',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textHint)),
            ],
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (o.nombreUsuario.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Orden tomada por: ${o.nombreUsuario}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary)),
                ),
              ),
            ...items.map((d) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${d.cantidad}x',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 11, color: AppColors.error)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.nombrePlato,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5)),
                        if (d.observaciones?.isNotEmpty ?? false)
                          Text('Nota: ${d.observaciones}',
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 10.5,
                                  color: AppColors.warning, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  Text('\$${_fmt.format(d.subtotal)}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12)),
                ],
              ),
            )),
          ],
        ),
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
