import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/models/factura_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/comanda_printer.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../features/caja/data/caja_repository.dart';
import '../../../features/configuracion/data/configuracion_repository.dart';
import '../../../features/facturacion/data/facturacion_repository.dart';
import '../../../shared/widgets/cliente_busqueda.dart';
import '../../../shared/widgets/cliente_form_dialog.dart';
import '../data/adelantos_repository.dart';

final _fmt = NumberFormat('#,##0.00', 'es');
final _fmtFecha = DateFormat('dd/MM/yyyy', 'es');

/// Adelantos de reservas: el cajero los registra cuando el cliente paga por
/// adelantado y los descuenta al cobrar. Solo existe para los restaurantes
/// que tienen el módulo activado.
class AdelantosScreen extends StatefulWidget {
  final String sucursalId;
  const AdelantosScreen({super.key, required this.sucursalId});

  @override
  State<AdelantosScreen> createState() => _AdelantosScreenState();
}

class _AdelantosScreenState extends State<AdelantosScreen> {
  final _repo = AdelantosRepository();
  String _estado = 'PENDIENTE';
  List<AdelantoModel> _adelantos = [];
  bool _cargando = true;
  String? _error;

  UserModel? get _user {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user : null;
  }

  bool get _esAdmin =>
      _user?.rol == UserRole.admin || _user?.rol == UserRole.superadmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final lista = await _repo.listarOFallar(widget.sucursalId, estado: _estado);
      if (mounted) setState(() { _adelantos = lista.adelantos; _cargando = false; });
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.parseError(e); _cargando = false; });
    }
  }

  Future<void> _nuevo() async {
    final creado = await Navigator.of(context).push<AdelantoModel>(MaterialPageRoute(
      builder: (_) => NuevoAdelantoScreen(sucursalId: widget.sucursalId),
    ));
    if (creado == null || !mounted) return;
    if (_estado != 'PENDIENTE') setState(() => _estado = 'PENDIENTE');
    await _cargar();
  }

  Future<void> _acciones(AdelantoModel a) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(a.nombreCliente,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              subtitle: Text('\$${_fmt.format(a.disponible)} · ${a.nombreMetodoPago}',
                  style: const TextStyle(fontFamily: 'Poppins')),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Reimprimir recibo'),
              onTap: () => Navigator.pop(ctx, 'imprimir'),
            ),
            if (a.pendiente)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Cambiar fecha de la reserva'),
                subtitle: const Text('Si cancela, el adelanto queda para otro día'),
                onTap: () => Navigator.pop(ctx, 'fecha'),
              ),
            if (a.pendiente && _esAdmin)
              ListTile(
                leading: const Icon(Icons.block, color: AppColors.error),
                title: const Text('Anular (registro equivocado)',
                    style: TextStyle(color: AppColors.error)),
                subtitle: const Text('Solo mientras la caja del día siga abierta'),
                onTap: () => Navigator.pop(ctx, 'anular'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || accion == null) return;
    switch (accion) {
      case 'imprimir':
        await imprimirReciboAdelanto(context, widget.sucursalId, a);
      case 'fecha':
        await _cambiarFecha(a);
      case 'anular':
        await _anular(a);
    }
  }

  Future<void> _cambiarFecha(AdelantoModel a) async {
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: a.fechaPrevista != null && !a.fechaPrevista!.isBefore(hoy) ? a.fechaPrevista! : hoy,
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 2),
      helpText: 'Nueva fecha de la reserva',
    );
    if (fecha == null || !mounted) return;
    try {
      await _repo.cambiarFecha(a.adelantoId, fecha);
      await _cargar();
    } catch (e) {
      _aviso(ApiClient.parseError(e), AppColors.error);
    }
  }

  Future<void> _anular(AdelantoModel a) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => const _MotivoAnulacionDialog(),
    );
    if (motivo == null || !mounted) return;
    try {
      await _repo.anular(a.adelantoId, motivo);
      _aviso('Adelanto anulado', AppColors.success);
      await _cargar();
    } catch (e) {
      _aviso(ApiClient.parseError(e), AppColors.error);
    }
  }

  void _aviso(String texto, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final total = _adelantos.fold<double>(0, (s, a) => s + a.disponible);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Adelantos de reservas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo adelanto'),
      ),
      body: SafeArea(
        child: Center(
          // En tablet la lista no se estira a todo el ancho.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (valor, texto) in const [
                        ('PENDIENTE', 'Pendientes'),
                        ('APLICADO', 'Usados'),
                        ('ANULADO', 'Anulados'),
                      ])
                        ChoiceChip(
                          label: Text(texto),
                          selected: _estado == valor,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13,
                            color: _estado == valor ? Colors.white : AppColors.textPrimary),
                          onSelected: (_) {
                            setState(() => _estado = valor);
                            _cargar();
                          },
                        ),
                    ],
                  ),
                ),
                if (_estado == 'PENDIENTE' && !_cargando && _adelantos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      '${_adelantos.length} pendiente${_adelantos.length == 1 ? '' : 's'} · '
                      '\$${_fmt.format(total)} recibidos por consumir',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                Expanded(child: _buildLista()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLista() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_adelantos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Text(
                _estado == 'PENDIENTE' ? 'No hay adelantos pendientes' : 'No hay adelantos',
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _adelantos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _AdelantoCard(adelanto: _adelantos[i], onTap: () => _acciones(_adelantos[i])),
      ),
    );
  }
}

