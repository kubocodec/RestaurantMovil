import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../features/facturacion/data/facturacion_repository.dart';

/// Precio sin IVA a partir del precio de menú con IVA, con 6 decimales:
/// $3.00 al 15% → 2.608696. Con 2 decimales se guardaba 2.61 y el centavo se
/// acumulaba con la cantidad (4 pizzas cobraban $12.01).
double precioSinIva(double conIva, double tarifa) =>
    (conIva / (1 + tarifa / 100) * 1000000).roundToDouble() / 1000000;

/// Lo que paga el cliente por una unidad (precio sin IVA + IVA, en centavos).
double precioConIva(double sinIva, double tarifa) {
  final micro = (sinIva * 1000000).round();
  final base = (micro + 5000) ~/ 10000;
  final iva = (micro * (tarifa * 100).round() + 50000000) ~/ 100000000;
  return (base + iva) / 100;
}

/// El precio se guardó desde un precio con IVA (tiene más de 2 decimales).
bool tieneDecimalesExtra(double precio) =>
    ((precio * 100) - (precio * 100).roundToDouble()).abs() > 0.000001;

/// Diálogo para escribir el precio de un plato en la sucursal. Devuelve el
/// precio SIN IVA a guardar, o null si se cancela.
///
/// Con "El precio incluye IVA" el administrador escribe el precio del menú
/// ($3.00) y se guarda ÷ (1 + IVA) con 6 decimales, para que el cobro cuadre
/// al centavo con cualquier cantidad. Apagado, funciona como siempre. Un
/// precio que ya se guardó así se abre con la casilla encendida y mostrando
/// el precio con IVA: mostrarlo con 2 decimales y volver a guardarlo
/// reintroduciría el error.
class PrecioDialog extends StatefulWidget {
  final String titulo;
  final String sucursalId;
  final double? precioActual;
  /// Tarifa propia del plato; null = la predeterminada de la sucursal.
  final double? tarifaPlato;
  final String textoBoton;

  const PrecioDialog({
    super.key,
    required this.titulo,
    required this.sucursalId,
    this.precioActual,
    this.tarifaPlato,
    this.textoBoton = 'Guardar',
  });

  @override
  State<PrecioDialog> createState() => _PrecioDialogState();
}

class _PrecioDialogState extends State<PrecioDialog> {
  final _ctrl = TextEditingController();
  late bool _incluyeIva;
  double? _tarifa;

  @override
  void initState() {
    super.initState();
    final actual = widget.precioActual;
    _incluyeIva = actual != null && tieneDecimalesExtra(actual);
    _tarifa = widget.tarifaPlato;
    if (_tarifa != null) {
      _llenar();
    } else {
      _cargarTarifa();
    }
  }

  Future<void> _cargarTarifa() async {
    final t = await FacturacionRepository().getIvaVigente(widget.sucursalId);
    if (!mounted) return;
    setState(() => _tarifa = t ?? 0);
    _llenar();
  }

  void _llenar() {
    final actual = widget.precioActual;
    if (actual == null) return;
    _ctrl.text = (_incluyeIva ? precioConIva(actual, _tarifa ?? 0) : actual).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _valor {
    final v = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    return v == null || v <= 0 ? null : v;
  }

  String _pct(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final tarifa = _tarifa;
    final valor = _valor;
    String? ayuda;
    if (tarifa != null && valor != null && tarifa > 0) {
      ayuda = _incluyeIva
          ? 'Se guarda \$${precioSinIva(valor, tarifa).toStringAsFixed(6)} + IVA ${_pct(tarifa)}%: '
            'el cliente paga \$${valor.toStringAsFixed(2)}'
          : 'Con IVA ${_pct(tarifa)}% el cliente paga \$${precioConIva(valor, tarifa).toStringAsFixed(2)}';
    }
    return AlertDialog(
      title: Text(widget.titulo,
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: _incluyeIva ? 'Precio con IVA (lo que paga el cliente) *' : 'Precio sin IVA *',
              prefixText: '\$  ',
            ),
            onChanged: (_) => setState(() {}),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _incluyeIva,
            // Sin tarifa todavía no se puede convertir.
            onChanged: tarifa == null ? null : (v) => setState(() => _incluyeIva = v ?? false),
            title: const Text('El precio incluye IVA',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          ),
          if (ayuda != null)
            Text(ayuda,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: valor == null || tarifa == null
              ? null
              : () => Navigator.pop(context, _incluyeIva ? precioSinIva(valor, tarifa) : valor),
          child: Text(widget.textoBoton),
        ),
      ],
    );
  }
}
