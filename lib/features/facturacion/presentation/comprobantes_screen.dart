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
import '../../../shared/widgets/cliente_busqueda.dart';
import '../../../shared/widgets/cliente_form_dialog.dart';
import '../../../shared/widgets/sri_estado_panel.dart';
import '../../configuracion/data/configuracion_repository.dart';
import '../data/facturacion_repository.dart';

/// Historial de notas de venta y facturas emitidas: para reimprimir, consultar
/// o emitir la factura cuando el cliente la pide después de haber pagado.
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

  /// Clasificación: TODOS | FACTURA | NOTA_VENTA | ANULADA
  String _filtro = 'TODOS';

  List<FacturaModel> get _visibles => switch (_filtro) {
    'FACTURA'    => _comprobantes.where((c) => c.esFactura && !c.isAnulada).toList(),
    'NOTA_VENTA' => _comprobantes.where((c) => c.esNotaVenta && !c.isAnulada).toList(),
    'ANULADA'    => _comprobantes.where((c) => c.isAnulada).toList(),
    _            => _comprobantes,
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
        title: const Text('Notas de venta y Facturas'),
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
    final notas    = _comprobantes.where((c) => c.esNotaVenta && !c.isAnulada).length;
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
                label: 'Notas de venta ($notas)',
                selected: _filtro == 'NOTA_VENTA',
                onTap: () => setState(() => _filtro = 'NOTA_VENTA'),
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
        // Si la nota de venta se convirtió en factura, el listado debe
        // reflejarlo al cerrar la hoja.
        onEmitida: _load,
      ),
    );
  }
}

/// Sello compacto del estado SRI en la lista de comprobantes.
class _SriMiniChip extends StatelessWidget {
  final String estado;

