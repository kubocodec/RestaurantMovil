import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/network/api_client.dart';
import '../data/configuracion_repository.dart';

/// Configuración de impresoras de comandas (cocina, barra, etc.).
/// Cada impresora atiende las categorías de platos que se le asignen:
/// al enviar una orden, cada ítem se imprime en la impresora de su categoría.
class ImpresorasConfigScreen extends StatefulWidget {
  final String sucursalId;
  final String restaurantId;
  const ImpresorasConfigScreen({
    super.key,
    required this.sucursalId,
    required this.restaurantId,
  });

  @override
  State<ImpresorasConfigScreen> createState() => _ImpresorasConfigScreenState();
}

class _ImpresorasConfigScreenState extends State<ImpresorasConfigScreen> {
  final _repo = ConfiguracionRepository();
  List<ImpresoraModel> _impresoras = [];
  List<CategoriaModel> _categorias = [];
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
      final results = await Future.wait([
        _repo.getImpresoras(widget.sucursalId),
        _repo.getCategorias(widget.restaurantId),
      ]);
      if (!mounted) return;
      setState(() {
        _impresoras = results[0] as List<ImpresoraModel>;
        _categorias = results[1] as List<CategoriaModel>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Impresoras de comandas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFormDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva impresora'),
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
    if (_impresoras.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.print_outlined, size: 64, color: AppColors.earth2.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              const Text('No hay impresoras configuradas',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              const Text(
                'Crea una impresora por estación (cocina, barra) y asígnale las categorías de platos que debe imprimir.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _showFormDialog(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crear impresora'),
              ),
            ],
          ),
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
                  'Al enviar una orden, cada ítem se imprime en la impresora asignada a su categoría (ej: bebidas → barra, platos fuertes → cocina). Usa la IP de la impresora térmica en la red local (puerto 9100 por defecto).',
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
              // Espacio extra al final: el FAB no debe tapar la última impresora
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              itemCount: _impresoras.length,
              itemBuilder: (_, i) => _ImpresoraCard(
                impresora: _impresoras[i],
                onToggle: () => _toggle(_impresoras[i]),
                onEdit: () => _showFormDialog(impresora: _impresoras[i]),
                onCategorias: () => _showCategoriasDialog(_impresoras[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(ImpresoraModel imp) async {
    try {
      await _repo.toggleImpresora(imp.impresoraId);
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  void _showFormDialog({ImpresoraModel? impresora}) {
    final esEdicion = impresora != null;
    final nombreCtrl = TextEditingController(text: impresora?.nombre ?? '');
    final areaCtrl   = TextEditingController(text: impresora?.area ?? '');
    final ipCtrl     = TextEditingController(text: impresora?.ip ?? '');
    final puertoCtrl = TextEditingController(text: (impresora?.puerto ?? 9100).toString());
    final seleccion  = Set<String>.from(impresora?.categoriaIds ?? const []);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(esEdicion ? 'Editar impresora' : 'Nueva impresora',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'ej: Cocina principal'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: areaCtrl,
                  decoration: const InputDecoration(labelText: 'Área', hintText: 'ej: Cocina, Barra'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ipCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'IP en la red local *', hintText: 'ej: 192.168.1.50'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: puertoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Puerto', helperText: '9100 en la mayoría de impresoras térmicas'),
                ),
                if (!esEdicion) ...[
                  const SizedBox(height: 12),
                  const Text('Categorías que imprime:',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                  ..._buildCategoriaChecks(seleccion, setDialogState),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final ip = ipCtrl.text.trim();
                if (nombre.isEmpty || ip.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nombre e IP son requeridos')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                try {
                  if (esEdicion) {
                    await _repo.actualizarImpresora(
                      impresoraId: impresora.impresoraId,
                      sucursalId: widget.sucursalId,
                      nombre: nombre,
                      area: areaCtrl.text.trim(),
                      ip: ip,
                      puerto: int.tryParse(puertoCtrl.text.trim()) ?? 9100,
                    );
                  } else {
                    await _repo.crearImpresora(
                      sucursalId: widget.sucursalId,
                      nombre: nombre,
                      area: areaCtrl.text.trim(),
                      ip: ip,
                      puerto: int.tryParse(puertoCtrl.text.trim()) ?? 9100,
                      categoriaIds: seleccion.toList(),
                    );
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(esEdicion ? 'Impresora actualizada' : 'Impresora creada'),
                      backgroundColor: AppColors.success,
                    ));
                  }
                  _load();
                } catch (e) {
                  _showError(e);
                }
              },
              child: Text(esEdicion ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoriasDialog(ImpresoraModel imp) {
    final seleccion = Set<String>.from(imp.categoriaIds);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Categorías: ${imp.nombre}',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildCategoriaChecks(seleccion, setDialogState),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _repo.asignarCategoriasImpresora(imp.impresoraId, seleccion.toList());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Categorías asignadas'), backgroundColor: AppColors.success,
                    ));
                  }
                  _load();
                } catch (e) {
                  _showError(e);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategoriaChecks(Set<String> seleccion, StateSetter setDialogState) {
    if (_categorias.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No hay categorías creadas. Crea primero el menú.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
        ),
      ];
    }
    return _categorias.map((c) => CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(c.nombre, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      value: seleccion.contains(c.categoriaId),
      onChanged: (v) => setDialogState(() {
        if (v == true) {
          seleccion.add(c.categoriaId);
        } else {
          seleccion.remove(c.categoriaId);
        }
      }),
    )).toList();
  }

  void _showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
      );
    }
  }
}

class _ImpresoraCard extends StatelessWidget {
  final ImpresoraModel impresora;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onCategorias;

  const _ImpresoraCard({
    required this.impresora,
    required this.onToggle,
    required this.onEdit,
    required this.onCategorias,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
        border: impresora.activo ? null : Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.earth2.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.print_outlined, color: AppColors.earth2, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(impresora.nombre,
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(
                      '${impresora.area?.isNotEmpty == true ? '${impresora.area} · ' : ''}${impresora.ip ?? 'sin IP'}:${impresora.puerto ?? 9100}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(value: impresora.activo, onChanged: (_) => onToggle(), activeColor: AppColors.success),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (impresora.categorias.isEmpty)
                const Text('Sin categorías asignadas — no imprimirá comandas',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.warning)),
              ...impresora.categorias.map((c) => Chip(
                label: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onCategorias,
                icon: const Icon(Icons.category_outlined, size: 16),
                label: const Text('Categorías', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
