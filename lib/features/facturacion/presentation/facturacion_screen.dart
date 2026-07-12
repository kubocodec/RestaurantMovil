import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/caja_model.dart';
import '../../../core/models/factura_model.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/config_models.dart';
import '../../../core/printing/comanda_printer.dart';
import '../../../features/caja/data/caja_repository.dart';
import '../../../features/configuracion/data/configuracion_repository.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';
import '../data/facturacion_repository.dart';

class FacturacionScreen extends StatefulWidget {
  final String ordenId;
  const FacturacionScreen({super.key, required this.ordenId});

  @override
  State<FacturacionScreen> createState() => _FacturacionScreenState();
}

class _FacturacionScreenState extends State<FacturacionScreen> {
  final _ordenRepo = OrdenesRepository();
  final _factRepo  = FacturacionRepository();
  final _cajaRepo  = CajaRepository();
  final _fmt = NumberFormat('#,##0.00', 'es');

  OrdenModel? _orden;
  List<MetodoPagoModel> _metodosPago = [];
  String? _aperturaCierreCajaId;
  bool _loading = true;
  bool _emitiendo = false;
  String? _error;
  String? _selectedMetodoPagoId;
  final _cedulaCtrl = TextEditingController();
  final _refCtrl    = TextEditingController();
  ClienteModel? _clienteEncontrado;
  Set<String> _itemsSeleccionados = {};

  // false = recibo a consumidor final; true = factura con datos del cliente
  bool _esFactura = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final orden    = await _ordenRepo.getOrden(widget.ordenId);
      final metodos  = await _factRepo.getMetodosPago();
      final cajas    = await _cajaRepo.getCajasBySucursal(_sucursalId);
      AperturaCajaModel? apertura;
      if (cajas.isNotEmpty) {
        apertura = await _cajaRepo.getAperturaActiva(cajas.first.cajaId);
      }

