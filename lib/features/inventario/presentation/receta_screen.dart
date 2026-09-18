import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/inventario_repository.dart';
import '../data/unidades.dart';
import 'inventario_dialogos.dart';

/// Receta de un plato: qué insumos lleva UNA porción, cuánto cuesta y, en esta
/// sucursal, si se descuenta al vender.
///
/// La receta es del plato (igual en todas las sucursales del restaurante); lo
/// que se decide por sucursal es si se descuenta y con qué costo se calcula.
class RecetaScreen extends StatefulWidget {
  final String sucursalId;
  final String platoId;
  final String nombrePlato;

  const RecetaScreen({
    super.key,
    required this.sucursalId,
    required this.platoId,
    required this.nombrePlato,
  });

  @override
  State<RecetaScreen> createState() => _RecetaScreenState();
}

class _Linea {
  final String insumoId;
  final String nombre;
  final String unidad;
  double cantidad;
  final double? costoUnitario;
  _Linea(this.insumoId, this.nombre, this.unidad, this.cantidad, this.costoUnitario);

  double? get costo => costoUnitario == null ? null : costoUnitario! * cantidad;
}

class _RecetaScreenState extends State<RecetaScreen> {
  final _repo = InventarioRepository();

  RecetaModel? _receta;
  final List<_Linea> _lineas = [];
  bool _loading = true;
  bool _guardando = false;
  bool _cambios = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await _repo.getReceta(widget.sucursalId, widget.platoId);
      if (!mounted) return;
      setState(() {
        _aplicar(r);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  void _aplicar(RecetaModel r) {
    _receta = r;
    _lineas
      ..clear()
      ..addAll(r.items.map((i) =>
          _Linea(i.insumoId, i.nombre, i.unidad, i.cantidad, i.costoUnitario)));
    _cambios = false;
  }

  _Linea? _linea(String insumoId) {
    for (final l in _lineas) {
      if (l.insumoId == insumoId) return l;
    }
    return null;
  }

  double get _costo => _lineas.fold(0.0, (s, l) => s + (l.costo ?? 0));
  bool get _costoCompleto => _lineas.every((l) => l.costoUnitario != null);

  Future<void> _agregar() async {
    final ins = await showModalBottomSheet<InsumoModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SelectorInsumoSheet(
        sucursalId: widget.sucursalId,
        repo: _repo,
        yaElegidos: _lineas.map((l) => l.insumoId).toSet(),
      ),
    );
    if (ins == null || !mounted) return;
    final existente = _linea(ins.insumoId);
    final r = await showDialog<CantidadYNota>(
      context: context,
      builder: (_) => CantidadDialog(
        titulo: ins.nombre,
        ayuda: 'Cuánto lleva UNA porción de ${widget.nombrePlato}.',
        unidadBase: ins.unidad,
        etiqueta: 'Cantidad por porción',
        inicialBase: existente?.cantidad,
      ),
    );
    if (r == null) return;
    setState(() {
      if (existente != null) {
        existente.cantidad = r.cantidadBase;
      } else {
        _lineas.add(_Linea(ins.insumoId, ins.nombre, ins.unidad, r.cantidadBase,
            ins.costoPromedio));
      }
      _cambios = true;
    });
  }

  Future<void> _editar(_Linea l) async {
    final r = await showDialog<CantidadYNota>(
      context: context,
      builder: (_) => CantidadDialog(
        titulo: l.nombre,
        ayuda: 'Cuánto lleva UNA porción de ${widget.nombrePlato}.',
        unidadBase: l.unidad,
        etiqueta: 'Cantidad por porción',
        inicialBase: l.cantidad,
      ),
    );
    if (r == null) return;
    setState(() { l.cantidad = r.cantidadBase; _cambios = true; });
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final r = await _repo.guardarReceta(widget.sucursalId, widget.platoId,
          {for (final l in _lineas) l.insumoId: l.cantidad});
      if (!mounted) return;
      setState(() { _aplicar(r); _guardando = false; });
      mostrarOk(context, 'Receta guardada');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarError(context, e);
    }
  }

