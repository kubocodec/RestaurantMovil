import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/mesa_model.dart';
import '../../../core/models/salon_model.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../data/mesas_repository.dart';

class MesasScreen extends StatefulWidget {
  const MesasScreen({super.key});
  @override
  State<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends State<MesasScreen> with TickerProviderStateMixin {
  final _repo = MesasRepository();
  List<SalonModel> _salones = [];
  List<MesaModel> _todasMesas = [];
  bool _loading = true;
  String? _error;
  late TabController _tabCtrl;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 1, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // El estado de las mesas cambia desde otros dispositivos (mesero,
    // cajero): refrescar en silencio sin esperar al pull-to-refresh.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshSilencioso());
  }

  @override
  void dispose() { _timer?.cancel(); _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _fetch();
      if (mounted) setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('MesasScreen._load error: $e\n$st');
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  /// Igual que _load pero sin spinner ni error: para el refresco periódico.
  Future<void> _refreshSilencioso() async {
    if (_loading) return;
    try { await _fetch(); } catch (_) {}
  }

  Future<void> _fetch() async {
    final sid = _sucursalId;
    if (sid.isEmpty) throw Exception('Sin sucursal asignada');
    // En paralelo: la pantalla carga en un viaje de red, no en dos
    final resultados = await Future.wait([
      _repo.getSalonesBySucursal(sid),
      _repo.getMesasBySucursal(sid),
    ]);
    final salones = resultados[0] as List<SalonModel>;
    final mesas   = resultados[1] as List<MesaModel>;
    if (!mounted) return;
    final len = salones.isEmpty ? 1 : salones.length + 1;
    // Conservar la pestaña seleccionada: solo recrear si cambió el número
    if (len != _tabCtrl.length) {
      final anterior = _tabCtrl;
      _tabCtrl = TabController(
        length: len, vsync: this,
        initialIndex: anterior.index.clamp(0, len - 1),
      );
      anterior.dispose();
    }
    setState(() {
      _salones    = salones;
      _todasMesas = mesas;
    });
  }

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  List<MesaModel> _mesasDelTab(int index) {
    if (index == 0) return _todasMesas;
    final salon = _salones[index - 1];
    return _todasMesas.where((m) => m.salonId == salon.salonId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mesas'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: _salones.isEmpty ? null : TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            const Tab(text: 'Todas'),
            ..._salones.map((s) => Tab(text: s.nombre)),
          ],
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? _ErrorView(error: _error!, onRetry: _load)
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_todasMesas.isEmpty) {
      return const Center(child: Text('No hay mesas configuradas', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)));
    }
    return TabBarView(
      controller: _tabCtrl,
      children: List.generate(
        _salones.isEmpty ? 1 : _salones.length + 1,
        (i) => _MesasGrid(mesas: _mesasDelTab(i), onTap: _onMesaTap, onRefresh: _load),
      ),
    );
  }

  Future<void> _onMesaTap(MesaModel mesa) async {
    if (mesa.isMantenimiento) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesa ${mesa.numeroMesa} en mantenimiento'), backgroundColor: AppColors.warning),
      );
      return;
    }
    await context.push('/mesero/orden/${mesa.mesaId}?nombre=${Uri.encodeComponent(mesa.numeroMesa)}&libre=${mesa.isLibre}');
    if (mounted) _load(); // refleja el nuevo estado de la mesa al volver
  }
}

// ── Grid de mesas ────────────────────────────────────────────────────────────
class _MesasGrid extends StatelessWidget {
  final List<MesaModel> mesas;
  final Future<void> Function(MesaModel) onTap;
  final Future<void> Function() onRefresh;

  const _MesasGrid({required this.mesas, required this.onTap, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final libres    = mesas.where((m) => m.isLibre).length;
    final ocupadas  = mesas.where((m) => m.isOcupada).length;
    final reservadas = mesas.where((m) => m.isReservada).length;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Wrap(
                spacing: 12,
                children: [
                  _LegendDot(color: AppColors.mesaLibre,     label: 'Libres ($libres)'),
                  _LegendDot(color: AppColors.mesaOcupada,   label: 'Ocupadas ($ocupadas)'),
                  _LegendDot(color: AppColors.mesaReservada, label: 'Reservadas ($reservadas)'),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _MesaCard(mesa: mesas[i], onTap: () => onTap(mesas[i])),
                childCount: mesas.length,
              ),
              // Columnas según el ancho disponible (responsive)
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MesaCard extends StatelessWidget {
  final MesaModel mesa;
  final VoidCallback onTap;
  const _MesaCard({required this.mesa, required this.onTap});

  Color get _color {
    switch (mesa.estado) {
      case 'LIBRE':         return AppColors.mesaLibre;
      case 'OCUPADA':       return AppColors.mesaOcupada;
      case 'RESERVADA':     return AppColors.mesaReservada;
      default:              return AppColors.mesaMantenimiento;
    }
  }

  IconData get _icon {
    switch (mesa.estado) {
      case 'LIBRE':     return Icons.table_restaurant_outlined;
      case 'OCUPADA':   return Icons.people_alt_outlined;
      case 'RESERVADA': return Icons.event_seat_outlined;
      default:          return Icons.build_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _color, width: 1.5),
          boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon, color: _color, size: 26),
            const SizedBox(height: 5),
            Text(mesa.numeroMesa, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: _color),
              overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.person_outline, size: 11, color: _color),
              const SizedBox(width: 2),
              Text('${mesa.capacidad}', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: _color)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
    ],
  );
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off, size: 64, color: AppColors.textHint),
        const SizedBox(height: 16),
        Text(error, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
      ]),
    ),
  );
}
