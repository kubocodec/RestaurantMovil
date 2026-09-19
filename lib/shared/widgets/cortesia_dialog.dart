import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Resultado del diálogo: cuántas unidades se regalan y por qué.
class CortesiaElegida {
  final int cantidad;
  final String motivo;
  const CortesiaElegida(this.cantidad, this.motivo);
}

/// Pide el motivo (obligatorio) y, si la línea tiene varias unidades, cuántas
/// se regalan. Con [mesaCompleta] no pregunta cantidad: se regala todo.
///
/// Es un widget con estado propio para que el controller se libere después de
/// la animación de cierre (ver CLAUDE.md: "TextEditingController used after
/// being disposed").
class CortesiaDialog extends StatefulWidget {
  final String titulo;
  final String detalle;
  final int maxUnidades;
  final bool mesaCompleta;

  const CortesiaDialog({
    super.key,
    required this.titulo,
    required this.detalle,
    this.maxUnidades = 1,
    this.mesaCompleta = false,
  });

  @override
  State<CortesiaDialog> createState() => _CortesiaDialogState();
}

class _CortesiaDialogState extends State<CortesiaDialog> {
  static const _motivos = ['Cumpleaños', 'Demora', 'Error de cocina', 'Cliente frecuente'];

  final _motivoCtrl = TextEditingController();
  late int _cantidad;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cantidad = widget.maxUnidades;
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  void _aceptar() {
    final motivo = _motivoCtrl.text.trim();
    if (motivo.isEmpty) {
      setState(() => _error = 'Escribe o elige el motivo');
      return;
    }
    Navigator.pop(context, CortesiaElegida(_cantidad, motivo));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.card_giftcard_rounded, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.titulo,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.detalle,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12.5,
                    color: AppColors.textSecondary, height: 1.4)),
            if (!widget.mesaCompleta && widget.maxUnidades > 1) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text('Unidades a regalar',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  IconButton(
                    onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_cantidad / ${widget.maxUnidades}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
                  IconButton(
                    onPressed: _cantidad < widget.maxUnidades
                        ? () => setState(() => _cantidad++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text('Motivo',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _motivos.map((m) {
                final sel = _motivoCtrl.text == m;
                return ChoiceChip(
                  label: Text(m),
                  selected: sel,
                  selectedColor: AppColors.success,
                  labelStyle: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.textPrimary),
                  onSelected: (_) => setState(() {
                    _motivoCtrl.text = m;
                    _error = null;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _motivoCtrl,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(
                  labelText: 'Otro motivo', isDense: true, counterText: ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          onPressed: _aceptar,
          child: Text(widget.mesaCompleta ? 'Regalar la mesa' : 'Dar cortesía'),
        ),
      ],
    );
  }
}
