import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/caja_model.dart';
import '../../../core/models/factura_model.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../core/models/config_models.dart';
import '../../../core/printing/comanda_printer.dart';
import '../../../core/settings/ajustes_cobro.dart';
import '../../../features/caja/data/caja_repository.dart';
import '../../../features/configuracion/data/configuracion_repository.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';
import '../../../shared/widgets/cliente_busqueda.dart';
import '../../../shared/widgets/cliente_form_dialog.dart';
import '../../../shared/widgets/cortesia_dialog.dart';
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
  final _propinaCtrl = TextEditingController();
  final _recibidoCtrl = TextEditingController();
  ClienteModel? _clienteEncontrado;

  /// Cuentas divididas: cuántas unidades de cada ítem entran en ESTE cobro
  /// (ordenDetalleId → cantidad elegida, entre 0 y lo pendiente).
  Map<String, int> _cantidadesElegidas = {};

  /// false = nota de venta (comprobante interno, no va al SRI) — es lo
  /// predeterminado; true = factura electrónica con datos del cliente, solo
  /// cuando el cliente la pide.
  bool _esFactura = false;

  /// Propina de ESTE cobro, en dólares (monto libre, no porcentaje). La
  /// elige el cajero en el diálogo de confirmación; el backend la suma al
  /// total sin cobrarle IVA.
  double _propina = 0;

  /// Efectivo que entregó el cliente en ESTE cobro, si el cajero usa la
  /// calculadora de vuelto. Solo es para mostrar e imprimir: el pago se
  /// registra por el total de la cuenta, o el arqueo del cajón se inflaría
  /// con el vuelto.
  double? _recibido;

  /// Pago dividido de ESTE cobro (ej. $15 efectivo + $11.50 transferencia);
  /// null = un solo método, el camino de siempre. La última fila no lleva
  /// monto: es lo que falta para el total que devuelve el servidor, así la
  /// suma cuadra al centavo aunque el redondeo local difiera.
  List<({String metodoPagoId, int? centavos, String? referencia})>? _pagosDivididos;

  /// Pago dividido: hasta 3 métodos. Los controllers viven en el State y no en
  /// el diálogo (ver la trampa del TextEditingController en CLAUDE.md).
  static const _maxFilasDivision = 3;
  final _montoDivCtrls = List.generate(_maxFilasDivision, (_) => TextEditingController());
  final _refDivCtrls = List.generate(_maxFilasDivision, (_) => TextEditingController());

  String get _usuarioId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.id : '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    _refCtrl.dispose();
    _propinaCtrl.dispose();
    _recibidoCtrl.dispose();
    for (final c in [..._montoDivCtrls, ..._refDivCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  bool get _esAdmin {
    final s = context.read<AuthBloc>().state;
    if (s is! AuthAuthenticated) return false;
    return s.user.rol == UserRole.admin || s.user.rol == UserRole.superadmin;
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

  /// Busca por nombre o cédula/RUC: con varias coincidencias se elige de una
  /// lista y sin ninguna se abre el formulario para registrarlo.
  Future<void> _buscarCliente() async {
    if (_cedulaCtrl.text.trim().isEmpty) return;
    final cliente = await buscarClienteInteractivo(context, _factRepo, _cedulaCtrl.text);
    if (cliente != null && mounted) {
      setState(() {
        _clienteEncontrado = cliente;
        _cedulaCtrl.text = cliente.cedulaRuc;
      });
    }
  }

  /// Abre el formulario de cliente: sin [cliente] registra uno nuevo
  /// (prellenando la cédula ya digitada); con [cliente] edita sus datos.
  Future<void> _abrirFormularioCliente({ClienteModel? cliente}) async {
    final resultado = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => ClienteFormDialog(
        repo:          _factRepo,
        cliente:       cliente,
        // Solo prellena si lo digitado son dígitos: si se buscó por nombre,
        // no es una cédula.
        cedulaInicial: cliente == null ? soloCedula(_cedulaCtrl.text) : null,
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

  bool get _haySeleccion => _cantidadesElegidas.values.any((c) => c > 0);

  /// Desglose de lo seleccionado **igual que el backend y que Factuplan**:
  /// cada línea lleva la tarifa de su plato (o la predeterminada del negocio si
  /// no tiene propia), las bases se agrupan por tarifa y el IVA se redondea
  /// línea por línea.
  ///
  /// Antes esto era `subtotal * (una sola tasa)`, y en un negocio con la comida
  /// al 0% y las bebidas embotelladas al 15% el cajero veía —y le decía al
  /// cliente— un total sin el IVA de las bebidas, mientras se cobraba el
  /// correcto. El número en pantalla tiene que ser el del comprobante.
  _DesgloseCobro get _desglose {
    final orden = _orden;
    if (orden == null) return const _DesgloseCobro(0, 0, {});

    // Todo en centavos enteros: con doubles, 0,2625 puede quedar en
    // 0,26249999 y redondear para el lado equivocado. La tarifa va en
    // centésimas de punto (15% = 1500).
    final basePorTarifa = <int, int>{};
    int ivaCentavos = 0;
    for (final d in orden.detallesNoFacturados) {
      final cantidad = _cantidadDe(d.ordenDetalleId);
      if (cantidad <= 0) continue;
      // Cortesía: se descuenta completa en el backend, no suma base ni IVA.
      if (d.cortesia) continue;
      final tarifa = d.ivaPorcentaje ?? _ivaPorcentaje;
      final clave = (tarifa * 100).round();
      final baseCentavos = (d.precioUnitario * 100).round() * cantidad;
      basePorTarifa[clave] = (basePorTarifa[clave] ?? 0) + baseCentavos;
      // IVA redondeado por línea (mitad hacia arriba), igual que el backend y
      // que Factuplan: agrupado por tarifa daba a veces un centavo más.
      if (clave > 0) ivaCentavos += (baseCentavos * clave + 5000) ~/ 10000;
    }

    double subtotal = 0;
    final bases = <double, double>{};
    basePorTarifa.forEach((clave, base) {
      subtotal += base / 100;
      bases[clave / 100] = base / 100;
    });
    return _DesgloseCobro(subtotal, ivaCentavos / 100, bases);
  }

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
    // Todo lo elegido es cortesía: no hay método de pago que confirmar.
    final sinCobro = _desglose.total == 0;
    final confirmado = sinCobro ? await _confirmarSinCobro() : await _confirmarMetodoPago();
    if (confirmado != true || !mounted) return;
    if (sinCobro) {
      _propina = 0;
      _pagosDivididos = null;
    }

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
                cortesia: d.cortesia,
              ))
          .toList();

      final factura = await _factRepo.emitirFactura(
        ordenId: widget.ordenId,
        aperturaCierreCajaId: aperturaCierreCajaId,
        clienteId: _esFactura ? _clienteEncontrado?.clienteId : null,
        tipoComprobante: _esFactura ? 'FACTURA' : 'NOTA_VENTA',
        detalles: detalles,
        propina: _propina,
      );

      // Una cuenta en $0 (solo cortesías) el backend la deja pagada al
      // emitirla: no hay pago que registrar (y un pago de $0 sería rechazado).
      final divididos = _pagosDivididos;
      final facturaPagada = factura.estado == 'PAGADA'
          ? factura
          : divididos != null
              ? await _factRepo.registrarPagos(
                  facturaVentaId: factura.facturaVentaId,
                  pagos: _armarPagosDivididos(divididos, factura.total),
                )
              : await _factRepo.registrarPago(
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

  /// Montos del pago dividido contra el total del servidor: la última fila
  /// se lleva lo que falta, en centavos enteros para que sumen exacto.
  List<({String metodoPagoId, double monto, String? referencia})> _armarPagosDivididos(
      List<({String metodoPagoId, int? centavos, String? referencia})> filas, double total) {
    var restante = (total * 100).round();
    final pagos = <({String metodoPagoId, double monto, String? referencia})>[];
    for (final f in filas) {
      final centavos = f.centavos ?? restante;
      restante -= centavos;
      pagos.add((metodoPagoId: f.metodoPagoId, monto: centavos / 100, referencia: f.referencia));
    }
    return pagos;
  }

  /// Diálogo previo al cobro que muestra el método de pago y el total en
  /// grande para que el cajero verifique antes de registrar el pago, y donde
  /// se pregunta por la propina (monto libre en dólares, opcional).
  Future<bool?> _confirmarMetodoPago() async {
    final metodo = _metodoPagoSeleccionado;
    final nombreMetodo = metodo?.nombre ?? '';
    final consumo = _desglose.total;
    final esEfectivo = nombreMetodo.toUpperCase().contains('EFECTIVO');
    final icono = esEfectivo
        ? Icons.payments_outlined
        : nombreMetodo.toUpperCase().contains('TARJETA')
            ? Icons.credit_card_outlined
            : Icons.account_balance_outlined;
    final color = esEfectivo ? AppColors.success : AppColors.primary;

    // Se conserva lo ya escrito si el cajero vuelve a abrir el diálogo
    // después de cambiar el método de pago.
    // Pregunta de propina: preferencia de cada cajero (activada por defecto).
    final pedirPropina = AjustesCobro.instancia.pedirPropina(_usuarioId);
    double propina = pedirPropina ? _propina : 0;
    _propinaCtrl.text = propina > 0 ? propina.toStringAsFixed(2) : '';

    // Calculadora de vuelto: preferencia de cada cajero, solo en efectivo.
    // En un pago dividido aplica a la parte en efectivo, si la hay.
    final calculadora = AjustesCobro.instancia.calcularVuelto(_usuarioId);
    var pedirRecibido = esEfectivo && calculadora;
    double? recibido;
    _recibidoCtrl.clear();

    // Pago dividido: arranca apagado cada vez; si el cajero no lo toca, el
    // cobro sigue exactamente el camino de un solo método.
    var dividir = false;
    final filas = <String>[]; // metodoPagoId de cada fila
    var centavosFilas = <int?>[];
    for (final c in [..._montoDivCtrls, ..._refDivCtrls]) {
      c.clear();
    }
    MetodoPagoModel? metodoDe(String id) =>
        _metodosPago.where((m) => m.metodoPagoId == id).firstOrNull;
    bool esEfectivoId(String id) =>
        (metodoDe(id)?.nombre ?? '').toUpperCase().contains('EFECTIVO');

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void fijarPropina(double v) {
            // Con el cursor al final: asignar .text a secas lo manda al inicio
            // y el siguiente dígito quedaría escrito al revés.
            final texto = v > 0 ? v.toStringAsFixed(2) : '';
            _propinaCtrl.value = TextEditingValue(
              text: texto,
              selection: TextSelection.collapsed(offset: texto.length),
            );
            setDialogState(() => propina = v);
          }

          // En centavos enteros: con doubles, 20 - 13,51 puede dar 6,4899999.
          final totalCentavos = ((consumo + propina) * 100).round();

          // Pago dividido: el cajero escribe los montos de todas las filas
          // menos la última, que se lleva lo que falta. Así la suma cuadra
          // siempre con el total y no hay "sobran" que corregir.
          var montosOk = true;
          var sumaFijas = 0;
          centavosFilas = [];
          for (var i = 0; i < filas.length - 1; i++) {
            final v = double.tryParse(_montoDivCtrls[i].text.replaceAll(',', '.'));
            final c = v == null ? null : (v * 100).round();
            if (c == null || c <= 0) montosOk = false;
            centavosFilas.add(c);
            sumaFijas += c ?? 0;
          }
          final restoCentavos = totalCentavos - sumaFijas;
          if (dividir) centavosFilas.add(restoCentavos);
          final divisionOk = !dividir || (montosOk && restoCentavos > 0);

          // Lo que el cliente paga en efectivo: contra eso se calcula el vuelto.
          int? efectivoCentavos;
          if (!dividir) {
            efectivoCentavos = esEfectivo ? totalCentavos : null;
          } else {
            for (var i = 0; i < filas.length; i++) {
              if (esEfectivoId(filas[i])) efectivoCentavos = centavosFilas[i] ?? 0;
            }
          }
          pedirRecibido = calculadora && efectivoCentavos != null;
          final aCubrirCentavos = efectivoCentavos ?? 0;

          final recibidoCentavos = recibido == null ? null : (recibido! * 100).round();
          final vueltoCentavos =
              recibidoCentavos == null ? null : recibidoCentavos - aCubrirCentavos;
          final alcanza = !pedirRecibido || (vueltoCentavos != null && vueltoCentavos >= 0);

          void fijarRecibido(double? v) {
            final texto = v == null ? '' : v.toStringAsFixed(2);
            _recibidoCtrl.value = TextEditingValue(
              text: texto,
              selection: TextSelection.collapsed(offset: texto.length),
            );
            setDialogState(() => recibido = v);
          }

          // Billetes que tiene sentido ofrecer: los que cubren el total.
          final billetes = [5, 10, 20, 50, 100]
              .where((b) => b * 100 >= aCubrirCentavos)
              .take(3)
              .toList();

          Widget chipMonto(int monto) {
            final activo = propina == monto.toDouble();
            return ChoiceChip(
              label: Text('\$$monto'),
              selected: activo,
              // Volver a tocarlo lo quita: no hace falta buscar otro botón.
              onSelected: (_) => fijarPropina(activo ? 0 : monto.toDouble()),
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13,
                color: activo ? Colors.white : AppColors.textPrimary),
            );
          }

          // Con el teclado abierto el diálogo queda con muy poco alto: se
          // compacta y el vuelto se repite junto al título, que no se desplaza,
          // para verlo mientras se escribe en cualquier tamaño de pantalla.
          final teclado = MediaQuery.viewInsetsOf(ctx).bottom > 0;
          final colorVuelto = alcanza ? AppColors.success : AppColors.error;
          final colorCaja = dividir ? AppColors.primary : color;

          const estiloMonto = TextStyle(
            fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700);

          Widget filaDivision(int i) {
            final ultima = i == filas.length - 1;
            final usados = {for (var j = 0; j < filas.length; j++) if (j != i) filas[j]};
            final opciones =
                _metodosPago.where((m) => !usados.contains(m.metodoPagoId)).toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButton<String>(
                          value: filas[i],
                          isExpanded: true,
                          isDense: true,
                          items: opciones
                              .map((m) => DropdownMenuItem(
                                    value: m.metodoPagoId,
                                    child: Text(m.nombre,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontFamily: 'Poppins', fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDialogState(() => filas[i] = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        // La última fila no se escribe: es lo que falta.
                        child: ultima
                            ? Text(
                                restoCentavos > 0
                                    ? '\$${_fmt.format(restoCentavos / 100)}'
                                    : '—',
                                textAlign: TextAlign.right,
                                style: estiloMonto.copyWith(
                                    color: restoCentavos > 0
                                        ? AppColors.textPrimary
                                        : AppColors.error))
                            : TextField(
                                controller: _montoDivCtrls[i],
                                scrollPadding: const EdgeInsets.only(bottom: 120),
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ],
                                textAlign: TextAlign.right,
                                style: estiloMonto,
                                decoration: const InputDecoration(
                                  prefixText: '\$ ',
                                  hintText: '0.00',
                                  isDense: true,
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                      ),
                      // Solo se quita la última fila agregada (la tercera):
                      // las dos primeras son la división mínima.
                      if (ultima && filas.length > 2)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Quitar',
                          onPressed: () => setDialogState(() {
                            _montoDivCtrls[i].clear();
                            _refDivCtrls[i].clear();
                            filas.removeLast();
                          }),
                        ),
                    ],
                  ),
                  if (metodoDe(filas[i])?.requiereReferencia == true)
                    TextField(
                      controller: _refDivCtrls[i],
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Referencia (opcional)',
                        isDense: true,
                      ),
                    ),
                ],
              ),
            );
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Confirmar cobro'),
                if (pedirRecibido && vueltoCentavos != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorVuelto.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colorVuelto.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '${alcanza ? 'Vuelto' : 'Faltan'} \$${_fmt.format(vueltoCentavos.abs() / 100)}',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 14, color: colorVuelto)),
                  ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!teclado) ...[
                    Text(
                      dividir
                          ? '¿Estás seguro de cómo se divide el pago?'
                          : '¿Estás seguro del método de pago seleccionado?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: teclado ? 8 : 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: colorCaja.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colorCaja.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        if (!teclado) ...[
                          Icon(dividir ? Icons.call_split : icono, color: colorCaja, size: 32),
                          const SizedBox(height: 6),
                        ],
                        Text(dividir ? 'PAGO DIVIDIDO' : nombreMetodo.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 18, color: colorCaja)),
                        const SizedBox(height: 2),
                        Text('\$${_fmt.format(consumo + propina)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                            fontSize: 22, color: AppColors.textPrimary)),
                        if (propina > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Consumo \$${_fmt.format(consumo)}  +  '
                            'propina \$${_fmt.format(propina)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 11,
                              color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (pedirPropina) ...[
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('¿Hay propina?',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _propinaCtrl,
                    // Que al enfocarlo se vean también los montos rápidos.
                    scrollPadding: const EdgeInsets.only(bottom: 90),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(
                        fontFamily: 'Poppins', fontSize: 16,
                        fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                      hintText: '0.00',
                      isDense: true,
                    ),
                    onChanged: (v) => setDialogState(
                      () => propina = double.tryParse(v.replaceAll(',', '.')) ?? 0),
                  ),
                  const SizedBox(height: 8),
                  // Wrap y no Row: con el texto en "Muy grande" los montos
                  // bajan a otra línea en vez de desbordarse.
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      chipMonto(1),
                      chipMonto(2),
                      chipMonto(5),
                      if (propina > 0)
                        ChoiceChip(
                          label: const Text('Quitar'),
                          selected: false,
                          onSelected: (_) => fijarPropina(0),
                          labelStyle: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                            fontSize: 13, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                  ],
                  if (dividir) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('¿Cómo paga?',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        TextButton(
                          onPressed: () => setDialogState(() {
                            dividir = false;
                            filas.clear();
                            for (final c in [..._montoDivCtrls, ..._refDivCtrls]) {
                              c.clear();
                            }
                          }),
                          child: const Text('No dividir'),
                        ),
                      ],
                    ),
                    if (!teclado)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Escribe cuánto paga con cada método; el último se completa solo.',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: AppColors.textSecondary),
                        ),
                      ),
                    for (var i = 0; i < filas.length; i++) filaDivision(i),
                    if (montosOk && restoCentavos <= 0)
                      Text(
                        'Los montos superan el total de \$${_fmt.format(totalCentavos / 100)}',
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 12, color: AppColors.error),
                      ),
                    if (filas.length < _maxFilasDivision && filas.length < _metodosPago.length)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar otro método'),
                          onPressed: () => setDialogState(() => filas.add(_metodosPago
                              .firstWhere((m) => !filas.contains(m.metodoPagoId))
                              .metodoPagoId)),
                        ),
                      ),
                  ] else if (_metodosPago.length >= 2) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.call_split, size: 18),
                        label: const Text('Dividir pago entre varios métodos'),
                        onPressed: () => setDialogState(() {
                          dividir = true;
                          final primero = metodo?.metodoPagoId ?? _metodosPago.first.metodoPagoId;
                          filas
                            ..clear()
                            ..add(primero)
                            ..add(_metodosPago
                                .firstWhere((m) => m.metodoPagoId != primero)
                                .metodoPagoId);
                        }),
                      ),
                    ),
                  ],
                  if (pedirRecibido) ...[
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(dividir ? '¿Con cuánto paga el efectivo?' : '¿Con cuánto paga?',
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _recibidoCtrl,
                      // Al enfocarlo el diálogo se desplaza hasta dejar
                      // visible el cuadro del vuelto, que va justo debajo.
                      scrollPadding: const EdgeInsets.only(bottom: 130),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        prefixText: '\$ ',
                        prefixStyle: TextStyle(
                          fontFamily: 'Poppins', fontSize: 16,
                          fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                        hintText: 'Efectivo recibido',
                        isDense: true,
                      ),
                      onChanged: (v) => setDialogState(
                        () => recibido = v.trim().isEmpty
                            ? null
                            : double.tryParse(v.replaceAll(',', '.'))),
                    ),
                    if (vueltoCentavos != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: (alcanza ? AppColors.success : AppColors.error).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (alcanza ? AppColors.success : AppColors.error).withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            Text(alcanza ? 'VUELTO' : 'FALTAN',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13,
                                color: alcanza ? AppColors.success : AppColors.error)),
                            Text('\$${_fmt.format(vueltoCentavos.abs() / 100)}',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 28,
                                color: alcanza ? AppColors.success : AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('Exacto'),
                          selected: vueltoCentavos == 0,
                          onSelected: (_) => fijarRecibido(aCubrirCentavos / 100),
                          selectedColor: AppColors.success,
                          labelStyle: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13,
                            color: vueltoCentavos == 0 ? Colors.white : AppColors.textPrimary),
                        ),
                        ...billetes.map((b) {
                          final activo = recibidoCentavos == b * 100;
                          return ChoiceChip(
                            label: Text('\$$b'),
                            selected: activo,
                            onSelected: (_) => fijarRecibido(b.toDouble()),
                            selectedColor: AppColors.success,
                            labelStyle: TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13,
                              color: activo ? Colors.white : AppColors.textPrimary),
                          );
                        }),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cambiar método'),
              ),
              ElevatedButton(
                // Con la calculadora activa no se cobra si lo recibido no
                // cubre el total (se registra el cobro completo).
                // En un pago dividido, tampoco mientras los montos no cuadren.
                onPressed: !alcanza || !divisionOk ? null : () async {
                  // Atajo al dedazo: $100 en vez de $10 en una mesa de $25.
                  if (propina > consumo) {
                    final seguro = await showDialog<bool>(
                      context: ctx,
                      builder: (c2) => AlertDialog(
                        title: const Text('Revisa la propina'),
                        content: Text(
                          'La propina (\$${_fmt.format(propina)}) es mayor que el '
                          'consumo (\$${_fmt.format(consumo)}). ¿Es correcto?',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c2, false),
                            child: const Text('Corregir'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(c2, true),
                            child: const Text('Sí, es correcta'),
                          ),
                        ],
                      ),
                    );
                    if (seguro != true) return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Sí, cobrar'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmado == true) {
      _propina = propina > 0 ? propina : 0;
      _recibido = pedirRecibido ? recibido : null;
      _pagosDivididos = dividir
          ? [
              for (var i = 0; i < filas.length; i++)
                (
                  metodoPagoId: filas[i],
                  centavos: i < filas.length - 1 ? centavosFilas[i] : null,
                  referencia: metodoDe(filas[i])?.requiereReferencia == true &&
                          _refDivCtrls[i].text.trim().isNotEmpty
                      ? _refDivCtrls[i].text.trim()
                      : null,
                ),
            ]
          : null;
    }
    return confirmado;
  }

  Future<bool?> _confirmarSinCobro() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cuenta en \$0',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
            'Todo lo que se cobra en esta cuenta es cortesía. Se emite una nota de venta '
            'de \$0 sin registrar pago.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
  }

  /// Dar o quitar la cortesía de una línea. Después se recarga la orden,
  /// porque la línea puede haberse partido (1 de 3 cervezas).
  Future<void> _accionCortesia(DetalleOrdenModel d) async {
    try {
      if (d.cortesia) {
        if (!d.cortesiaEditable) return;
        final quitar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Quitar cortesía',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
            content: Text(
                '${d.nombrePlato} vuelve a cobrarse (\$${_fmt.format(d.precioUnitario * d.cantidad)}).'
                '${d.motivoCortesia != null ? '\n\nMotivo de la cortesía: ${d.motivoCortesia}' : ''}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
            ],
          ),
        );
        if (quitar != true) return;
        await _factRepo.quitarCortesia(d.ordenDetalleId);
      } else {
        final r = await showDialog<CortesiaElegida>(
          context: context,
          builder: (_) => CortesiaDialog(
            titulo: 'Cortesía: ${d.nombrePlato}',
            detalle: 'El plato queda en la cuenta en \$0. Se descuenta del inventario igual, '
                'porque sí se consume.',
            maxUnidades: d.cantidadPendiente,
          ),
        );
        if (r == null) return;
        await _factRepo.darCortesia(d.ordenDetalleId, cantidad: r.cantidad, motivo: r.motivo);
      }
      if (mounted) await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Mesa completa gratis: solo el administrador. Nota de venta de $0, sin
  /// pago ni SRI; la mesa queda libre.
  Future<void> _regalarMesa() async {
    final orden = _orden;
    final apertura = _aperturaCierreCajaId;
    if (orden == null || apertura == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay caja abierta. Abre la caja antes de cerrar la mesa.'),
          backgroundColor: AppColors.warning));
      return;
    }
    final r = await showDialog<CortesiaElegida>(
      context: context,
      builder: (_) => const CortesiaDialog(
        titulo: 'Regalar toda la mesa',
        detalle: 'Todo lo pendiente pasa a cortesía y se emite una nota de venta de \$0. '
            'No se registra pago ni se envía al SRI, y la mesa queda libre.',
        mesaCompleta: true,
      ),
    );
    if (r == null || !mounted) return;
    setState(() => _emitiendo = true);
    try {
      final items = orden.detallesNoFacturados
          .map((d) => ReciboItem(
                nombre: d.nombrePlato,
                cantidad: d.cantidadPendiente,
                subtotal: d.precioUnitario * d.cantidadPendiente,
                cortesia: true,
              ))
          .toList();
      final factura = await _factRepo.cortesiaMesa(
          ordenId: orden.ordenId, aperturaCierreCajaId: apertura, motivo: r.motivo);
      if (mounted) {
        await _mostrarComprobante(factura, items);
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
    final dividido = factura.pagos.length > 1;
    final metodoPago = dividido
        ? factura.pagos.map((p) => p.nombreMetodoPago).join(' + ')
        : _metodoPagoSeleccionado?.nombre ?? '';
    // En un pago dividido el vuelto sale de la parte en efectivo, con el
    // monto que registró el servidor (no el calculado en el diálogo).
    final efectivo = dividido
        ? factura.pagos
            .where((p) => p.nombreMetodoPago.toUpperCase().contains('EFECTIVO'))
            .fold<double>(0, (s, p) => s + p.monto)
        : null;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ComprobanteDialog(
        factura: factura,
        items: items,
        metodoPago: factura.total == 0 ? 'Cortesía (sin cobro)' : metodoPago,
        // El comprobante real manda: una cuenta en $0 siempre sale como nota.
        esFactura: factura.tipoComprobante == 'FACTURA',
        sucursalId: _sucursalId,
        recibido: factura.total > 0 ? _recibido : null,
        montoEfectivo: efectivo,
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
                          if (d.cortesia) const _EtiquetaCortesia(),
                          Text(
                            d.cortesia
                                ? '${d.motivoCortesia ?? ''}${d.cortesiaPor != null ? ' · ${d.cortesiaPor}' : ''}'
                                : '\$${_fmt.format(d.precioUnitario)} c/u · $pendiente pendiente${d.cantidadFacturada > 0 ? ' (${d.cantidadFacturada} ya cobradas)' : ''}',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    // Regalar / quitar la cortesía de la línea
                    IconButton(
                      tooltip: d.cortesia ? 'Quitar cortesía' : 'Dar cortesía',
                      visualDensity: VisualDensity.compact,
                      onPressed: _emitiendo || (d.cortesia && !d.cortesiaEditable)
                          ? null
                          : () => _accionCortesia(d),
                      icon: Icon(
                        d.cortesia ? Icons.card_giftcard_rounded : Icons.card_giftcard_outlined,
                        size: 20,
                        color: d.cortesia ? AppColors.success : AppColors.textHint),
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
                      child: Text('\$${_fmt.format(d.cortesia ? 0 : d.precioUnitario * elegida)}',
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
                label: const Text('Nota de venta'),
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
        const SizedBox(height: 6),
        Text(
          _esFactura
              ? 'Se emitirá factura electrónica al SRI con los datos del cliente.'
              : 'Comprobante interno del local; no se envía al SRI. '
                'Elige Factura solo si el cliente la pide.',
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
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
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _buscarCliente(),
                decoration: const InputDecoration(
                    labelText: 'Nombre o cédula / RUC',
                    prefixIcon: Icon(Icons.person_search_outlined)),
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

  static String _pct(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Widget _buildResumen() {
    final d = _desglose;
    // Con tarifas mixtas se muestran las dos bases por separado, como en el
    // ticket: el cliente tiene que poder ver qué parte pagó IVA.
    final tarifas = d.basePorTarifa.keys.toList()..sort();
    final mixta = tarifas.length > 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _ResumenRow(label: 'Subtotal', value: '\$${_fmt.format(d.subtotal)}'),
          if (mixta)
            ...tarifas.map((t) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ResumenRow(
                    label: 'Subtotal ${_pct(t)}%',
                    value: '\$${_fmt.format(d.basePorTarifa[t]!)}',
                  ),
                )),
          const SizedBox(height: 6),
          _ResumenRow(
            label: mixta ? 'IVA' : 'IVA (${_pct(tarifas.isEmpty ? _ivaPorcentaje : tarifas.first)}%)',
            value: '\$${_fmt.format(d.iva)}',
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: AppColors.divider)),
          _ResumenRow(label: 'TOTAL', value: '\$${_fmt.format(d.total)}', isBold: true, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildEmitirBtn() {
    return Column(
      children: [
        _botonCobrar(),
        if (_esAdmin && (_orden?.detallesNoFacturados.isNotEmpty ?? false)) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
              onPressed: _emitiendo ? null : _regalarMesa,
              icon: const Icon(Icons.card_giftcard_rounded),
              label: const Text('Regalar toda la mesa'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _botonCobrar() {
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
            : _haySeleccion && _desglose.total == 0
                ? 'Registrar cortesía (\$0)'
                : _esFactura ? 'Cobrar y emitir factura' : 'Cobrar (nota de venta)'),
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
  /// Efectivo que entregó el cliente (calculadora de vuelto); null si no se usó.
  final double? recibido;
  /// Parte en efectivo de un pago dividido: el vuelto se calcula sobre ella y
  /// no sobre el total. null = un solo método.
  final double? montoEfectivo;

  const _ComprobanteDialog({
    required this.factura,
    required this.items,
    required this.metodoPago,
    required this.esFactura,
    required this.sucursalId,
    this.recibido,
    this.montoEfectivo,
  });

  @override
  State<_ComprobanteDialog> createState() => _ComprobanteDialogState();
}

class _ComprobanteDialogState extends State<_ComprobanteDialog> {
  final _configRepo = ConfiguracionRepository();
  final _factRepo = FacturacionRepository();
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
          Text(widget.esFactura ? 'Factura emitida' : 'Nota de venta emitida',
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
                Text('${widget.esFactura ? 'FACTURA' : 'NOTA DE VENTA'} No. ${f.numeroFactura}',
                    style: _ticketBold),
                Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(f.fecha.toLocal())}', style: _ticketStyle),
                Text('Orden: #${f.numeroOrden}', style: _ticketStyle),
                Text('Cliente: ${f.nombreCliente ?? 'Consumidor Final'}', style: _ticketStyle),
                if (f.cedulaRucCliente?.isNotEmpty ?? false)
                  Text('CI/RUC: ${f.cedulaRucCliente}', style: _ticketStyle),
                const Divider(),
                ...widget.items.map((it) => _filaTicket(
                    '${it.cantidad} x ${it.nombre}${it.cortesia ? ' (cortesía)' : ''}', it.subtotal)),
                const Divider(),
                _filaTicket('Subtotal', f.subtotal),
                if (f.descuento > 0)
                  _filaTicket(widget.items.any((it) => it.cortesia) ? 'Cortesía' : 'Descuento', -f.descuento),
                if (f.tieneTarifasMixtas) ...[
                  _filaTicket('Subtotal 0%', f.subtotalSinIva!),
                  _filaTicket('Subtotal ${f.ivaPorcentaje.toStringAsFixed(0)}%',
                      f.subtotalGravado!),
                ],
                _filaTicket('IVA ${f.ivaPorcentaje.toStringAsFixed(0)}%', f.iva),
                if (f.propina > 0) _filaTicket('Propina', f.propina),
                _filaTicket('TOTAL', f.total, bold: true),
                if (f.pagos.length > 1)
                  for (final p in f.pagos) _filaTicket(p.nombreMetodoPago, p.monto)
                else
                  Text('Pago: ${widget.metodoPago}', style: _ticketStyle),
                if (widget.recibido != null) ...[
                  _filaTicket('Recibido', widget.recibido!),
                  _filaTicket('Vuelto',
                      ((widget.recibido! * 100).round() -
                              ((widget.montoEfectivo ?? f.total) * 100).round()) /
                          100,
                      bold: true),
                ],
                if (f.cortesia && f.motivoCortesia != null)
                  Text('CORTESÍA: ${f.motivoCortesia}', style: _ticketBold),
                // Solo la factura viaja al SRI: en la nota de venta no hay
                // nada que consultar.
                if (widget.esFactura)
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
      // Si la emisión SRI aún no se refleja (corre en segundo plano tras el
      // cobro), refrescar antes de imprimir para que el ticket lleve la
      // clave de acceso. Si falla, se imprime igual como comprobante.
      // En la nota de venta no aplica: no se envía al SRI.
      if (widget.esFactura && !_factura.tieneSri) {
        try {
          final f = await _factRepo.getFactura(_factura.facturaVentaId);
          if (f.tieneSri && mounted) setState(() => _factura = f);
        } catch (_) {}
      }
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
        recibido: widget.recibido,
        montoEfectivo: widget.montoEfectivo,
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

/// Botón compacto de +/- para elegir cantidades en cuentas divididas.
class _EtiquetaCortesia extends StatelessWidget {
  const _EtiquetaCortesia();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: const Text('CORTESÍA',
          style: TextStyle(
              fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700,
              color: AppColors.success)),
    );
  }
}

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

/// Lo que se va a cobrar, ya separado por tarifa de IVA.
///
/// [basePorTarifa] va de porcentaje a base imponible: `{0.0: 42.50, 15.0: 3.00}`
/// es una mesa de almuerzos al 0% con una cerveza gravada.
class _DesgloseCobro {
  final double subtotal;
  final double iva;
  final Map<double, double> basePorTarifa;

  const _DesgloseCobro(this.subtotal, this.iva, this.basePorTarifa);

  double get total => subtotal + iva;
}
