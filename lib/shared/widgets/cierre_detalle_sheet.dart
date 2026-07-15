import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/caja_model.dart';
import '../../core/models/config_models.dart';
import '../../core/network/api_client.dart';
import '../../core/printing/comanda_printer.dart';
import '../../features/configuracion/data/configuracion_repository.dart';

/// Hoja inferior con el detalle completo de un turno de caja (abierto o
/// cerrado): arqueo, ventas por método de pago, cada ingreso y egreso,
/// y ventas por plato. Con [sucursalId] se habilita el botón de imprimir
/// (usa las impresoras térmicas configuradas en la sucursal).
Future<void> mostrarCierreDetalle(
  BuildContext context,
  CierreDetalladoModel cierre, {
  String? sucursalId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _CierreDetalleBody(
          cierre: cierre,
          scrollController: scrollCtrl,
          sucursalId: sucursalId,
        ),
      ),
    ),
  );
}

class _CierreDetalleBody extends StatefulWidget {
  final CierreDetalladoModel cierre;
  final ScrollController scrollController;
  final String? sucursalId;
  const _CierreDetalleBody({
    required this.cierre,
    required this.scrollController,
    this.sucursalId,
  });

  @override
  State<_CierreDetalleBody> createState() => _CierreDetalleBodyState();
}

class _CierreDetalleBodyState extends State<_CierreDetalleBody> {
  static final _fmt = NumberFormat('#,##0.00', 'es');
  bool _imprimiendo = false;

  CierreDetalladoModel get cierre => widget.cierre;
  ScrollController get scrollController => widget.scrollController;

