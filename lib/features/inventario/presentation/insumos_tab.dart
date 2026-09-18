import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/inventario_repository.dart';
import '../data/unidades.dart';
import 'inventario_dialogos.dart';

/// Insumos de la sucursal: cuánto hay, cuánto vale y qué está por acabarse.
/// Lo que está en negativo va primero: es la señal de que falta registrar
/// una compra o hacer un conteo.
class InsumosTab extends StatefulWidget {
  final String sucursalId;
  final InventarioRepository repo;
  const InsumosTab({super.key, required this.sucursalId, required this.repo});

  @override
  State<InsumosTab> createState() => _InsumosTabState();
}

class _InsumosTabState extends State<InsumosTab> with AutomaticKeepAliveClientMixin {
  final _buscar = TextEditingController();
  List<InsumoModel> _insumos = [];
  bool _loading = true;
  bool _verInactivos = false;
  String _filtro = '';
  String? _error;

  InventarioRepository get _repo => widget.repo;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final lista = await _repo.getInsumos(widget.sucursalId, incluirInactivos: _verInactivos);
      if (!mounted) return;
      setState(() { _insumos = lista; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  List<InsumoModel> get _ordenados {
    int peso(InsumoModel i) => !i.activo ? 3 : i.negativo ? 0 : i.bajoMinimo ? 1 : 2;
    final lista = _filtro.isEmpty
        ? [..._insumos]
        : _insumos.where((i) => i.nombre.toLowerCase().contains(_filtro)).toList();
    lista.sort((a, b) {
      final p = peso(a).compareTo(peso(b));
      return p != 0 ? p : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return lista;
  }

  Future<void> _nuevo() async {
    final form = await showDialog<InsumoForm>(
        context: context, builder: (_) => const InsumoDialog());
    if (form == null) return;
    await _ejecutar(() => _repo.guardarInsumo(widget.sucursalId,
        nombre: form.nombre, unidad: form.unidad,
        categoria: form.categoria, stockMinimo: form.stockMinimo));
  }

  Future<void> _editar(InsumoModel i) async {
    final form = await showDialog<InsumoForm>(
        context: context, builder: (_) => InsumoDialog(insumo: i));
    if (form == null) return;
    await _ejecutar(() => _repo.guardarInsumo(widget.sucursalId,
        insumoId: i.insumoId, nombre: form.nombre, unidad: form.unidad,
        categoria: form.categoria, stockMinimo: form.stockMinimo));
  }

  Future<void> _conteo(InsumoModel i) async {
    final r = await showDialog<CantidadYNota>(
      context: context,
      builder: (_) => CantidadDialog(
        titulo: 'Conteo de ${i.nombre}',
        ayuda: 'Pesa o cuenta lo que hay físicamente y escríbelo. El sistema tiene '
            '${Unidades.formato(i.stock, i.unidad)}; la diferencia queda en el historial.',
        unidadBase: i.unidad,
        etiqueta: 'Cantidad real',
        etiquetaNota: 'Nota (opcional)',
        permitirCero: true,
      ),
    );
    if (r == null) return;
    await _ejecutar(() => _repo.ajustarInsumo(widget.sucursalId, i.insumoId,
        stock: r.cantidadBase, nota: r.nota));
  }

  Future<void> _merma(InsumoModel i) async {
    final r = await showDialog<CantidadYNota>(
      context: context,
      builder: (_) => CantidadDialog(
        titulo: 'Merma de ${i.nombre}',
        ayuda: 'Lo que salió sin venderse: se dañó, se botó o lo consumió el personal.',
        unidadBase: i.unidad,
        etiqueta: 'Cantidad',
        etiquetaNota: 'Motivo (obligatorio)',
        notaObligatoria: true,
      ),
    );
    if (r == null) return;
    await _ejecutar(() => _repo.registrarMerma(widget.sucursalId, i.insumoId,
        cantidad: r.cantidadBase, motivo: r.nota));
  }

  Future<void> _cambiarEstado(InsumoModel i) async {
    await _ejecutar(() => _repo.cambiarEstadoInsumo(widget.sucursalId, i.insumoId, !i.activo));
  }

  void _historial(InsumoModel i) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => HistorialSheet(
        titulo: i.nombre,
        cargar: () => _repo.getMovimientosInsumo(widget.sucursalId, i.insumoId),
        formatear: (c) => Unidades.formato(c, i.unidad),
      ),
    );
  }

  Future<void> _ejecutar(Future<Object?> Function() accion) async {
    try {
      await accion();
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nuevo-insumo',
        onPressed: _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Insumo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _ErrorReintentar(mensaje: _error!, onReintentar: _load)
              : _buildLista(),
    );
  }

  Widget _buildLista() {
    final lista = _ordenados;
    final negativos = _insumos.where((i) => i.activo && i.negativo).length;
    final bajos = _insumos.where((i) => i.activo && !i.negativo && i.bajoMinimo).length;
    final valor = _insumos.where((i) => i.activo).fold(0.0, (s, i) => s + i.valorStock);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          TextField(
            controller: _buscar,
            decoration: const InputDecoration(
                hintText: 'Buscar insumo...', prefixIcon: Icon(Icons.search), isDense: true),
            onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Resumen(texto: 'Inventario: \$${valor.toStringAsFixed(2)}', color: AppColors.primary),
              if (negativos > 0) _Resumen(texto: '$negativos en negativo', color: AppColors.error),
              if (bajos > 0) _Resumen(texto: '$bajos por reponer', color: AppColors.warning),
              FilterChip(
                label: const Text('Ver desactivados'),
                selected: _verInactivos,
                labelStyle: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                onSelected: (v) {
                  setState(() => _verInactivos = v);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_insumos.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Text(
                'Todavía no hay insumos.\n\nCrea los ingredientes que quieres controlar '
                '(carne, papas, aceite…), arma la receta de cada plato desde '
                'Configuración → Menú y registra tus compras para tener el costo real.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Poppins', color: AppColors.textSecondary, height: 1.5),
              ),
            )
          else
            ...lista.map(_buildItem),
        ],
      ),
    );
  }

