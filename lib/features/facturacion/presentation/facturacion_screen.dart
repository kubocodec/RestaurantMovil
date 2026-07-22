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
import '../../../shared/widgets/sri_estado_panel.dart';
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
  // IVA vigente de la sucursal (lo aplica el backend al emitir); 15 solo
  // como respaldo si el endpoint aún no existe en el servidor.
  double _ivaPorcentaje = 15;
  String? _aperturaCierreCajaId;
  bool _loading = true;
  bool _emitiendo = false;
  String? _error;
  String? _selectedMetodoPagoId;
  final _cedulaCtrl = TextEditingController();
  final _refCtrl    = TextEditingController();
  ClienteModel? _clienteEncontrado;

  /// Cuentas divididas: cuántas unidades de cada ítem entran en ESTE cobro
  /// (ordenDetalleId → cantidad elegida, entre 0 y lo pendiente).
  Map<String, int> _cantidadesElegidas = {};

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
      final metodos  = await _factRepo.getMetodosPago(_sucursalId);
      final iva      = await _factRepo.getIvaVigente(_sucursalId);
      final cajas    = await _cajaRepo.getCajasBySucursal(_sucursalId);
      AperturaCajaModel? apertura;
      if (cajas.isNotEmpty) {
        apertura = await _cajaRepo.getAperturaActiva(cajas.first.cajaId);
      }

      if (!mounted) return;
      setState(() {
        _orden = orden;
        _metodosPago = metodos;
        if (iva != null) _ivaPorcentaje = iva;
        _aperturaCierreCajaId = apertura?.aperturaCierreCajaId;
        if (metodos.isNotEmpty) _selectedMetodoPagoId = metodos.first.metodoPagoId;
        // Por defecto se cobra todo lo pendiente; el cajero baja cantidades
        // cuando el cliente paga solo una parte (cuentas divididas)
        _cantidadesElegidas = {
          for (final d in orden.detallesNoFacturados) d.ordenDetalleId: d.cantidadPendiente,
        };
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cliente no encontrado. Regístralo con el formulario.'),
          backgroundColor: AppColors.warning,
        ));
        _abrirFormularioCliente();
      }
    }
  }

  /// Abre el formulario de cliente: sin [cliente] registra uno nuevo
  /// (prellenando la cédula ya digitada); con [cliente] edita sus datos.
  Future<void> _abrirFormularioCliente({ClienteModel? cliente}) async {
    final resultado = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => _ClienteFormDialog(
        repo:          _factRepo,
        cliente:       cliente,
        cedulaInicial: cliente == null ? _cedulaCtrl.text.trim() : null,
      ),
    );
    if (resultado != null && mounted) {
      setState(() {
        _clienteEncontrado = resultado;
        _cedulaCtrl.text = resultado.cedulaRuc;
      });
    }
  }

  int _cantidadDe(String ordenDetalleId) => _cantidadesElegidas[ordenDetalleId] ?? 0;

  double get _subtotalSeleccionado {
    final orden = _orden;
    if (orden == null) return 0;
    return orden.detallesNoFacturados
        .fold(0.0, (sum, d) => sum + d.precioUnitario * _cantidadDe(d.ordenDetalleId));
  }

  bool get _haySeleccion => _cantidadesElegidas.values.any((c) => c > 0);

  bool get _puedeEmitir =>
      _haySeleccion &&
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

    // Confirmación explícita del método de pago: evita cobros registrados
    // como efectivo cuando fueron transferencia (y viceversa), que luego
    // descuadran el arqueo del cierre de caja.
    final confirmado = await _confirmarMetodoPago();
    if (confirmado != true || !mounted) return;

    setState(() => _emitiendo = true);
    try {
      // Solo los ítems con cantidad elegida > 0; se cobra esa cantidad
      // (puede ser parcial: cuentas divididas)
      final seleccionados = orden.detallesNoFacturados
          .where((d) => _cantidadDe(d.ordenDetalleId) > 0)
          .toList();
      final detalles = seleccionados
          .map((d) => {
                'ordenDetalleId': d.ordenDetalleId,
                'cantidad': _cantidadDe(d.ordenDetalleId),
              })
          .toList();
      // Copia para el comprobante (tras emitir quedan marcados facturados)
      final itemsRecibo = seleccionados
          .map((d) => ReciboItem(
                nombre: d.nombrePlato,
                cantidad: _cantidadDe(d.ordenDetalleId),
                subtotal: d.precioUnitario * _cantidadDe(d.ordenDetalleId),
              ))
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

  /// Diálogo previo al cobro que muestra el método de pago y el total en
  /// grande para que el cajero verifique antes de registrar el pago.
  Future<bool?> _confirmarMetodoPago() {
    final metodo = _metodoPagoSeleccionado;
    final nombreMetodo = metodo?.nombre ?? '';
    final subtotal = _subtotalSeleccionado;
    final total = subtotal + subtotal * (_ivaPorcentaje / 100);
    final esEfectivo = nombreMetodo.toUpperCase().contains('EFECTIVO');
    final icono = esEfectivo
        ? Icons.payments_outlined
        : nombreMetodo.toUpperCase().contains('TARJETA')
            ? Icons.credit_card_outlined
            : Icons.account_balance_outlined;
    final color = esEfectivo ? AppColors.success : AppColors.primary;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cobro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '¿Estás seguro del método de pago seleccionado?',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Icon(icono, color: color, size: 32),
                  const SizedBox(height: 6),
                  Text(nombreMetodo.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 18, color: color)),
                  const SizedBox(height: 2),
                  Text('\$${_fmt.format(total)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 22, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cambiar método'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cobrar'),
          ),
        ],
      ),
    );
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
    final lugar = _orden?.lugar ?? 'Mesa ?';
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
              Text(
                _orden?.esParaLlevar == true ? 'Para llevar' : 'Mesa: $lugar',
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13)),
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
    final todoSeleccionado = detalles.every(
      (d) => _cantidadDe(d.ordenDetalleId) == d.cantidadPendiente);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Ítems a cobrar', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
            TextButton(
              onPressed: () => setState(() {
                if (todoSeleccionado) {
                  _cantidadesElegidas.updateAll((_, __) => 0);
                } else {
                  _cantidadesElegidas = {
                    for (final d in detalles) d.ordenDetalleId: d.cantidadPendiente,
                  };
                }
              }),
              child: Text(
                todoSeleccionado ? 'Quitar todo' : 'Cobrar todo',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
              ),
            ),
          ],
        ),
        const Text(
          'Para cuentas divididas ajusta cuántas unidades paga este cliente; el resto queda pendiente.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: detalles.map((d) {
              final elegida = _cantidadDe(d.ordenDetalleId);
              final pendiente = d.cantidadPendiente;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.nombrePlato,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            '\$${_fmt.format(d.precioUnitario)} c/u · $pendiente pendiente${d.cantidadFacturada > 0 ? ' (${d.cantidadFacturada} ya cobradas)' : ''}',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    // Stepper: cuántas unidades entran en este cobro
                    _QtyBtn(
                      icon: Icons.remove,
                      enabled: elegida > 0,
                      onTap: () => setState(() => _cantidadesElegidas[d.ordenDetalleId] = elegida - 1),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text('$elegida/$pendiente',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
                          color: elegida > 0 ? AppColors.primary : AppColors.textHint)),
                    ),
                    _QtyBtn(
                      icon: Icons.add,
                      enabled: elegida < pendiente,
                      onTap: () => setState(() => _cantidadesElegidas[d.ordenDetalleId] = elegida + 1),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 62,
                      child: Text('\$${_fmt.format(d.precioUnitario * elegida)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 13, color: AppColors.primary)),
                    ),
                  ],
                ),
              );
            }).toList(),
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
                onSubmitted: (_) => _buscarCliente(),
                decoration: const InputDecoration(labelText: 'Cédula / RUC', prefixIcon: Icon(Icons.badge_outlined)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Buscar cliente',
              onPressed: _buscarCliente,
              icon: const Icon(Icons.search),
              style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Registrar cliente nuevo',
              onPressed: () => _abrirFormularioCliente(),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              style: IconButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
            ),
          ],
        ),
        if (_clienteEncontrado != null) _buildClienteCard(_clienteEncontrado!),
      ],
    );
  }

  /// Tarjeta con TODOS los datos del cliente para que el cajero los
  /// verifique antes de facturar (el email es clave: ahí llega la factura
  /// electrónica) y los corrija con el lápiz si cambiaron.
  Widget _buildClienteCard(ClienteModel c) {
    Widget dato(IconData icono, String texto, {bool alerta = false}) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icono, size: 14, color: alerta ? AppColors.warning : AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(texto,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                color: alerta ? AppColors.warning : AppColors.textSecondary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
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
                          fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                dato(Icons.badge_outlined, 'CI/RUC: ${c.cedulaRuc}'),
                c.tieneEmail
                    ? dato(Icons.email_outlined, c.email!)
                    : dato(Icons.email_outlined,
                        'Sin email: la factura irá al email de la sucursal', alerta: true),
                if (c.telefono?.isNotEmpty ?? false) dato(Icons.phone_outlined, c.telefono!),
                if (c.direccion?.isNotEmpty ?? false) dato(Icons.place_outlined, c.direccion!),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar datos del cliente',
            visualDensity: VisualDensity.compact,
            onPressed: () => _abrirFormularioCliente(cliente: c),
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
          ),
        ],
      ),
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
    final iva   = subtotal * (_ivaPorcentaje / 100);
    final total = subtotal + iva;
    final pctLabel = _ivaPorcentaje == _ivaPorcentaje.truncateToDouble()
        ? _ivaPorcentaje.toStringAsFixed(0)
        : _ivaPorcentaje.toStringAsFixed(1);
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
          _ResumenRow(label: 'IVA ($pctLabel%)', value: '\$${_fmt.format(iva)}'),
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

  /// El backend emite la factura electrónica en segundo plano tras el
  /// cobro; el panel SRI la va actualizando (así la impresión ya lleva la
  /// clave de acceso).
  late FacturaModel _factura = widget.factura;

  static const _ticketStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35);
  static const _ticketBold =
      TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final f = _factura;
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
                SriEstadoPanel(
                  factura: f,
                  autoConsultar: true,
                  onActualizada: (actualizada) => setState(() => _factura = actualizada),
                ),
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

      final via = await ComandaPrinter.imprimirRecibo(
        ip: elegida.ip,
        puerto: elegida.puerto ?? 9100,
        mac: elegida.mac,
        factura: _factura,
        items: widget.items,
        metodoPago: widget.metodoPago,
        esFactura: widget.esFactura,
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

/// Formulario de cliente para el cobro: registra uno nuevo o edita los
/// datos del encontrado (la cédula/RUC identifica al cliente y no se cambia
/// al editar). Devuelve el ClienteModel guardado al cerrar.
class _ClienteFormDialog extends StatefulWidget {
  final FacturacionRepository repo;
  final ClienteModel? cliente;   // null = registrar nuevo
  final String? cedulaInicial;   // prellenar cédula al registrar

  const _ClienteFormDialog({required this.repo, this.cliente, this.cedulaInicial});

  @override
  State<_ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<_ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre    = TextEditingController(text: widget.cliente?.nombre ?? '');
  late final _cedula    = TextEditingController(
      text: widget.cliente?.cedulaRuc ?? widget.cedulaInicial ?? '');
  late final _email     = TextEditingController(text: widget.cliente?.email ?? '');
  late final _telefono  = TextEditingController(text: widget.cliente?.telefono ?? '');
  late final _direccion = TextEditingController(text: widget.cliente?.direccion ?? '');
  bool _saving = false;

  bool get _esEdicion => widget.cliente != null;

  @override
  void dispose() {
    _nombre.dispose(); _cedula.dispose(); _email.dispose();
    _telefono.dispose(); _direccion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final ClienteModel guardado;
      if (_esEdicion) {
        guardado = await widget.repo.actualizarCliente(
          clienteId: widget.cliente!.clienteId,
          nombre:    _nombre.text.trim(),
          email:     _email.text.trim(),
          telefono:  _telefono.text.trim(),
          direccion: _direccion.text.trim(),
        );
      } else {
        guardado = await widget.repo.crearCliente(
          nombre:    _nombre.text.trim(),
          cedulaRuc: _cedula.text.trim(),
          email:     _email.text.trim(),
          telefono:  _telefono.text.trim(),
          direccion: _direccion.text.trim(),
        );
      }
      if (mounted) {
        Navigator.pop(context, guardado);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esEdicion ? 'Cliente actualizado' : 'Cliente registrado'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar cliente' : 'Registrar cliente',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombre,
                  autofocus: !_esEdicion,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Nombre / Razón social *',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cedula,
                  enabled: !_esEdicion,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Cédula / RUC *',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    helperText: _esEdicion ? 'La cédula/RUC no se puede cambiar' : null,
                  ),
                  validator: (v) {
                    final ced = (v ?? '').trim();
                    if (ced.isEmpty) return 'La cédula/RUC es requerida';
                    if (ced.length != 10 && ced.length != 13) {
                      return 'Debe tener 10 (cédula) o 13 (RUC) dígitos';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (recibe la factura electrónica)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    final email = (v ?? '').trim();
                    if (email.isEmpty) return null; // opcional: cae al email de la sucursal
                    if (!email.contains('@') || !email.contains('.')) return 'Email inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _direccion,
                  decoration: const InputDecoration(
                      labelText: 'Dirección', prefixIcon: Icon(Icons.place_outlined)),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _guardar,
          child: _saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_esEdicion ? 'Guardar cambios' : 'Registrar'),
        ),
      ],
    );
  }
}

/// Botón compacto de +/- para elegir cantidades en cuentas divididas.
class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _QtyBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: enabled ? Colors.white : AppColors.textHint),
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