  /// Lista las impresoras de la sucursal, deja elegir una e imprime el
  /// ticket de cierre completo (mismo flujo que la reimpresión de recibos).
  Future<void> _imprimir() async {
    final sucursalId = widget.sucursalId;
    if (sucursalId == null || _imprimiendo) return;
    setState(() => _imprimiendo = true);
    try {
      final impresoras = (await ConfiguracionRepository().getImpresoras(sucursalId))
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
          title: const Text('Imprimir en',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          children: impresoras.map((i) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, i),
            child: Text('${i.nombre}${i.area?.isNotEmpty == true ? ' (${i.area})' : ''}',
                style: const TextStyle(fontFamily: 'Poppins')),
          )).toList(),
        ),
      );
      if (elegida == null) return;

      await ComandaPrinter.imprimirCierreCaja(
        ip: elegida.ip!,
        puerto: elegida.puerto ?? 9100,
        cierre: cierre,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cierre de caja impreso'), backgroundColor: AppColors.success,
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

  @override
  Widget build(BuildContext context) {
    final c = cierre;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildHeader(c),
        if (widget.sucursalId != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _imprimiendo ? null : _imprimir,
              icon: _imprimiendo
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined, size: 20),
              label: Text(_imprimiendo ? 'Imprimiendo...' : 'Imprimir cierre',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildArqueo(c),
        const SizedBox(height: 16),
        if (c.ventasPorMetodo.isNotEmpty) ...[
          _buildVentasPorMetodo(c),
          const SizedBox(height: 16),
        ],
        _buildMovimientos(
          titulo: 'Ingresos extra',
          items: c.ingresos,
          total: c.totalIngresos,
          esIngreso: true,
          vacio: 'No se registraron ingresos extra en este turno',
        ),
        const SizedBox(height: 16),
        _buildMovimientos(
          titulo: 'Egresos (gastos)',
          items: c.egresos,
          total: c.totalEgresos,
          esIngreso: false,
          vacio: 'No se registraron egresos en este turno',
        ),
        if (c.ventasPorPlato.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildVentasPorPlato(c),
        ],
        if ((c.observaciones ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildObservaciones(c.observaciones!),
        ],
      ],
    );
  }

  Widget _buildHeader(CierreDetalladoModel c) {
    final fechaFmt = DateFormat('dd/MM/yyyy HH:mm', 'es');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Detalle de caja · ${c.nombreCaja}',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (c.isCerrada ? AppColors.textSecondary : AppColors.success).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                c.isCerrada ? 'CERRADA' : 'ABIERTA',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 11,
                  color: c.isCerrada ? AppColors.textSecondary : AppColors.success),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Apertura: ${fechaFmt.format(c.fechaApertura.toLocal())} · ${c.usuarioApertura}',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
        if (c.fechaCierre != null)
          Text('Cierre: ${fechaFmt.format(c.fechaCierre!.toLocal())} · ${c.usuarioCierre ?? ''}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildArqueo(CierreDetalladoModel c) {
    final otrosMetodos = c.totalVentas - c.totalVentasEfectivo;
    final diferencia = c.diferencia;
    return _Card(
      titulo: 'Arqueo de caja',
      trailing: '${c.totalFacturas} facturas',
      child: Column(
        children: [
          _Fila('Monto inicial', c.montoInicial, fmt: _fmt),
          _Fila('Ventas en efectivo', c.totalVentasEfectivo, fmt: _fmt, signo: '+'),
          _Fila('Otros ingresos', c.totalIngresos, fmt: _fmt, signo: '+'),
          _Fila('Egresos', c.totalEgresos, fmt: _fmt, signo: '-'),
          const Divider(height: 16),
          _Fila('Debe haber en caja (efectivo)', c.montoEsperado, fmt: _fmt, bold: true),
          if (c.montoContado != null)
            _Fila('Efectivo contado', c.montoContado!, fmt: _fmt, bold: true),
          if (diferencia != null) ...[
            const Divider(height: 16),
            _Fila(
              diferencia.abs() < 0.01
                  ? 'Caja cuadrada'
                  : diferencia > 0 ? 'Sobrante' : 'Faltante',
              diferencia,
              fmt: _fmt,
              bold: true,
              color: diferencia.abs() < 0.01
                  ? AppColors.success
                  : diferencia > 0 ? AppColors.warning : AppColors.error,
            ),
          ],
          const Divider(height: 16),
          _Fila('Ventas totales (todos los métodos)', c.totalVentas, fmt: _fmt),
          if (otrosMetodos > 0.009)
            _Fila('Cobrado por otros métodos de pago', otrosMetodos, fmt: _fmt),
        ],
      ),
    );
  }

  Widget _buildVentasPorMetodo(CierreDetalladoModel c) {
    return _Card(
      titulo: 'Ventas por método de pago',
      child: Column(
        children: [
          ...c.ventasPorMetodo.map((m) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  m.metodo.toUpperCase() == 'EFECTIVO'
                      ? Icons.payments_outlined
                      : m.metodo.toUpperCase().contains('TARJETA')
                          ? Icons.credit_card_outlined
                          : Icons.account_balance_outlined,
                  size: 18, color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m.metodo,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Text('${m.numPagos} ${m.numPagos == 1 ? 'pago' : 'pagos'}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(width: 12),
                Text('\$${_fmt.format(m.total)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
          )),
          const Divider(height: 16),
          _Fila('Total cobrado', c.ventasPorMetodo.fold(0.0, (s, m) => s + m.total), fmt: _fmt, bold: true),
        ],
      ),
    );
  }

  Widget _buildMovimientos({
    required String titulo,
    required List<MovimientoItemModel> items,
    required double total,
    required bool esIngreso,
    required String vacio,
  }) {
    final color = esIngreso ? AppColors.success : AppColors.error;
    return _Card(
      titulo: '$titulo (${items.length})',
      trailing: '${esIngreso ? '+' : '-'}\$${_fmt.format(total)}',
      trailingColor: color,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(vacio,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            )
          : Column(
              children: items.map((m) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        esIngreso ? Icons.add_circle_outline : Icons.remove_circle_outline,
                        color: color, size: 15),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.concepto.isEmpty ? 'Sin concepto' : m.concepto,
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('${m.usuario} · ${DateFormat('HH:mm', 'es').format(m.fecha.toLocal())}',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text('${esIngreso ? '+' : '-'}\$${_fmt.format(m.monto)}',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: color)),
                  ],
                ),
              )).toList(),
            ),
    );
  }

  Widget _buildVentasPorPlato(CierreDetalladoModel c) {
    final totalPlatos = c.ventasPorPlato.fold(0, (s, v) => s + v.cantidad);
    return _Card(
      titulo: 'Ventas por plato',
      trailing: '$totalPlatos platos',
      child: Column(
        children: c.ventasPorPlato.map((v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 28, height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${v.cantidad}',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    fontSize: 12, color: AppColors.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.plato,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Text('\$${_fmt.format(v.total)}',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildObservaciones(String obs) {
    return _Card(
      titulo: 'Observaciones',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(obs,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary)),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String titulo;
  final String? trailing;
  final Color? trailingColor;
  final Widget child;
  const _Card({required this.titulo, this.trailing, this.trailingColor, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(titulo,
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
              if (trailing != null)
                Text(trailing!,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12,
                    color: trailingColor ?? AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final double valor;
  final NumberFormat fmt;
  final String signo;
  final bool bold;
  final Color? color;
  const _Fila(this.label, this.valor, {required this.fmt, this.signo = '', this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Poppins',
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: bold ? 14 : 13,
      color: color ?? (bold ? AppColors.textPrimary : AppColors.textSecondary),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: style)),
          Text('$signo\$${fmt.format(valor.abs())}', style: style),
        ],
      ),
    );
  }
}
