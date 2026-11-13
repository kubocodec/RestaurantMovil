import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/settings/ajustes_texto.dart';
import '../../reportes/data/resumen_periodo_model.dart';

/// Ventas de un día para el gráfico de la semana.
typedef VentaDia = ({DateTime dia, double ventas});

/// Panel del administrador en la web de escritorio (maqueta del 2026-11-12):
/// indicadores, la semana en barras, órdenes en curso, alertas y lo más
/// vendido de hoy. Solo dibuja: los datos los carga el panel de siempre
/// (admin_dashboard.dart), que en el celular sigue mostrando su versión.
class PanelAdminEscritorio extends StatelessWidget {
  final bool cargando;
  final double ventasHoy;
  final int facturasHoy;
  final int mesasOcupadas;
  final int mesasTotal;
  final List<OrdenModel> ordenes;
  /// Los 6 días anteriores a hoy, del más viejo al más nuevo. Vacío mientras carga.
  final List<VentaDia> semanaPrevia;
  /// null = todavía no se sabe; vacío = hoy no se vendió nada.
  final List<PlatoVentaModel>? masVendidos;
  /// Aviso de inventario ya armado (o un SizedBox vacío).
  final Widget avisoInventario;
  final Widget avisoPago;
  final ValueChanged<OrdenModel> onAbrirOrden;
  final VoidCallback onVerMesas;
  final VoidCallback onVerReportes;

  const PanelAdminEscritorio({
    super.key,
    required this.cargando,
    required this.ventasHoy,
    required this.facturasHoy,
    required this.mesasOcupadas,
    required this.mesasTotal,
    required this.ordenes,
    required this.semanaPrevia,
    required this.masVendidos,
    required this.avisoInventario,
    required this.avisoPago,
    required this.onAbrirOrden,
    required this.onVerMesas,
    required this.onVerReportes,
  });

