import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/orden_model.dart';

/// Resumen de la orden de la mesa elegida, al lado de la cuadrícula de mesas
/// (solo en la web de escritorio).
///
/// Solo MUESTRA: tomar el pedido, la precuenta y el cobro siguen en sus
/// pantallas de siempre, que se abren con los botones. Así el cobro y las
/// anulaciones no tienen un camino nuevo que probar.
class PanelOrdenMesa extends StatelessWidget {
  final OrdenModel? orden;
  final bool puedeCobrar;
  final VoidCallback onAbrir;
  final VoidCallback onPrecuenta;
  final VoidCallback onCobrar;

  const PanelOrdenMesa({
    super.key,
    required this.orden,
    required this.puedeCobrar,
    required this.onAbrir,
    required this.onPrecuenta,
    required this.onCobrar,
  });

  static const _t13 = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary);
  static const _t11 = TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary);

  static (String, Color) _estado(DetalleOrdenModel d) {
    if (d.isListo) return ('Listo', AppColors.success);
    if (d.isEnPreparacion) return ('En cocina', AppColors.info);
    if (d.isEntregado) return ('Servido', AppColors.textSecondary);
    return ('Pendiente', AppColors.warning);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(left: BorderSide(color: AppColors.surfaceVariant)),
      ),
      child: orden == null ? _vacio() : _conOrden(orden!),
    );
  }

  Widget _vacio() => const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 40, color: AppColors.textHint),
              SizedBox(height: 12),
              Text('Toca una mesa ocupada o un pedido para llevar para ver su orden aquí.',
                  textAlign: TextAlign.center, style: _t11),
              SizedBox(height: 6),
              Text('Las mesas libres se abren directo, como siempre.', textAlign: TextAlign.center, style: _t11),
            ],
          ),
        ),
      );

  Widget _conOrden(OrdenModel o) {
    final hora = o.fechaCreacion.toLocal();
    final vivos = o.detalles.where((d) => d.estado != 'CANCELADO').toList();
    // Lo mismo que muestra la orden en su franja "Por cobrar".
    final porCobrar = o.detallesNoFacturados.fold(0.0, (s, d) => s + d.subtotalPendiente);
    final hayPorCobrar = o.detallesNoFacturados.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(o.lugarConNota,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                [
                  'Orden #${o.numeroOrden}',
                  if (o.nombreUsuario.isNotEmpty) o.nombreUsuario,
                  'desde ${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}',
                  if ((o.numComensales ?? 0) > 0) '${o.numComensales} personas',
                ].join(' · '),
                style: _t11,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: vivos.isEmpty
              ? const Center(child: Text('La orden todavía no tiene platos.', style: _t11))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  itemCount: vivos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surface),
                  itemBuilder: (_, i) {
                    final d = vivos[i];
                    final (estado, color) = _estado(d);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text('${d.cantidad}',
                                style: _t13.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.nombrePlato, style: _t13.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    _pildora(estado, color),
                                    if (d.facturado) _pildora('Cobrado', AppColors.textSecondary),
                                  ],
                                ),
                                if ((d.observaciones ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text('Nota: ${d.observaciones}', style: _t11),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('\$${d.subtotal.toStringAsFixed(2)}',
                              style: _t13.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.surfaceVariant))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Por cobrar', style: _t13)),
                  Text('\$${porCobrar.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cajeroColor)),
                ],
              ),
              const Text('El total con IVA se calcula al cobrar.', style: _t11),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onAbrir,
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Abrir orden'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPrecuenta,
                    icon: const Icon(Icons.receipt_outlined, size: 18),
                    label: const Text('Precuenta'),
                  ),
                ],
              ),
              if (puedeCobrar && hayPorCobrar) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cajeroColor),
                  onPressed: onCobrar,
                  icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                  label: const Text('Cobrar'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _pildora(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w600, color: c)),
      );
}