      if (!mounted) return;
      setState(() {
        _orden = orden;
        _metodosPago = metodos;
        _aperturaCierreCajaId = apertura?.aperturaCierreCajaId;
        if (metodos.isNotEmpty) _selectedMetodoPagoId = metodos.first.metodoPagoId;
        _itemsSeleccionados = Set.from(orden.detallesNoFacturados.map((d) => d.ordenDetalleId));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _buscarCliente() async {
    if (_cedulaCtrl.text.trim().isEmpty) return;
    final cliente = await _factRepo.buscarClientePorCedula(_cedulaCtrl.text.trim());
    if (mounted) {
      if (cliente != null) {
        setState(() => _clienteEncontrado = cliente);
      } else {
        setState(() => _clienteEncontrado = null);
        _ofrecerRegistroCliente();
      }
    }
  }

  void _ofrecerRegistroCliente() {
    final nombreCtrl = TextEditingController();
    final cedulaCtrl = TextEditingController(text: _cedulaCtrl.text.trim());
    final telefonoCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar cliente',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('El cliente no existe. Regístralo para incluirlo en la factura.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: nombreCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre / Razón social *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cedulaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cédula / RUC *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              final cedula = cedulaCtrl.text.trim();
              if (nombre.isEmpty || cedula.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nombre y cédula/RUC son requeridos')),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                final cliente = await _factRepo.crearCliente(
                  nombre: nombre,
                  cedulaRuc: cedula,
                  telefono: telefonoCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                );
                if (mounted) {
                  setState(() {
                    _clienteEncontrado = cliente;
                    _cedulaCtrl.text = cliente.cedulaRuc;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Cliente registrado'), backgroundColor: AppColors.success,
                  ));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  double get _subtotalSeleccionado {
    final orden = _orden;
    if (orden == null) return 0;
    return orden.detallesNoFacturados
        .where((d) => _itemsSeleccionados.contains(d.ordenDetalleId))
        .fold(0.0, (sum, d) => sum + d.subtotal);
  }

  bool get _puedeEmitir =>
      _itemsSeleccionados.isNotEmpty &&
      _selectedMetodoPagoId != null &&
      _aperturaCierreCajaId != null &&
      (!_esFactura || _clienteEncontrado != null);

  MetodoPagoModel? get _metodoPagoSeleccionado =>
      _metodosPago.where((m) => m.metodoPagoId == _selectedMetodoPagoId).firstOrNull;

  Future<void> _emitirFactura() async {
    if (!_puedeEmitir) {
      final msg = _aperturaCierreCajaId == null
          ? 'No hay caja abierta. Abre la caja antes de facturar.'
          : 'Selecciona al menos un ítem y un método de pago.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.warning),
      );
      return;
    }

    final orden = _orden;
    final aperturaCierreCajaId = _aperturaCierreCajaId;
    final metodoPagoId = _selectedMetodoPagoId;
    if (orden == null || aperturaCierreCajaId == null || metodoPagoId == null) return;

    setState(() => _emitiendo = true);
    try {
      final seleccionados = orden.detallesNoFacturados
          .where((d) => _itemsSeleccionados.contains(d.ordenDetalleId))
          .toList();
      final detalles = seleccionados
          .map((d) => {'ordenDetalleId': d.ordenDetalleId, 'cantidad': d.cantidad})
          .toList();
      // Copia para el comprobante (tras emitir quedan marcados facturados)
      final itemsRecibo = seleccionados
          .map((d) => ReciboItem(nombre: d.nombrePlato, cantidad: d.cantidad, subtotal: d.subtotal))
          .toList();

      final factura = await _factRepo.emitirFactura(
        ordenId: widget.ordenId,
        aperturaCierreCajaId: aperturaCierreCajaId,
        clienteId: _esFactura ? _clienteEncontrado?.clienteId : null,
        detalles: detalles,
      );

      final facturaPagada = await _factRepo.registrarPago(
        facturaVentaId: factura.facturaVentaId,
        metodoPagoId: metodoPagoId,
        monto: factura.total,
        referencia: _refCtrl.text.trim().isNotEmpty ? _refCtrl.text.trim() : null,
      );

      if (mounted) {
        await _mostrarComprobante(facturaPagada, itemsRecibo);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _emitiendo = false);
    }
  }

  Future<void> _mostrarComprobante(FacturaModel factura, List<ReciboItem> items) async {
    final metodoPago = _metodoPagoSeleccionado?.nombre ?? '';
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ComprobanteDialog(
        factura: factura,
        items: items,
        metodoPago: metodoPago,
        esFactura: _esFactura,
        sucursalId: _sucursalId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Facturación')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_aperturaCierreCajaId == null) _buildCajaWarning(),
          _buildOrdenInfo(),
          const SizedBox(height: 16),
          _buildItemsSelector(),
          const SizedBox(height: 16),
          _buildClienteSection(),
          const SizedBox(height: 16),
          _buildMetodoPago(),
          const SizedBox(height: 16),
          _buildResumen(),
          const SizedBox(height: 20),
          _buildEmitirBtn(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCajaWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text('No hay caja abierta. Ve a Gestión de Caja y ábrela primero.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.warning)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdenInfo() {
    final mesa = _orden?.numeroMesa ?? 'Mesa ?';
    final estado = _orden?.estado ?? '';
    final numero = _orden?.numeroOrden.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Orden #$numero', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
              Text('Mesa: $mesa', style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13)),
              Text('Estado: $estado', style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSelector() {
    final detalles = _orden?.detallesNoFacturados ?? [];
    if (detalles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(14)),
        child: const Center(child: Text('No hay ítems pendientes de facturar',
          style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Ítems a facturar', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
            TextButton(
              onPressed: () => setState(() {
                if (_itemsSeleccionados.length == detalles.length) {
                  _itemsSeleccionados.clear();
                } else {
                  _itemsSeleccionados = Set.from(detalles.map((d) => d.ordenDetalleId));
                }
              }),
              child: Text(
                _itemsSeleccionados.length == detalles.length ? 'Deseleccionar todo' : 'Seleccionar todo',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: detalles.map((d) => CheckboxListTile(
              value: _itemsSeleccionados.contains(d.ordenDetalleId),
              onChanged: (val) => setState(() {
                if (val == true) {
                  _itemsSeleccionados.add(d.ordenDetalleId);
                } else {
                  _itemsSeleccionados.remove(d.ordenDetalleId);
                }
              }),
              title: Text('${d.cantidad}× ${d.nombrePlato}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              subtitle: Text('\$${_fmt.format(d.precioUnitario)} c/u',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              secondary: Text('\$${_fmt.format(d.subtotal)}',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
              activeColor: AppColors.primary,
              dense: true,
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildClienteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tipo de comprobante',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('Recibo (consumidor final)'),
                selected: !_esFactura,
                onSelected: (_) => setState(() => _esFactura = false),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12,
                  color: !_esFactura ? Colors.white : AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Factura (con datos)'),
                selected: _esFactura,
                onSelected: (_) => setState(() => _esFactura = true),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12,
                  color: _esFactura ? Colors.white : AppColors.textPrimary),
              ),
            ),
          ],
        ),
        if (_esFactura) _buildDatosCliente(),
      ],
    );
  }

  Widget _buildDatosCliente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Datos del cliente (requeridos para la factura)',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cedulaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cédula / RUC', prefixIcon: Icon(Icons.badge_outlined)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _buscarCliente,
              icon: const Icon(Icons.search),
              style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
          ],
        ),
        if (_clienteEncontrado != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                const SizedBox(width: 4),
                Text('Cliente: ${_clienteEncontrado!.nombre}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.success)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMetodoPago() {
    if (_metodosPago.isEmpty) return const SizedBox.shrink();
    final requiereRef = _metodoPagoSeleccionado?.requiereReferencia == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Método de pago',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _metodosPago.map((m) {
            final isSelected = _selectedMetodoPagoId == m.metodoPagoId;
            return ChoiceChip(
              label: Text(m.nombre),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedMetodoPagoId = m.metodoPagoId),
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontSize: 13,
              ),
            );
          }).toList(),
        ),
        if (requiereRef) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _refCtrl,
            decoration: const InputDecoration(
              labelText: 'Referencia / Número de transacción',
              prefixIcon: Icon(Icons.numbers_outlined),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResumen() {
    final subtotal = _subtotalSeleccionado;
    final iva   = subtotal * 0.15;
    final total = subtotal + iva;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _ResumenRow(label: 'Subtotal', value: '\$${_fmt.format(subtotal)}'),
          const SizedBox(height: 6),
          _ResumenRow(label: 'IVA (15%)', value: '\$${_fmt.format(iva)}'),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: AppColors.divider)),
          _ResumenRow(label: 'TOTAL', value: '\$${_fmt.format(total)}', isBold: true, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildEmitirBtn() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: (_puedeEmitir && !_emitiendo) ? _emitirFactura : null,
        icon: _emitiendo
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.point_of_sale_rounded),
        label: Text(_emitiendo
            ? 'Cobrando...'
            : _esFactura ? 'Cobrar y emitir factura' : 'Cobrar (recibo)'),
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
          ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      ),
    );
  }
}

