import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../core/cobro/desglose_cobro.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/config_models.dart';
import '../../core/models/orden_model.dart';
import '../../core/network/api_client.dart';
import '../../core/printing/comanda_printer.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/configuracion/data/configuracion_repository.dart';
import '../../features/facturacion/data/facturacion_repository.dart';
import '../../features/ordenes/data/ordenes_repository.dart';

/// Precuenta: cuánto lleva consumido la mesa, para que el cliente sepa cuánto
/// debe antes de pedir más. Solo informa: no cobra, no emite comprobante, no
/// cierra la mesa ni toca la caja. La pueden sacar mesero, cajero y admin.
///
/// El total sale del mismo cálculo que el cobro ([DesgloseCobro]), sobre todo
/// lo pendiente de la orden: con la cuenta dividida, lo que falta por pagar.
class PrecuentaScreen extends StatefulWidget {
  final String ordenId;
  final String sucursalId;
  const PrecuentaScreen({super.key, required this.ordenId, required this.sucursalId});

  @override
  State<PrecuentaScreen> createState() => _PrecuentaScreenState();
}

class _PrecuentaScreenState extends State<PrecuentaScreen> {
  final _fmt = NumberFormat('#,##0.00', 'es');
  OrdenModel? _orden;
  // Respaldo como en el cobro si el endpoint de IVA no responde.
  double _ivaPredeterminado = 15;
  bool _cargando = true;
  bool _imprimiendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Siempre la orden recién leída: la de la pantalla anterior puede no
  /// tener lo último que pidieron desde otro equipo.
  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final orden = await OrdenesRepository().getOrden(widget.ordenId);
      final iva = await FacturacionRepository().getIvaVigente(widget.sucursalId);
      if (!mounted) return;
      setState(() {
        _orden = orden;
        if (iva != null) _ivaPredeterminado = iva;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.parseError(e); _cargando = false; });
    }
  }

  List<DetalleOrdenModel> get _pendientes => _orden?.detallesNoFacturados ?? const [];

  DesgloseCobro get _desglose => DesgloseCobro.calcular(
      _pendientes, (d) => d.cantidadPendiente, _ivaPredeterminado);

  static String _pct(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Future<void> _imprimir() async {
    final orden = _orden;
    if (orden == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    setState(() => _imprimiendo = true);
    try {
      final impresoras = (await ConfiguracionRepository().getImpresoras(widget.sucursalId))
          .where((i) => i.activo && i.imprimible)
          .toList();
      if (!mounted) return;
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
      final d = _desglose;
      final via = await ComandaPrinter.imprimirPrecuenta(
        ip: elegida.ip,
        puerto: elegida.puerto ?? 9100,
        mac: elegida.mac,
        nombreSucursal: user?.sucursalNombre ?? '',
        lugar: orden.lugar,
        numeroOrden: orden.numeroOrden,
        lineas: [
          for (final p in _pendientes)
            (
              cantidad: p.cantidadPendiente,
              plato: p.nombrePlato,
              subtotal: p.precioUnitario * p.cantidadPendiente,
              cortesia: p.cortesia,
            ),
        ],
        basePorTarifa: d.basePorTarifa,
        iva: d.iva,
        total: d.total,
        atendidoPor: user?.nombre ?? '',
      );
      messenger.showSnackBar(SnackBar(
        content: Text('Precuenta impresa por $via'), backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('No se pudo imprimir: ${ApiClient.parseError(e)}'),
        backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Precuenta'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? Center(
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
                  )
                : _buildContenido(),
      ),
    );
  }

  Widget _buildContenido() {
    final orden = _orden!;
    final d = _desglose;
    final tarifas = d.basePorTarifa.keys.toList()..sort();
    final tarifaIva = tarifas.where((t) => t > 0).fold(0.0, (m, t) => t > m ? t : m);
    const normal = TextStyle(fontFamily: 'Poppins', fontSize: 13);
    const secundario = TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary);

    Widget fila(String label, double valor, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: bold ? normal.copyWith(fontWeight: FontWeight.w700) : normal)),
              Text('\$${_fmt.format(valor)}',
                  style: bold ? normal.copyWith(fontWeight: FontWeight.w700) : normal),
            ],
          ),
        );

    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Solo informa cuánto lleva la cuenta. No cobra ni emite comprobante: '
                      'el cliente puede seguir pidiendo.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${orden.lugar} · Orden #${orden.numeroOrden}',
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
                        const Divider(height: 20),
                        if (_pendientes.isEmpty)
                          const Text('No hay nada pendiente de pago en esta orden.', style: secundario)
                        else
                          for (final p in _pendientes)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 34,
                                    child: Text('${p.cantidadPendiente}x',
                                      style: normal.copyWith(fontWeight: FontWeight.w700)),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.nombrePlato, style: normal),
                                        if (p.cortesia)
                                          const Text('CORTESÍA',
                                            style: TextStyle(
                                              fontFamily: 'Poppins', fontSize: 11,
                                              fontWeight: FontWeight.w700, color: AppColors.success)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\$${_fmt.format(p.cortesia ? 0 : p.precioUnitario * p.cantidadPendiente)}',
                                    style: normal),
                                ],
                              ),
                            ),
                        const Divider(height: 20),
                        if (tarifas.length > 1)
                          for (final t in tarifas) fila('Subtotal ${_pct(t)}%', d.basePorTarifa[t]!)
                        else
                          fila('Subtotal', d.subtotal),
                        if (d.iva > 0) fila('IVA ${_pct(tarifaIva)}%', d.iva),
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('TOTAL',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
                            ),
                            Text('\$${_fmt.format(d.total)}',
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                fontSize: 26, color: AppColors.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _imprimiendo || _pendientes.isEmpty ? null : _imprimir,
                icon: _imprimiendo
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: Text(_imprimiendo ? 'Imprimiendo...' : 'Imprimir precuenta'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
