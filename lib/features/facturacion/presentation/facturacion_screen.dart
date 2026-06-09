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
import '../../../features/caja/data/caja_repository.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente no encontrado'), backgroundColor: AppColors.warning),
        );
        setState(() => _clienteEncontrado = null);
      }
    }
  }

  double get _subtotalSeleccionado {
    if (_orden == null) return 0;
    return _orden!.detallesNoFacturados
        .where((d) => _itemsSeleccionados.contains(d.ordenDetalleId))
        .fold(0.0, (sum, d) => sum + d.subtotal);
  }

  bool get _puedeEmitir =>
      _itemsSeleccionados.isNotEmpty &&
      _selectedMetodoPagoId != null &&
      _aperturaCierreCajaId != null;

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

    setState(() => _emitiendo = true);
    try {
      final detalles = _orden!.detallesNoFacturados
          .where((d) => _itemsSeleccionados.contains(d.ordenDetalleId))
          .map((d) => {'ordenDetalleId': d.ordenDetalleId, 'cantidad': d.cantidad})
          .toList();

      final factura = await _factRepo.emitirFactura(
        ordenId: widget.ordenId,
        aperturaCierreCajaId: _aperturaCierreCajaId!,
        clienteId: _clienteEncontrado?.clienteId,
        detalles: detalles,
      );

      await _factRepo.registrarPago(
        facturaVentaId: factura.facturaVentaId,
        metodoPagoId: _selectedMetodoPagoId!,
        monto: factura.total,
        referencia: _refCtrl.text.trim().isNotEmpty ? _refCtrl.text.trim() : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Factura emitida correctamente!'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Facturación')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _buildError()
              : _buildBody(),
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
        const Text('Datos del cliente (opcional)',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
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
            : const Icon(Icons.receipt_rounded),
        label: Text(_emitiendo ? 'Emitiendo...' : 'Emitir Factura'),
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
