import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/orden_model.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../features/ordenes/data/ordenes_repository.dart';

class _DetalleFlat {
  final String detalleId;
  final String mesaNombre;
  final String platoNombre;
  final int cantidad;
  final String estado;
  final String? notas;

  const _DetalleFlat({
    required this.detalleId,
    required this.mesaNombre,
    required this.platoNombre,
    required this.cantidad,
    required this.estado,
    this.notas,
  });

  factory _DetalleFlat.from(DetalleOrdenModel d, OrdenModel o) => _DetalleFlat(
    detalleId:   d.ordenDetalleId,
    mesaNombre:  o.numeroMesa,
    platoNombre: d.nombrePlato,
    cantidad:    d.cantidad,
    estado:      d.estado,
    notas:       d.observaciones,
  );

  bool get isPendiente     => estado == 'PENDIENTE' || estado == 'ENVIADO';
  bool get isEnPreparacion => estado == 'EN_PREPARACION';
  bool get isListo         => estado == 'LISTO';
}

class _OrdenFlat {
  final String mesaNombre;
  final List<_DetalleFlat> detalles;
  const _OrdenFlat({required this.mesaNombre, required this.detalles});
}

class CocinaScreen extends StatefulWidget {
  const CocinaScreen({super.key});

  @override
  State<CocinaScreen> createState() => _CocinaScreenState();
}

class _CocinaScreenState extends State<CocinaScreen> with SingleTickerProviderStateMixin {
  final _repo = OrdenesRepository();
  List<_DetalleFlat> _todos = [];
  List<_OrdenFlat> _ordenesParaListos = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    try {
      final ordenes = await _repo.getOrdenesActivas(_sucursalId);
      final todos = <_DetalleFlat>[];
      final listaListos = <_OrdenFlat>[];

      for (final o in ordenes) {
        final detalles = o.detalles.map((d) => _DetalleFlat.from(d, o)).toList();
        final activos = detalles.where((d) => !d.isListo && d.estado != 'ENTREGADO' && d.estado != 'CANCELADO').toList();
        final listos  = detalles.where((d) => d.isListo).toList();
        todos.addAll(activos);
        if (listos.isNotEmpty) {
          listaListos.add(_OrdenFlat(mesaNombre: o.numeroMesa, detalles: listos));
        }
      }

      if (mounted) {
        setState(() {
          _todos = todos;
          _ordenesParaListos = listaListos;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _cambiarEstado(_DetalleFlat detalle, String nuevoEstado) async {
    try {
      await _repo.cambiarEstadoDetalle(detalle.detalleId, nuevoEstado);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nuevoEstado == 'EN_PREPARACION' ? '¡En preparación!' : '¡Plato listo!'),
          backgroundColor: nuevoEstado == 'EN_PREPARACION' ? AppColors.estadoEnProceso : AppColors.estadoListo,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<_DetalleFlat> get _pendientes     => _todos.where((d) => d.isPendiente).toList();
  List<_DetalleFlat> get _enPreparacion  => _todos.where((d) => d.isEnPreparacion).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cocineroColor,
        title: const Text('Cocina'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Pendientes (${_pendientes.length})'),
            Tab(text: 'En prep. (${_enPreparacion.length})'),
            const Tab(text: 'Listos'),
          ],
        ),
      ),
      body: _loading && _todos.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.cocineroColor))
          : _error != null && _todos.isEmpty
              ? _buildError()
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildList(_pendientes, 'Iniciar', AppColors.estadoEnProceso, Icons.play_arrow_rounded, 'EN_PREPARACION'),
                    _buildList(_enPreparacion, 'Listo', AppColors.estadoListo, Icons.done_rounded, 'LISTO'),
                    _buildListosList(),
                  ],
                ),
    );
  }

  Widget _buildList(List<_DetalleFlat> detalles, String action, Color color, IconData icon, String nuevoEstado) {
    if (detalles.isEmpty) {
      return _buildEmpty(
        action == 'Iniciar' ? 'No hay pedidos pendientes' : 'No hay platos en preparación',
        action == 'Iniciar' ? Icons.check_circle_outline : Icons.kitchen_outlined,
        action == 'Iniciar' ? AppColors.success : AppColors.textHint,
      );
    }
    return RefreshIndicator(
      color: AppColors.cocineroColor,
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        itemCount: detalles.length,
        itemBuilder: (_, i) => _DetalleCard(
          detalle: detalles[i],
          primaryAction: action,
          primaryColor: color,
          primaryIcon: icon,
          onPrimaryAction: () => _cambiarEstado(detalles[i], nuevoEstado),
        ),
      ),
    );
  }

  Widget _buildListosList() {
    if (_ordenesParaListos.isEmpty) {
      return _buildEmpty('No hay platos listos en este momento', Icons.restaurant_outlined, AppColors.textHint);
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      itemCount: _ordenesParaListos.length,
      itemBuilder: (_, i) {
        final orden = _ordenesParaListos[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.estadoListo.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.estadoListo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.estadoListo, size: 14),
                      const SizedBox(width: 4),
                      Text(orden.mesaNombre, style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        color: AppColors.estadoListo, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              ...orden.detalles.map((d) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check, color: AppColors.estadoListo, size: 16),
                    const SizedBox(width: 8),
                    Text('${d.cantidad}x ${d.platoNombre}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                  ],
                ),
              )),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Poppins')),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _buildEmpty(String msg, IconData icon, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: color.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(msg, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 15)),
        ],
      ),
    );
  }
}

class _DetalleCard extends StatelessWidget {
  final _DetalleFlat detalle;
  final String primaryAction;
  final Color primaryColor;
  final IconData primaryIcon;
  final VoidCallback onPrimaryAction;

  const _DetalleCard({
    required this.detalle,
    required this.primaryAction,
    required this.primaryColor,
    required this.primaryIcon,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text('×${detalle.cantidad}',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: primaryColor, fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detalle.platoNombre,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                Row(
                  children: [
                    const Icon(Icons.table_restaurant_outlined, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(detalle.mesaNombre,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                if (detalle.notas != null && detalle.notas!.isNotEmpty)
                  Text('Nota: ${detalle.notas}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.warning, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onPrimaryAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
            icon: Icon(primaryIcon, size: 16),
            label: Text(primaryAction,
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
