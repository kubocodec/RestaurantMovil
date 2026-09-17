import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/network/api_client.dart';
import '../data/configuracion_repository.dart';

class TasaIvaScreen extends StatefulWidget {
  final String tenantId;
  const TasaIvaScreen({super.key, required this.tenantId});

  @override
  State<TasaIvaScreen> createState() => _TasaIvaScreenState();
}

class _TasaIvaScreenState extends State<TasaIvaScreen> {
  final _repo = ConfiguracionRepository();
  List<TasaIvaModel> _tasas = [];
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
      final data = await _repo.getTasasIva(widget.tenantId);
      if (!mounted) return;
      setState(() { _tasas = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Tasas de IVA')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCrearDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva tasa'),
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
    if (_tasas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.percent_rounded, size: 64, color: AppColors.cajeroColor.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No hay tasas de IVA configuradas',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Crea una tasa para poder emitir facturas',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showCrearDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear tasa IVA'),
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
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Debe existir al menos una tasa IVA activa y vigente para poder emitir '
                  'facturas. La marcada con la estrella es la que se aplica a los platos que '
                  'no tienen tarifa propia; las demás quedan disponibles para asignarlas '
                  'plato por plato desde el menú.',
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
              // Espacio extra al final: el FAB no debe tapar la última tasa
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              itemCount: _tasas.length,
              itemBuilder: (_, i) => _TasaCard(
                tasa: _tasas[i],
                onToggle: () => _toggle(_tasas[i]),
                onPredeterminada: () => _marcarPredeterminada(_tasas[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _marcarPredeterminada(TasaIvaModel tasa) async {
    try {
      await _repo.marcarTasaIvaPredeterminada(tasa.tasaIvaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Los platos sin tarifa propia ahora facturan al '
              '${tasa.porcentaje.toStringAsFixed(0)}%'),
          backgroundColor: AppColors.success,
        ));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _toggle(TasaIvaModel tasa) async {
    try {
      await _repo.toggleTasaIva(tasa.tasaIvaId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showCrearDialog() {
    final nombreCtrl = TextEditingController();
    final porcCtrl = TextEditingController(text: '12');
    final fechaCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva Tasa IVA', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre (ej: IVA 12%)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: porcCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Porcentaje', suffixText: '%'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fechaCtrl,
                decoration: const InputDecoration(labelText: 'Vigente desde (YYYY-MM-DD)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              final porc   = double.tryParse(porcCtrl.text.trim());
              final fecha  = fechaCtrl.text.trim();
              if (nombre.isEmpty || porc == null || fecha.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Completa todos los campos')),
                );
                return;
              }
              Navigator.pop(ctx);
              await _crear(nombre, porc, fecha);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _crear(String nombre, double porcentaje, String vigentDesde) async {
    try {
      await _repo.crearTasaIva(
        tenantId:    widget.tenantId,
        nombre:      nombre,
        porcentaje:  porcentaje,
        vigentDesde: vigentDesde,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tasa IVA creada'), backgroundColor: AppColors.success),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class _TasaCard extends StatelessWidget {
  final TasaIvaModel tasa;
  final VoidCallback onToggle;
  final VoidCallback onPredeterminada;
  const _TasaCard({
    required this.tasa,
    required this.onToggle,
    required this.onPredeterminada,
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
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.cajeroColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.percent_rounded, color: AppColors.cajeroColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(tasa.nombre,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    if (tasa.predeterminada) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Predeterminada',
                            style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 9.5,
                                fontWeight: FontWeight.w600, color: AppColors.success)),
                      ),
                    ],
                  ],
                ),
                Text('${tasa.porcentaje.toStringAsFixed(0)}%  •  Vigente desde: ${tasa.vigentDesde}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          // La estrella marca cuál heredan los platos sin tarifa propia. Es una
          // decisión aparte de activo/inactivo: con IVA por plato el negocio
          // necesita las dos tarifas activas y solo una como predeterminada.
          if (!tasa.predeterminada)
            IconButton(
              tooltip: 'Usar como predeterminada',
              icon: const Icon(Icons.star_outline_rounded,
                  color: AppColors.textSecondary, size: 22),
              onPressed: onPredeterminada,
            )
          else
            const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.star_rounded, color: AppColors.success, size: 22),
            ),
          Switch(
            value: tasa.activo,
            onChanged: (_) => onToggle(),
            activeColor: AppColors.success,
          ),
        ],
      ),
    );
  }
}
