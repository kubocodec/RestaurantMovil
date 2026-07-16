import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/models/factura_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/comanda_printer.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../configuracion/data/configuracion_repository.dart';
import '../data/facturacion_repository.dart';

/// Historial de recibos y facturas emitidos: para reimprimir o consultar
/// cuando el cliente vuelve a pedir su comprobante.
class ComprobantesScreen extends StatefulWidget {
  const ComprobantesScreen({super.key});

  @override
  State<ComprobantesScreen> createState() => _ComprobantesScreenState();
}

class _ComprobantesScreenState extends State<ComprobantesScreen> {
  final _repo = FacturacionRepository();
  final _fmt = NumberFormat('#,##0.00');
  List<FacturaModel> _comprobantes = [];
  DateTime _fecha = DateTime.now();
  bool _loading = true;
  String? _error;

  /// Clasificación: TODOS | FACTURA | RECIBO | ANULADA
  String _filtro = 'TODOS';

  List<FacturaModel> get _visibles => switch (_filtro) {
    'FACTURA' => _comprobantes.where((c) => c.esFactura && !c.isAnulada).toList(),
    'RECIBO'  => _comprobantes.where((c) => !c.esFactura && !c.isAnulada).toList(),
    'ANULADA' => _comprobantes.where((c) => c.isAnulada).toList(),
    _         => _comprobantes,
  };

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _repo.getComprobantes(_sucursalId, fecha: _fecha);
      if (!mounted) return;
      setState(() { _comprobantes = data; _loading = false; });
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
      locale: const Locale('es'),
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
        title: const Text('Recibos y Facturas'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.cardBackground,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
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
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? _buildError()
                      : _buildLista(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
        ],
      ),
    ),
  );

  Widget _buildLista() {
    if (_comprobantes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
            SizedBox(height: 16),
            Text('No hay comprobantes en esta fecha',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final visibles = _visibles;
    final totalDia = _comprobantes
        .where((c) => !c.isAnulada)
        .fold(0.0, (s, c) => s + c.total);
    final facturas = _comprobantes.where((c) => c.esFactura && !c.isAnulada).length;
    final recibos  = _comprobantes.where((c) => !c.esFactura && !c.isAnulada).length;
    final anuladas = _comprobantes.where((c) => c.isAnulada).length;

    return Column(
      children: [
        // Clasificación de comprobantes
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FiltroChip(
                label: 'Todos (${_comprobantes.length})',
                selected: _filtro == 'TODOS',
                onTap: () => setState(() => _filtro = 'TODOS'),
              ),
              _FiltroChip(
                label: 'Facturas ($facturas)',
                selected: _filtro == 'FACTURA',
                onTap: () => setState(() => _filtro = 'FACTURA'),
              ),
              _FiltroChip(
                label: 'Recibos ($recibos)',
                selected: _filtro == 'RECIBO',
                onTap: () => setState(() => _filtro = 'RECIBO'),
              ),
              _FiltroChip(
                label: 'Anulados ($anuladas)',
                selected: _filtro == 'ANULADA',
                onTap: () => setState(() => _filtro = 'ANULADA'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${visibles.length} comprobantes',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
              Text('Total del día: \$${_fmt.format(totalDia)}',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13,
                    fontWeight: FontWeight.w700, color: AppColors.cajeroColor)),
            ],
          ),
        ),
        Expanded(
          child: visibles.isEmpty
              ? const Center(
                  child: Text('Sin comprobantes de este tipo',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: visibles.length,
                    itemBuilder: (_, i) => _ComprobanteCard(
                      factura: visibles[i],
                      fmt: _fmt,
                      onTap: () => _verDetalle(visibles[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _verDetalle(FacturaModel f) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DetalleComprobanteSheet(
        factura: f,
        fmt: _fmt,
        sucursalId: _sucursalId,
      ),
    );
  }
}

class _FiltroChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FiltroChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.primary : AppColors.divider),
          ),
          child: Text(label,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary)),
        ),
      ),
    );
  }
}

class _ComprobanteCard extends StatelessWidget {
  final FacturaModel factura;
  final NumberFormat fmt;
  final VoidCallback onTap;

  const _ComprobanteCard({required this.factura, required this.fmt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final f = factura;
    final color = f.isAnulada
        ? AppColors.error
        : f.esFactura ? AppColors.primary : AppColors.cajeroColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
          border: f.isAnulada ? Border.all(color: AppColors.error.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(
                f.esFactura ? Icons.receipt_long_outlined : Icons.receipt_outlined,
                color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${f.esFactura ? 'Factura' : 'Recibo'} ${f.numeroFactura}',
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                      if (f.isAnulada) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('ANULADA',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 9,
                                fontWeight: FontWeight.w700, color: AppColors.error)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${DateFormat('HH:mm').format(f.fecha.toLocal())} · ${f.nombreCliente ?? 'Consumidor Final'}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text('\$${fmt.format(f.total)}',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 14, color: f.isAnulada ? AppColors.textHint : AppColors.textPrimary,
                  decoration: f.isAnulada ? TextDecoration.lineThrough : null)),
          ],
        ),
      ),
    );
  }
}

