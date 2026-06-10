import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/salon_model.dart';
import '../../../core/models/mesa_model.dart';
import '../../../core/network/api_client.dart';
import '../data/configuracion_repository.dart';

class SalonesMesasScreen extends StatefulWidget {
  final String sucursalId;
  const SalonesMesasScreen({super.key, required this.sucursalId});

  @override
  State<SalonesMesasScreen> createState() => _SalonesMesasScreenState();
}

class _SalonesMesasScreenState extends State<SalonesMesasScreen> {
  final _repo = ConfiguracionRepository();
  List<SalonModel> _salones = [];
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
      final salones = await _repo.getSalones(widget.sucursalId);
      if (!mounted) return;
      setState(() { _salones = salones; _loading = false; });
    } catch (e, st) {
      debugPrint('SalonesMesasScreen._load error: $e\n$st');
      if (!mounted) return;
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Salones y Mesas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCrearSalonDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo salón'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
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
    if (_salones.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_restaurant_outlined, size: 64, color: AppColors.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No hay salones configurados',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Crea salones y agrega mesas para poder tomar órdenes',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showCrearSalonDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear salón'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _salones.length,
        itemBuilder: (_, i) => _SalonCard(
          salon: _salones[i],
          repo: _repo,
          onChanged: _load,
        ),
      ),
    );
  }

  void _showCrearSalonDialog() {
    final nombreCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo salón', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre del salón *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              if (nombre.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _repo.crearSalon(
                  sucursalId:  widget.sucursalId,
                  nombre:      nombre,
                  descripcion: descCtrl.text.trim(),
                );
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Salón creado'), backgroundColor: AppColors.success),
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

class _SalonCard extends StatefulWidget {
  final SalonModel salon;
  final ConfiguracionRepository repo;
  final VoidCallback onChanged;

  const _SalonCard({required this.salon, required this.repo, required this.onChanged});

  @override
  State<_SalonCard> createState() => _SalonCardState();
}

class _SalonCardState extends State<_SalonCard> {
  List<MesaModel> _mesas = [];
  bool _loadingMesas = false;
  bool _expanded = false;

  Future<void> _loadMesas() async {
    setState(() { _loadingMesas = true; });
    try {
      final mesas = await widget.repo.getMesasBySalon(widget.salon.salonId);
      setState(() { _mesas = mesas; _loadingMesas = false; });
    } catch (_) {
      setState(() { _loadingMesas = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () {
              setState(() { _expanded = !_expanded; });
              if (_expanded && _mesas.isEmpty) _loadMesas();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.meeting_room_outlined, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.salon.nombre,
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                        if (widget.salon.descripcion.isNotEmpty)
                          Text(widget.salon.descripcion,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                    onPressed: () => _showCrearMesaDialog(context),
                    tooltip: 'Agregar mesa',
                  ),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) _buildMesasList(),
        ],
      ),
    );
  }

  Widget _buildMesasList() {
    if (_loadingMesas) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_mesas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: [
            const Icon(Icons.table_bar_outlined, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            const Text('Sin mesas — ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            GestureDetector(
              onTap: () => _showCrearMesaDialog(context),
              child: const Text('agregar mesa',
                  style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _mesas.map((m) => _MesaChip(mesa: m)).toList(),
      ),
    );
  }

  void _showCrearMesaDialog(BuildContext context) {
    final numCtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '4');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nueva mesa en ${widget.salon.nombre}',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numCtrl,
              decoration: const InputDecoration(labelText: 'Número de mesa *', hintText: 'ej: 1, A1, VIP-1'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacidad (personas)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final num = numCtrl.text.trim();
              final cap = int.tryParse(capCtrl.text.trim()) ?? 4;
              if (num.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.repo.crearMesa(
                  salonId:    widget.salon.salonId,
                  numeroMesa: num,
                  capacidad:  cap,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mesa creada'), backgroundColor: AppColors.success),
                );
                _loadMesas();
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
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

class _MesaChip extends StatelessWidget {
  final MesaModel mesa;
  const _MesaChip({required this.mesa});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.table_bar_outlined, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Text('Mesa ${mesa.numeroMesa}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
          Text('  (${mesa.capacidad} pax)',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