  Widget _buildItem(InsumoModel i) {
    final color = !i.activo
        ? AppColors.textHint
        : i.negativo
            ? AppColors.error
            : i.bajoMinimo
                ? AppColors.warning
                : AppColors.success;
    final detalle = [
      if (i.categoria != null) i.categoria!,
      Unidades.costo(i.costoPromedio, i.unidad),
      if (i.stockMinimo != null) 'mínimo ${Unidades.formato(i.stockMinimo, i.unidad)}',
      if (!i.activo) 'desactivado',
    ].join('  ·  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _historial(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.nombre,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                            fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(detalle,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11.5,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Unidades.formato(i.stock, i.unidad),
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 17, color: color)),
                  if (i.valorStock > 0)
                    Text('\$${i.valorStock.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: AppColors.textSecondary)),
                ],
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (v) {
                  switch (v) {
                    case 'conteo':    _conteo(i); break;
                    case 'merma':     _merma(i); break;
                    case 'historial': _historial(i); break;
                    case 'editar':    _editar(i); break;
                    case 'estado':    _cambiarEstado(i); break;
                  }
                },
                itemBuilder: (_) => [
                  if (i.activo) ...[
                    const PopupMenuItem(value: 'conteo', child: Text('Conteo físico')),
                    const PopupMenuItem(value: 'merma', child: Text('Registrar merma')),
                  ],
                  const PopupMenuItem(value: 'historial', child: Text('Historial')),
                  const PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(
                      value: 'estado', child: Text(i.activo ? 'Desactivar' : 'Activar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  final String texto;
  final Color color;
  const _Resumen({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(texto,
          style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _ErrorReintentar extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;
  const _ErrorReintentar({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