  const _SriMiniChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    final (color, texto) = switch (estado) {
      'AUTORIZADA' => (AppColors.success, 'SRI ✓'),
      'PROCESANDO' => (AppColors.warning, 'SRI…'),
      _            => (AppColors.error, 'SRI ✗'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(texto,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 9,
            fontWeight: FontWeight.w700, color: color)),
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
                      Text('${f.esFactura ? 'Factura' : 'Nota de venta'} ${f.numeroFactura}',
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
                      if (!f.isAnulada && f.tieneSri) ...[
                        const SizedBox(width: 6),
                        _SriMiniChip(estado: f.sriEstado!),
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
  /// Se llama cuando la nota de venta pasó a ser factura electrónica.
  final VoidCallback? onEmitida;

  const _DetalleComprobanteSheet({
    required this.factura,
    required this.fmt,
    required this.sucursalId,
    this.onEmitida,
  });

  @override
  State<_DetalleComprobanteSheet> createState() => _DetalleComprobanteSheetState();
}

class _DetalleComprobanteSheetState extends State<_DetalleComprobanteSheet> {
  final _configRepo = ConfiguracionRepository();
  final _factRepo = FacturacionRepository();
  bool _imprimiendo = false;
  bool _emitiendo = false;

  /// Cambia si la nota de venta se convierte en factura desde aquí.
  late FacturaModel _factura = widget.factura;

  static const _ticketStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35);
  static const _ticketBold =
      TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35, fontWeight: FontWeight.w700);

  /// La factura solo se puede pedir sobre una nota de venta ya cobrada.
  bool get _puedeEmitirFactura =>
      _factura.esNotaVenta && !_factura.isAnulada && _factura.estado == 'PAGADA';

  @override
  Widget build(BuildContext context) {
    final f = _factura;
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
                    '${f.esFactura ? 'Factura' : 'Nota de venta'} ${f.numeroFactura}${f.isAnulada ? ' (ANULADA)' : ''}',
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
                    Text('${f.esFactura ? 'FACTURA' : 'NOTA DE VENTA'} No. ${f.numeroFactura}',
                        style: _ticketBold),
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
                    if (f.tieneTarifasMixtas) ...[
                      _filaTicket('Subtotal 0%', f.subtotalSinIva!),
                      _filaTicket('Subtotal ${f.ivaPorcentaje.toStringAsFixed(0)}%',
                          f.subtotalGravado!),
                    ],
                    _filaTicket('IVA ${f.ivaPorcentaje.toStringAsFixed(0)}%', f.iva),
                    if (f.propina > 0) _filaTicket('Propina', f.propina),
                    _filaTicket('TOTAL', f.total, bold: true),
                    if (metodoPago.isNotEmpty) Text('Pago: $metodoPago', style: _ticketStyle),
                    // La nota de venta no va al SRI: no hay estado que mostrar.
                    if (!f.isAnulada && f.esFactura) SriEstadoPanel(factura: f),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_puedeEmitirFactura) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _emitiendo ? null : _emitirFactura,
                      icon: _emitiendo
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(_emitiendo
                          ? 'Emitiendo...'
                          : 'Emitir factura (el cliente la pidió)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
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

  /// Convierte la nota de venta en factura electrónica: pide los datos del
  /// cliente (el SRI los exige) y la envía. El cobro no se toca — es el
  /// mismo comprobante, ahora transmitido.
  Future<void> _emitirFactura() async {
    final cliente = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => _ClienteFacturaDialog(repo: _factRepo, total: _factura.total),
    );
    if (cliente == null || !mounted) return;

    setState(() => _emitiendo = true);
    try {
      final actualizada = await _factRepo.emitirSri(
        _factura.facturaVentaId,
        clienteId: cliente.clienteId,
      );
      if (!mounted) return;
      setState(() => _factura = actualizada);
      widget.onEmitida?.call();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Factura enviada al SRI'), backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _emitiendo = false);
    }
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

      final f = _factura;
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

/// Pide el cliente para emitir la factura de una nota de venta ya cobrada:
/// se busca por nombre o cédula/RUC, se puede corregir sus datos y, si no
/// está registrado, se crea al momento. El SRI exige identificar al
/// comprador, así que no se emite sin cliente.
class _ClienteFacturaDialog extends StatefulWidget {
  final FacturacionRepository repo;
  final double total;

  const _ClienteFacturaDialog({required this.repo, required this.total});

  @override
  State<_ClienteFacturaDialog> createState() => _ClienteFacturaDialogState();
}

class _ClienteFacturaDialogState extends State<_ClienteFacturaDialog> {
  final _busquedaCtrl = TextEditingController();
  ClienteModel? _cliente;
  bool _buscando = false;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    if (_busquedaCtrl.text.trim().isEmpty) return;
    setState(() => _buscando = true);
    final elegido = await buscarClienteInteractivo(
        context, widget.repo, _busquedaCtrl.text);
    if (!mounted) return;
    setState(() {
      _buscando = false;
      if (elegido != null) {
        _cliente = elegido;
        _busquedaCtrl.text = elegido.cedulaRuc;
      }
    });
  }

  /// Registrar uno nuevo, o editar el encontrado si sus datos cambiaron
  /// (el email importa: ahí llega la factura electrónica).
  Future<void> _abrirFormulario({ClienteModel? cliente}) async {
    final guardado = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => ClienteFormDialog(
        repo: widget.repo,
        cliente: cliente,
        cedulaInicial: cliente == null ? soloCedula(_busquedaCtrl.text) : null,
      ),
    );
    if (guardado != null && mounted) {
      setState(() { _cliente = guardado; _busquedaCtrl.text = guardado.cedulaRuc; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cliente;
    return AlertDialog(
      title: const Text('Emitir factura',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total del comprobante: \$${widget.total.toStringAsFixed(2)}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
            const SizedBox(height: 4),
            const Text('La factura se envía al SRI con los datos del cliente.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _busquedaCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _buscar(),
                    decoration: const InputDecoration(
                        labelText: 'Nombre o cédula / RUC',
                        prefixIcon: Icon(Icons.person_search_outlined)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Buscar cliente',
                  onPressed: _buscando ? null : _buscar,
                  icon: _buscando
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Registrar cliente nuevo',
                  onPressed: () => _abrirFormulario(),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  style: IconButton.styleFrom(
                      backgroundColor: AppColors.success, foregroundColor: Colors.white),
                ),
              ],
            ),
            if (c != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(c.nombre,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 13.5,
                                      fontWeight: FontWeight.w700),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          Text('CI/RUC: ${c.cedulaRuc}',
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12,
                                color: AppColors.textSecondary)),
                          Text(
                            c.tieneEmail
                                ? c.email!
                                : 'Sin email: la factura irá al email de la sucursal',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              color: c.tieneEmail ? AppColors.textSecondary : AppColors.warning),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          if (c.telefono?.isNotEmpty ?? false)
                            Text(c.telefono!,
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 12,
                                  color: AppColors.textSecondary)),
                          if (c.direccion?.isNotEmpty ?? false)
                            Text(c.direccion!,
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 12,
                                  color: AppColors.textSecondary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar datos del cliente',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _abrirFormulario(cliente: c),
                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: c == null ? null : () => Navigator.pop(context, c),
          child: const Text('Emitir factura'),
        ),
      ],
    );
  }
}