  /// Enciende o apaga el descuento de la receta al vender, en esta sucursal.
  Future<void> _cambiarDescuento(bool activar) async {
    final spId = _receta?.sucursalPlatoId;
    if (spId == null) return;
    if (activar && _receta?.modoInventario == 'UNIDADES') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cambiar a receta',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
          content: const Text(
              'Este plato hoy se cuenta por unidades. Al pasarlo a receta se deja de '
              'contar el plato y se descuentan sus insumos; el stock por unidades se borra.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cambiar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _repo.configurar(spId, modo: activar ? 'RECETA' : 'SIN_CONTROL');
      await _load();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<bool> _confirmarSalida() async {
    if (!_cambios) return true;
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin guardar?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text('Los cambios de la receta se perderán.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir editando')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
        ],
      ),
    );
    return salir == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_cambios,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmarSalida()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text('Receta · ${widget.nombrePlato}')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontFamily: 'Poppins', color: AppColors.textSecondary)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reintentar')),
                          ],
                        ),
                      ),
                    )
                  : _buildBody(),
        ),
        bottomNavigationBar: _loading || _error != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _agregar,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar insumo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _cambios && !_guardando ? _guardar : null,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_outlined),
                          label: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBody() {
    final r = _receta!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCosto(r),
        const SizedBox(height: 12),
        _buildDescuento(r),
        const SizedBox(height: 16),
        Text('Ingredientes por porción',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_lineas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Esta receta está vacía.\nAgrega los insumos que lleva una porción: '
              'por ejemplo 320 g de carne y 150 g de papas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins', color: AppColors.textSecondary, height: 1.5),
            ),
          )
        else
          ..._lineas.map(_buildLinea),
      ],
    );
  }

  Widget _buildCosto(RecetaModel r) {
    final costo = _costo;
    final precio = r.precio;
    final margen = precio != null && precio > 0 && _lineas.isNotEmpty
        ? (precio - costo) / precio * 100
        : null;
    final colorMargen = margen == null
        ? AppColors.textSecondary
        : margen < 30
            ? AppColors.error
            : margen < 55
                ? AppColors.warning
                : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _dato('Precio', precio == null ? '—' : '\$${precio.toStringAsFixed(2)}',
                  AppColors.textPrimary),
              _dato('Costo por porción', '\$${costo.toStringAsFixed(2)}', AppColors.primary),
              _dato('Margen', margen == null ? '—' : '${margen.toStringAsFixed(1)} %', colorMargen),
            ],
          ),
          if (_lineas.isNotEmpty && !_costoCompleto) ...[
            const SizedBox(height: 10),
            Text(
              'Costo incompleto: ${_lineas.where((l) => l.costoUnitario == null).map((l) => l.nombre).join(', ')} '
              'todavía no tiene compras registradas en esta sucursal.',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.warning, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
          Text(valor,
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18, color: color)),
        ],
      );

  Widget _buildDescuento(RecetaModel r) {
    if (r.sucursalPlatoId == null) {
      return const Text(
        'Este plato no está asignado a esta sucursal: la receta se guarda, pero aquí no se descuenta.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
        value: r.seDescuenta,
        activeColor: AppColors.success,
        title: const Text('Descontar insumos al vender',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: const Text(
            'En esta sucursal. Nunca bloquea la venta: si un insumo no alcanza, '
            'queda en negativo y te avisa.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
        onChanged: _cambios ? null : _cambiarDescuento,
      ),
    );
  }

  Widget _buildLinea(_Linea l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => _editar(l),
        title: Text(l.nombre,
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          l.costo == null
              ? '${Unidades.formato(l.cantidad, l.unidad)} · sin costo'
              : '${Unidades.formato(l.cantidad, l.unidad)} · \$${l.costo!.toStringAsFixed(2)}',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
        ),
        trailing: IconButton(
          tooltip: 'Quitar',
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => setState(() { _lineas.remove(l); _cambios = true; }),
        ),
      ),
    );
  }
}
