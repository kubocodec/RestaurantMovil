import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/network/api_client.dart';
import '../data/configuracion_repository.dart';

class CajasConfigScreen extends StatefulWidget {
  final String sucursalId;
  const CajasConfigScreen({super.key, required this.sucursalId});

  @override
  State<CajasConfigScreen> createState() => _CajasConfigScreenState();
}

class _CajasConfigScreenState extends State<CajasConfigScreen> {
  final _repo = ConfiguracionRepository();
  List<CajaConfigModel> _cajas = [];
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
      final data = await _repo.getCajas(widget.sucursalId);
      if (!mounted) return;
      setState(() { _cajas = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Cajas Registradoras')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCrearDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva caja'),
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
    if (_cajas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.point_of_sale_outlined, size: 64, color: AppColors.earth2.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No hay cajas configuradas',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('El cajero necesita al menos una caja para operar',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showCrearDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear caja'),
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
            color: AppColors.info.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withOpacity(0.25)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El código de punto de emisión es requerido para la facturación electrónica (Ecuador). Ej: 001, 002.',
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
              // Espacio extra al final para que el FAB no tape la última caja
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              itemCount: _cajas.length,
              itemBuilder: (_, i) => _CajaCard(
                caja: _cajas[i],
                onToggle: () => _toggle(_cajas[i]),
                onEdit: () => _showEditarDialog(_cajas[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(CajaConfigModel caja) async {
    try {
      await _repo.toggleCaja(caja.cajaId);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  void _showEditarDialog(CajaConfigModel caja) {
    final nombreCtrl = TextEditingController(text: caja.nombre);
    final codigoCtrl = TextEditingController(text: caja.codigoPuntoEmision);
    final descCtrl   = TextEditingController(text: caja.descripcion ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar caja', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre de la caja *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codigoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código punto emisión *',
                  helperText: '3 dígitos, ej: 001',
                ),
                maxLength: 3,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              final codigo = codigoCtrl.text.trim();
              if (nombre.isEmpty || codigo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nombre y código son requeridos')),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await _repo.actualizarCaja(
                  cajaId:              caja.cajaId,
                  sucursalId:          widget.sucursalId,
                  nombre:              nombre,
                  codigoPuntoEmision:  codigo,
                  descripcion:         descCtrl.text.trim(),
                );
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Caja actualizada'), backgroundColor: AppColors.success),
                );
                _load();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showCrearDialog() {
    final nombreCtrl = TextEditingController();
    final codigoCtrl = TextEditingController(text: '001');
    final descCtrl   = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Caja', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre de la caja *', hintText: 'ej: Caja Principal'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codigoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código punto emisión *',
                  helperText: '3 dígitos, ej: 001',
                ),
                maxLength: 3,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              final codigo = codigoCtrl.text.trim();
              if (nombre.isEmpty || codigo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nombre y código son requeridos')),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await _repo.crearCaja(
                  sucursalId:          widget.sucursalId,
                  nombre:              nombre,
                  codigoPuntoEmision:  codigo,
                  descripcion:         descCtrl.text.trim(),
                );
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Caja creada'), backgroundColor: AppColors.success),
                );
                _load();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
                );
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}

class _CajaCard extends StatelessWidget {
  final CajaConfigModel caja;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  const _CajaCard({required this.caja, required this.onToggle, required this.onEdit});

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
        border: caja.activo
            ? null
            : Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.earth2.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.point_of_sale_outlined, color: AppColors.earth2, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caja.nombre,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                Text('Punto emisión: ${caja.codigoPuntoEmision}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                if (caja.descripcion?.isNotEmpty ?? false)
                  Text(caja.descripcion ?? '',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Switch(value: caja.activo, onChanged: (_) => onToggle(), activeColor: AppColors.success),
              Text(caja.activo ? 'Activa' : 'Inactiva',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10,
                    color: caja.activo ? AppColors.success : AppColors.error,
                  )),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