class _AdelantoCard extends StatelessWidget {
  final AdelantoModel adelanto;
  final VoidCallback onTap;
  const _AdelantoCard({required this.adelanto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = adelanto;
    final fechaPrevista = a.fechaPrevista;
    final hoy = DateUtils.dateOnly(DateTime.now());
    final vencida = a.pendiente && fechaPrevista != null && fechaPrevista.isBefore(hoy);
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.nombreCliente,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(
                      [
                        if (fechaPrevista != null) 'Reserva: ${_fmtFecha.format(fechaPrevista)}',
                        a.nombreMetodoPago,
                        if (a.numeroFactura != null) a.numeroFactura!,
                      ].join(' · '),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        // Fecha pasada: canceló o no vino; sigue a su favor.
                        color: vencida ? AppColors.warning : AppColors.textSecondary),
                    ),
                    Text('Recibido ${_fmtFecha.format(a.fechaRegistro.toLocal())} por ${a.usuario}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
                    if (a.nota != null)
                      Text(a.nota!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('\$${_fmt.format(a.pendiente ? a.disponible : a.monto)}',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MotivoAnulacionDialog extends StatefulWidget {
  const _MotivoAnulacionDialog();

  @override
  State<_MotivoAnulacionDialog> createState() => _MotivoAnulacionDialogState();
}

class _MotivoAnulacionDialogState extends State<_MotivoAnulacionDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Anular adelanto'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Úsalo solo si el adelanto se registró mal. Si el cliente cancela la reserva, '
            'no se anula: cambia la fecha y el adelanto queda a su favor.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Motivo'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _ctrl.text.trim().isEmpty ? null : () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Anular'),
        ),
      ],
    );
  }
}

/// Formulario de un adelanto nuevo. Es una pantalla y no un diálogo: tiene
/// varios campos de texto y así sus controllers viven en su propio State.
class NuevoAdelantoScreen extends StatefulWidget {
  final String sucursalId;
  const NuevoAdelantoScreen({super.key, required this.sucursalId});

  @override
  State<NuevoAdelantoScreen> createState() => _NuevoAdelantoScreenState();
}

class _NuevoAdelantoScreenState extends State<NuevoAdelantoScreen> {
  final _repo = AdelantosRepository();
  final _factRepo = FacturacionRepository();
  final _cajaRepo = CajaRepository();
  final _buscarCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();