  static final _dinero = NumberFormat('#,##0.00', 'en_US');
  static String _m(double v) => '\$${_dinero.format(v)}';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final angosto = c.maxWidth < 900;
      final izquierda = [
        _tarjeta(
          titulo: 'Ventas de los últimos 7 días',
          detalle: 'Con IVA, sin propinas. Hoy, hasta ahora.',
          accion: ('Ver reportes', onVerReportes),
          child: _BarrasSemana(dias: _semana()),
        ),
        _ordenesEnCurso(),
      ];
      final derecha = [
        _masVendidosHoy(),
      ];
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            avisoPago,
            avisoInventario,
            _indicadores(context, angosto),
            const SizedBox(height: 18),
            if (angosto)
              ..._separados([...izquierda, ...derecha])
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: Column(children: _separados(izquierda))),
                  const SizedBox(width: 18),
                  Expanded(child: Column(children: _separados(derecha))),
                ],
              ),
          ],
        ),
      );
    });
  }

  List<Widget> _separados(List<Widget> w) => [
        for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(height: 18), w[i]],
      ];

  /// La semana con hoy al final, con lo que ya se sabe de hoy.
  List<({String etiqueta, double ventas, bool hoy})> _semana() {
    final f = DateFormat('EEE d', 'es');
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('.', '');
    return [
      for (final d in semanaPrevia) (etiqueta: cap(f.format(d.dia)), ventas: d.ventas, hoy: false),
      (etiqueta: 'Hoy', ventas: ventasHoy, hoy: true),
    ];
  }

  Widget _indicadores(BuildContext context, bool angosto) {
    final ayer = semanaPrevia.isEmpty ? null : semanaPrevia.last.ventas;
    final paraLlevar = ordenes.where((o) => o.esParaLlevar).length;
    final listas = ordenes.where((o) => o.detalles.any((d) => d.isListo)).length;
    String? variacion;
    var sube = true;
    if (ayer != null && ayer > 0 && !cargando) {
      final v = (ventasHoy - ayer) / ayer;
      sube = v >= 0;
      variacion = '${sube ? '▲' : '▼'} ${(v.abs() * 100).toStringAsFixed(0)}%';
    }
    final kpis = [
      _Kpi(
        icono: Icons.payments_outlined,
        color: AppColors.success,
        rotulo: 'Ventas de hoy',
        valor: cargando ? '…' : _m(ventasHoy),
        detalle: ayer == null ? null : 'contra ayer (${_m(ayer)})',
        variacion: variacion,
        sube: sube,
      ),
      _Kpi(
        icono: Icons.table_restaurant_outlined,
        color: AppColors.primary,
        rotulo: 'Mesas ocupadas',
        valor: cargando ? '…' : '$mesasOcupadas',
        detalle: mesasTotal > 0 ? 'de $mesasTotal mesas' : null,
      ),
      _Kpi(
        icono: Icons.soup_kitchen_outlined,
        color: AppColors.warning,
        rotulo: 'Órdenes en curso',
        valor: cargando ? '…' : '${ordenes.length}',
        detalle: ordenes.isEmpty
            ? null
            : [
                if (paraLlevar > 0) '$paraLlevar para llevar',
                if (listas > 0) '$listas con platos listos',
              ].join(' · '),
      ),
      _Kpi(
        icono: Icons.receipt_long_outlined,
        color: AppColors.info,
        rotulo: 'Comprobantes emitidos',
        valor: cargando ? '…' : '$facturasHoy',
        detalle: 'hoy',
      ),
    ];
    // Alto fijo que crece con el tamaño de texto elegido, como en el resto
    // de la app: con proporciones fijas, "Muy grande" desbordaba la tarjeta.
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: angosto ? 2 : 4,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: 116 * escalaTextoDe(context),
      ),
      children: kpis,
    );
  }

  Widget _ordenesEnCurso() {
    final lista = [...ordenes]..sort((a, b) => a.fechaCreacion.compareTo(b.fechaCreacion));
    return _tarjeta(
      titulo: 'Órdenes en curso',
      detalle: 'Se actualiza sola cada 30 segundos. Toca una para abrirla.',
      accion: ('Ver mesas', onVerMesas),
      child: lista.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('No hay órdenes abiertas ahora.', style: _Estilos.secundario),
            )
          : Column(
              children: [
                const _FilaOrden.encabezado(),
                for (final o in lista) _FilaOrden(orden: o, onTap: () => onAbrirOrden(o)),
              ],
            ),
    );
  }

  Widget _masVendidosHoy() {
    final top = masVendidos;
    Widget cuerpo;
    if (top == null) {
      cuerpo = const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (top.isEmpty) {
      cuerpo = const Text('Todavía no hay ventas hoy.', style: _Estilos.secundario);
    } else {
      final maximo = top.first.unidades;
      cuerpo = Column(
        children: [
          for (var i = 0; i < top.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textHint)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(top[i].nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: maximo > 0 ? top[i].unidades / maximo : 0,
                            minHeight: 6,
                            color: AppColors.primary,
                            backgroundColor: AppColors.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${top[i].unidades}',
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
        ],
      );
    }
    return _tarjeta(titulo: 'Más vendidos hoy', detalle: 'Por unidades.', child: cuerpo);
  }

  Widget _tarjeta({
    required String titulo,
    String? detalle,
    (String, VoidCallback)? accion,
    required Widget child,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(titulo,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                if (accion != null)
                  TextButton(
                    onPressed: accion.$2,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(accion.$1),
                  ),
              ],
            ),
            if (detalle != null) Text(detalle, style: _Estilos.secundario),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

abstract final class _Estilos {
  static const secundario = TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary);
}

class _Kpi extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String rotulo;
  final String valor;
  final String? detalle;
  final String? variacion;
  final bool sube;

  const _Kpi({
    required this.icono,
    required this.color,
    required this.rotulo,
    required this.valor,
    this.detalle,
    this.variacion,
    this.sube = true,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icono, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(rotulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            Text.rich(
              TextSpan(children: [
                if (variacion != null)
                  TextSpan(
                    text: '$variacion ',
                    style: TextStyle(fontWeight: FontWeight.w600, color: sube ? AppColors.success : AppColors.error),
                  ),
                TextSpan(text: detalle ?? ''),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _Estilos.secundario,
            ),
          ],
        ),
      );
}

/// Una fila de la tabla de órdenes en curso.
class _FilaOrden extends StatelessWidget {
  final OrdenModel? orden;
  final VoidCallback? onTap;

  const _FilaOrden({required OrdenModel this.orden, required this.onTap});
  const _FilaOrden.encabezado()
      : orden = null,
        onTap = null;

  /// Lo más urgente de la orden, mirando sus platos.
  static (String, Color) _estado(OrdenModel o) {
    final vivos = o.detalles.where((d) => d.estado != 'CANCELADO');
    if (vivos.any((d) => d.isListo)) return ('Platos listos', AppColors.success);
    if (vivos.any((d) => d.isEnPreparacion)) return ('En cocina', AppColors.info);
    if (vivos.any((d) => d.isPendiente)) return ('Pendiente', AppColors.warning);
    return ('Servida', AppColors.textSecondary);
  }

  @override
  Widget build(BuildContext context) {
    const cab = TextStyle(
        fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.textHint);
    const celda = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary);
    final o = orden;
    Widget fila(List<Widget> c) => Row(children: [
          Expanded(flex: 4, child: c[0]),
          Expanded(flex: 3, child: c[1]),
          Expanded(flex: 2, child: c[2]),
          Expanded(flex: 3, child: c[3]),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: c[4])),
        ]);
    if (o == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surfaceVariant))),
        child: fila(const [
          Text('LUGAR', style: cab),
          Text('MESERO', style: cab),
          Text('DESDE', style: cab),
          Text('ESTADO', style: cab),
          Text('TOTAL', style: cab),
        ]),
      );
    }
    final hora = o.fechaCreacion.toLocal();
    final (estado, color) = _estado(o);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surface))),
        child: fila([
          Text(o.lugarConNota,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: celda.copyWith(fontWeight: FontWeight.w600)),
          Text(o.nombreUsuario, maxLines: 1, overflow: TextOverflow.ellipsis, style: celda),
          Text('${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}', style: celda),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Text(estado,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ),
          ),
          Text(PanelAdminEscritorio._m(o.total),
              style: celda.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// Barras de la semana, a escala con la venta más alta. Sin paquete de
/// gráficos: son siete barras y no justifican una dependencia.
class _BarrasSemana extends StatelessWidget {
  final List<({String etiqueta, double ventas, bool hoy})> dias;

  const _BarrasSemana({required this.dias});

  @override
  Widget build(BuildContext context) {
    final maximo = dias.fold<double>(0, (m, d) => d.ventas > m ? d.ventas : m);
    final esc = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 190 + 30 * (esc - 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in dias)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        d.ventas > 0 ? '\$${d.ventas.toStringAsFixed(0)}' : '—',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: d.hoy ? FontWeight.w700 : FontWeight.w500,
                          color: d.hoy ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: maximo > 0 ? (d.ventas / maximo).clamp(0.02, 1.0) : 0.02,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 52),
                          decoration: BoxDecoration(
                            color: d.hoy ? AppColors.primary : AppColors.border,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(d.etiqueta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          fontWeight: d.hoy ? FontWeight.w700 : FontWeight.w400,
                          color: d.hoy ? AppColors.textPrimary : AppColors.textSecondary,
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
