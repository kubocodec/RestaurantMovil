import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/factura_model.dart';
import '../../../core/network/api_client.dart';
import '../data/configuracion_repository.dart';

/// Catálogo de métodos de pago de la sucursal (efectivo, tarjetas,
/// transferencia, etc.). El admin puede crear, editar y activar/desactivar.
class MetodosPagoConfigScreen extends StatefulWidget {
  final String sucursalId;
  const MetodosPagoConfigScreen({super.key, required this.sucursalId});

  @override
  State<MetodosPagoConfigScreen> createState() => _MetodosPagoConfigScreenState();
}

class _MetodosPagoConfigScreenState extends State<MetodosPagoConfigScreen> {
  final _repo = ConfiguracionRepository();
  List<MetodoPagoModel> _metodos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final data = await _repo.getMetodosPago(widget.sucursalId);
      if (!mounted) return;
      setState(() { _metodos = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Métodos de Pago')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCrearDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo método'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
      ],
    ),
  );

  Widget _buildBody() {
    if (_metodos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_outlined, size: 64, color: AppColors.earth2.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text('No hay métodos de pago',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('El cajero necesita al menos un método activo para cobrar',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showCrearDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear método'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El arqueo de caja cuenta solo lo cobrado con el método "Efectivo". '
                  '"Requiere referencia" pide un número de comprobante al cobrar (voucher, transferencia).',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              // Espacio extra al final para que el FAB no tape el último método
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              itemCount: _metodos.length,
              itemBuilder: (_, i) => _MetodoCard(
                metodo: _metodos[i],
                onToggle: () => _toggle(_metodos[i]),
                onEdit: () => _showEditarDialog(_metodos[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(MetodoPagoModel metodo) async {
    try {
      await _repo.toggleMetodoPago(metodo.metodoPagoId);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  void _showCrearDialog() => _showFormDialog();

  void _showEditarDialog(MetodoPagoModel metodo) => _showFormDialog(metodo: metodo);

  void _showFormDialog({MetodoPagoModel? metodo}) {
    final esNuevo = metodo == null;
    final nombreCtrl = TextEditingController(text: metodo?.nombre ?? '');
    final descCtrl = TextEditingController(text: metodo?.descripcion ?? '');
    bool requiereRef = metodo?.requiereReferencia ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(esNuevo ? 'Nuevo método de pago' : 'Editar método de pago',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    hintText: 'ej: De Una, PeiGo, Datafast',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requiere referencia',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  subtitle: const Text('Pide número de comprobante al cobrar',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                  value: requiereRef,
                  onChanged: (v) => setDialogState(() => requiereRef = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                if (nombre.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('El nombre es requerido')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                try {
                  if (esNuevo) {
                    await _repo.crearMetodoPago(
                      sucursalId:         widget.sucursalId,
                      nombre:             nombre,
                      descripcion:        descCtrl.text.trim(),
                      requiereReferencia: requiereRef,
                    );
                  } else {
                    await _repo.actualizarMetodoPago(
                      metodoPagoId:       metodo.metodoPagoId,
                      nombre:             nombre,
                      descripcion:        descCtrl.text.trim(),
                      requiereReferencia: requiereRef,
                    );
                  }
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(esNuevo ? 'Método de pago creado' : 'Método de pago actualizado'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                  _load();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
                  );
                }
              },
              child: Text(esNuevo ? 'Crear' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetodoCard extends StatelessWidget {
  final MetodoPagoModel metodo;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  const _MetodoCard({required this.metodo, required this.onToggle, required this.onEdit});

  IconData get _icono {
    final n = metodo.nombre.toUpperCase();
    if (n.contains('EFECTIVO')) return Icons.payments_outlined;
    if (n.contains('TARJETA')) return Icons.credit_card_outlined;
    if (n.contains('TRANSFER')) return Icons.account_balance_outlined;
    if (n.contains('CHEQUE')) return Icons.receipt_long_outlined;
    return Icons.account_balance_wallet_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
          border: metodo.activo
              ? null
              : Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.earth2.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_icono, color: AppColors.earth2, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metodo.nombre,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                  if (metodo.descripcion.isNotEmpty)
                    Text(metodo.descripcion,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                  if (metodo.requiereReferencia)
                    const Text('Requiere referencia',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.info)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Switch(value: metodo.activo, onChanged: (_) => onToggle(), activeColor: AppColors.success),
                Text(metodo.activo ? 'Activo' : 'Inactivo',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10,
                      color: metodo.activo ? AppColors.success : AppColors.error,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