  /// Un solo id por formulario: si el guardado se reintenta (doble tap, red
  /// lenta) el backend devuelve el mismo adelanto en vez de duplicarlo.
  final _intento = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '-${Random().nextInt(1 << 30).toRadixString(16)}';

  List<MetodoPagoModel> _metodos = [];
  String? _metodoId;
  String? _aperturaId;
  ClienteModel? _cliente;
  DateTime? _fechaPrevista;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    _montoCtrl.dispose();
    _refCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final metodos = await _factRepo.getMetodosPago(widget.sucursalId);
      final cajas = await _cajaRepo.getCajasBySucursal(widget.sucursalId);
      final apertura = cajas.isEmpty ? null : await _cajaRepo.getAperturaActiva(cajas.first.cajaId);
      if (!mounted) return;
      setState(() {
        _metodos = metodos;
        _metodoId = metodos.isNotEmpty ? metodos.first.metodoPagoId : null;
        _aperturaId = apertura?.isAbierta == true ? apertura!.aperturaCierreCajaId : null;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.parseError(e); _cargando = false; });
    }
  }

  MetodoPagoModel? get _metodo => _metodos.where((m) => m.metodoPagoId == _metodoId).firstOrNull;

  double? get _monto {
    final v = double.tryParse(_montoCtrl.text.replaceAll(',', '.'));
    return v == null || v <= 0 ? null : v;
  }

  bool get _puedeGuardar =>
      !_guardando && _aperturaId != null && _cliente != null && _monto != null && _metodoId != null;

  Future<void> _buscarCliente() async {
    final c = await buscarClienteInteractivo(context, _factRepo, _buscarCtrl.text);
    if (c != null && mounted) setState(() => _cliente = c);
  }

  Future<void> _registrarCliente() async {
    final c = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => ClienteFormDialog(repo: _factRepo, cedulaInicial: soloCedula(_buscarCtrl.text)),
    );
    if (c != null && mounted) setState(() => _cliente = c);
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: _fechaPrevista ?? hoy,
      firstDate: DateTime(hoy.year, hoy.month, hoy.day),
      lastDate: DateTime(hoy.year + 2),
      helpText: 'Fecha de la reserva',
    );
    if (f != null && mounted) setState(() => _fechaPrevista = f);
  }

  Future<void> _guardar() async {
    if (!_puedeGuardar) return;
    final monto = _monto!;
    // Confirmación del monto y el método: un error aquí descuadra la caja.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar adelanto'),
        content: Text(
          '${_cliente!.nombre} deja \$${_fmt.format(monto)} en ${_metodo?.nombre ?? ''}.\n\n'
          'No se factura ahora: se descuenta el día que consuma.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _guardando = true);
    try {
      final a = await _repo.registrar(
        aperturaCierreCajaId: _aperturaId!,
        clienteId: _cliente!.clienteId,
        monto: monto,
        metodoPagoId: _metodoId!,
        referencia: _metodo?.requiereReferencia == true ? _refCtrl.text.trim() : null,
        fechaPrevista: _fechaPrevista,
        nota: _notaCtrl.text.trim(),
        clientRequestId: _intento,
      );
      if (!mounted) return;
      await imprimirReciboAdelanto(context, widget.sucursalId, a, preguntar: true);
      if (mounted) Navigator.pop(context, a);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Nuevo adelanto')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? Center(child: Text(_error!))
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _buildCampos(),
                      ),
                    ),
                  ),
      ),
    );
  }

  List<Widget> _buildCampos() {
    const titulo = TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15);
    return [
      if (_aperturaId == null)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'No hay caja abierta. Abre la caja para recibir el adelanto: el dinero entra a la caja de hoy.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        ),
      const Text('Cliente', style: titulo),
      const SizedBox(height: 8),
      if (_cliente != null)
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(_cliente!.nombre, overflow: TextOverflow.ellipsis),
            subtitle: Text(_cliente!.cedulaRuc),
            trailing: TextButton(
              onPressed: () => setState(() => _cliente = null),
              child: const Text('Cambiar'),
            ),
          ),
        )
      else ...[
        TextField(
          controller: _buscarCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _buscarCliente(),
          decoration: InputDecoration(
            hintText: 'Nombre o cédula',
            isDense: true,
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _buscarCliente),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _registrarCliente,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Registrar cliente nuevo'),
          ),
        ),
      ],
      const SizedBox(height: 16),
      const Text('Monto del adelanto', style: titulo),
      const SizedBox(height: 8),
      TextField(
        controller: _montoCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700),
        decoration: const InputDecoration(prefixText: '\$ ', hintText: '0.00', isDense: true),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      const Text('¿Cómo pagó?', style: titulo),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: _metodos.map((m) {
          final sel = m.metodoPagoId == _metodoId;
          return ChoiceChip(
            label: Text(m.nombre),
            selected: sel,
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13,
              color: sel ? Colors.white : AppColors.textPrimary),
            onSelected: (_) => setState(() => _metodoId = m.metodoPagoId),
          );
        }).toList(),
      ),
      if (_metodo?.requiereReferencia == true) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _refCtrl,
          decoration: const InputDecoration(
            labelText: 'Referencia / número de transacción', isDense: true),
        ),
      ],
      const SizedBox(height: 16),
      const Text('Reserva', style: titulo),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _elegirFecha,
        icon: const Icon(Icons.event_outlined, size: 18),
        label: Text(_fechaPrevista == null
            ? 'Elegir fecha (opcional)'
            : 'Para el ${_fmtFecha.format(_fechaPrevista!)}'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _notaCtrl,
        maxLength: 200,
        decoration: const InputDecoration(
          hintText: 'Nota (ej. mesa para 8, cumpleaños)', isDense: true),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _puedeGuardar ? _guardar : null,
          icon: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(_guardando ? 'Registrando...' : 'Registrar adelanto'),
        ),
      ),
    ];
  }
}