/// Detalle tipo ticket con opción de reimpresión.
class _DetalleComprobanteSheet extends StatefulWidget {
  final FacturaModel factura;
  final NumberFormat fmt;
  final String sucursalId;

  const _DetalleComprobanteSheet({
    required this.factura,
    required this.fmt,
    required this.sucursalId,
  });

  @override
  State<_DetalleComprobanteSheet> createState() => _DetalleComprobanteSheetState();
}

class _DetalleComprobanteSheetState extends State<_DetalleComprobanteSheet> {
  final _configRepo = ConfiguracionRepository();
  bool _imprimiendo = false;

  static const _ticketStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35);
  static const _ticketBold =
      TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final f = widget.factura;
    final metodoPago = f.pagos.map((p) => p.nombreMetodoPago).join(', ');
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(f.esFactura ? Icons.receipt_long_outlined : Icons.receipt_outlined,
                    color: f.isAnulada ? AppColors.error : AppColors.cajeroColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${f.esFactura ? 'Factura' : 'Recibo'} ${f.numeroFactura}${f.isAnulada ? ' (ANULADA)' : ''}',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(f.nombreRestaurant.isNotEmpty ? f.nombreRestaurant : f.nombreSucursal,
                        textAlign: TextAlign.center, style: _ticketBold),
                    if (f.razonSocial?.isNotEmpty ?? false)
                      Text(f.razonSocial!, textAlign: TextAlign.center, style: _ticketStyle),
                    if (f.rucSucursal?.isNotEmpty ?? false)
                      Text('RUC: ${f.rucSucursal}', textAlign: TextAlign.center, style: _ticketStyle),
                    if (f.direccionSucursal?.isNotEmpty ?? false)
                      Text(f.direccionSucursal!, textAlign: TextAlign.center, style: _ticketStyle),
                    const Divider(),
                    Text('${f.esFactura ? 'FACTURA' : 'RECIBO'} No. ${f.numeroFactura}', style: _ticketBold),
                    Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(f.fecha.toLocal())}', style: _ticketStyle),
                    Text('Orden: #${f.numeroOrden}', style: _ticketStyle),
                    Text('Cliente: ${f.nombreCliente ?? 'Consumidor Final'}', style: _ticketStyle),
                    if (f.cedulaRucCliente?.isNotEmpty ?? false)
                      Text('CI/RUC: ${f.cedulaRucCliente}', style: _ticketStyle),
                    const Divider(),
                    ...f.items.map((it) => _filaTicket('${it.cantidad} x ${it.nombre}', it.subtotal)),
                    const Divider(),
                    _filaTicket('Subtotal', f.subtotal),
                    if (f.descuento > 0) _filaTicket('Descuento', -f.descuento),
                    _filaTicket('IVA ${f.ivaPorcentaje.toStringAsFixed(0)}%', f.iva),
                    if (f.propina > 0) _filaTicket('Propina', f.propina),
                    _filaTicket('TOTAL', f.total, bold: true),
                    if (metodoPago.isNotEmpty) Text('Pago: $metodoPago', style: _ticketStyle),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: AppColors.cardBackground,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _imprimiendo ? null : _imprimir,
                    icon: _imprimiendo
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.print_outlined, size: 18),
                    label: Text(_imprimiendo ? 'Imprimiendo...' : 'Reimprimir'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTicket(String concepto, double monto, {bool bold = false}) {
    final style = bold ? _ticketBold : _ticketStyle;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(concepto, style: style)),
        Text('\$${monto.toStringAsFixed(2)}', style: style),
      ],
    );
  }

  Future<void> _imprimir() async {
    setState(() => _imprimiendo = true);
    try {
      final impresoras = (await _configRepo.getImpresoras(widget.sucursalId))
          .where((i) => i.activo && i.imprimible)
          .toList();
      if (!mounted) return;
      if (impresoras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay impresoras configuradas en la sucursal'),
          backgroundColor: AppColors.warning,
        ));
        return;
      }
      ImpresoraModel? elegida = impresoras.length == 1 ? impresoras.first : null;
      elegida ??= await showDialog<ImpresoraModel>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Imprimir en', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          children: impresoras.map((i) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Text('${i.nombre}${i.area?.isNotEmpty == true ? ' (${i.area})' : ''}',
                style: const TextStyle(fontFamily: 'Poppins')),
          )).toList(),
        ),
      );
      if (elegida == null) return;

      final f = widget.factura;
      final via = await ComandaPrinter.imprimirRecibo(
        ip: elegida.ip,
        puerto: elegida.puerto ?? 9100,
        mac: elegida.mac,
        factura: f,
        items: f.items
            .map((it) => ReciboItem(nombre: it.nombre, cantidad: it.cantidad, subtotal: it.subtotal))
            .toList(),
        metodoPago: f.pagos.map((p) => p.nombreMetodoPago).join(', '),
        esFactura: f.esFactura,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Comprobante impreso por $via'), backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo imprimir: ${ApiClient.parseError(e)}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }
}