/// Comprobante emitido: vista tipo ticket con opción de imprimir en una
/// impresora de la sucursal.
class _ComprobanteDialog extends StatefulWidget {
  final FacturaModel factura;
  final List<ReciboItem> items;
  final String metodoPago;
  final bool esFactura;
  final String sucursalId;

  const _ComprobanteDialog({
    required this.factura,
    required this.items,
    required this.metodoPago,
    required this.esFactura,
    required this.sucursalId,
  });

  @override
  State<_ComprobanteDialog> createState() => _ComprobanteDialogState();
}

class _ComprobanteDialogState extends State<_ComprobanteDialog> {
  final _configRepo = ConfiguracionRepository();
  bool _imprimiendo = false;

  static const _ticketStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35);
  static const _ticketBold =
      TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final f = widget.factura;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success),
          const SizedBox(width: 8),
          Text(widget.esFactura ? 'Factura emitida' : 'Recibo emitido',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
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
                if (f.nombreSucursal.isNotEmpty)
                  Text(f.nombreSucursal, textAlign: TextAlign.center, style: _ticketStyle),
                if (f.direccionSucursal?.isNotEmpty ?? false)
                  Text(f.direccionSucursal!, textAlign: TextAlign.center, style: _ticketStyle),
                if (f.telefonoSucursal?.isNotEmpty ?? false)
                  Text('Tel: ${f.telefonoSucursal}', textAlign: TextAlign.center, style: _ticketStyle),
                const Divider(),
                Text('${widget.esFactura ? 'FACTURA' : 'RECIBO'} No. ${f.numeroFactura}', style: _ticketBold),
                Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(f.fecha.toLocal())}', style: _ticketStyle),
                Text('Orden: #${f.numeroOrden}', style: _ticketStyle),
                Text('Cliente: ${f.nombreCliente ?? 'Consumidor Final'}', style: _ticketStyle),
                if (f.cedulaRucCliente?.isNotEmpty ?? false)
                  Text('CI/RUC: ${f.cedulaRucCliente}', style: _ticketStyle),
                const Divider(),
                ...widget.items.map((it) => _filaTicket('${it.cantidad} x ${it.nombre}', it.subtotal)),
                const Divider(),
                _filaTicket('Subtotal', f.subtotal),
                if (f.descuento > 0) _filaTicket('Descuento', -f.descuento),
                _filaTicket('IVA ${f.ivaPorcentaje.toStringAsFixed(0)}%', f.iva),
                if (f.propina > 0) _filaTicket('Propina', f.propina),
                _filaTicket('TOTAL', f.total, bold: true),
                Text('Pago: ${widget.metodoPago}', style: _ticketStyle),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _imprimiendo ? null : _imprimir,
          icon: _imprimiendo
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.print_outlined, size: 18),
          label: Text(_imprimiendo ? 'Imprimiendo...' : 'Imprimir'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Listo'),
        ),
      ],
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
          .where((i) => i.activo && (i.ip?.isNotEmpty ?? false))
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

      await ComandaPrinter.imprimirRecibo(
        ip: elegida.ip!,
        puerto: elegida.puerto ?? 9100,
        factura: widget.factura,
        items: widget.items,
        metodoPago: widget.metodoPago,
        esFactura: widget.esFactura,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Comprobante impreso'), backgroundColor: AppColors.success,
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

class _ResumenRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? color;

  const _ResumenRow({required this.label, required this.value, this.isBold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          fontSize: isBold ? 16 : 14,
          color: color ?? AppColors.textPrimary)),
        Text(value, style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          fontSize: isBold ? 18 : 14,
          color: color ?? AppColors.textPrimary)),
      ],
    );
  }
}