/// Imprime el recibo de un adelanto en una impresora de la sucursal. Con
/// [preguntar] primero ofrece imprimirlo (recién registrado) y se puede omitir.
Future<void> imprimirReciboAdelanto(
  BuildContext context,
  String sucursalId,
  AdelantoModel a, {
  bool preguntar = false,
}) async {
  if (preguntar) {
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adelanto registrado'),
        content: Text('${a.nombreCliente} · \$${_fmt.format(a.monto)}\n\n¿Imprimir el recibo para el cliente?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Imprimir')),
        ],
      ),
    );
    if (si != true || !context.mounted) return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final auth = context.read<AuthBloc>().state;
  final user = auth is AuthAuthenticated ? auth.user : null;
  try {
    final impresoras = (await ConfiguracionRepository().getImpresoras(sucursalId))
        .where((i) => i.activo && i.imprimible)
        .toList();
    if (!context.mounted) return;
    if (impresoras.isEmpty) {
      messenger.showSnackBar(const SnackBar(
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
    final via = await ComandaPrinter.imprimirReciboAdelanto(
      ip: elegida.ip,
      puerto: elegida.puerto ?? 9100,
      mac: elegida.mac,
      nombreSucursal: user?.sucursalNombre ?? '',
      cliente: a.nombreCliente,
      cedula: a.cedulaCliente,
      monto: a.monto,
      metodoPago: a.nombreMetodoPago,
      referencia: a.referencia,
      fechaPrevista: a.fechaPrevista,
      nota: a.nota,
      fecha: a.fechaRegistro,
      atendidoPor: a.usuario,
    );
    messenger.showSnackBar(SnackBar(
      content: Text('Recibo impreso por $via'), backgroundColor: AppColors.success));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('No se pudo imprimir: ${ApiClient.parseError(e)}'),
      backgroundColor: AppColors.error));
  }
}
