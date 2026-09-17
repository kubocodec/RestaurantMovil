import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/inventario_repository.dart';

/// Inventario de la sucursal: lo que tiene control de stock, con lo agotado y
/// lo que está por agotarse arriba de todo.
///
/// Solo aparece si el restaurante tiene el control de inventario activado; los
/// negocios que no llevan inventario nunca ven esta pantalla.
class InventarioScreen extends StatefulWidget {
  final String sucursalId;
  const InventarioScreen({super.key, required this.sucursalId});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  final _repo = InventarioRepository();

  List<InventarioItemModel> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _repo.getInventario(widget.sucursalId);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  List<InventarioItemModel> get _agotados => _items.where((i) => i.agotado).toList();
  List<InventarioItemModel> get _bajos => _items.where((i) => i.bajoMinimo).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.textHint),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Todavía no hay platos con control de stock.\n\n'
                'Actívalo plato por plato desde Configuración → Menú, '
                'en los que necesites contar (cervezas, botellas, porciones armadas).',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_agotados.isNotEmpty || _bajos.isNotEmpty) ...[
            _buildResumen(),
            const SizedBox(height: 16),
          ],
          ..._items.map(_buildItem),
        ],
      ),
    );
  }

  Widget _buildResumen() {
    final agotados = _agotados.length;
    final bajos = _bajos.length;
    final color = agotados > 0 ? AppColors.error : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(agotados > 0 ? Icons.error_outline : Icons.warning_amber_rounded,
              color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (agotados > 0)
                  Text('$agotados sin stock',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 15, color: color)),
                if (bajos > 0)
                  Text('$bajos por agotarse',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13,
                          color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(InventarioItemModel item) {
    final color = item.agotado
        ? AppColors.error
        : item.bajoMinimo
            ? AppColors.warning
            : AppColors.success;
    final unidad = item.unidad?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombrePlato,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                            fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      item.stockMinimo == null
                          ? item.categoria
                          : '${item.categoria}  ·  mínimo ${item.minimoTexto}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 11.5,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(item.stockTexto,
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          fontSize: 22, color: color)),
                  if (unidad != null && unidad.isNotEmpty)
                    Text(unidad,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _dialogoIngreso(item),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ingreso'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _dialogoAjuste(item),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Ajuste'),
                ),
              ),
              IconButton(
                tooltip: 'Historial',
                icon: const Icon(Icons.history, color: AppColors.textSecondary),
                onPressed: () => _verHistorial(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------

  Future<void> _dialogoIngreso(InventarioItemModel item) async {
    final resultado = await _pedirNumero(
      titulo: 'Ingreso de ${item.nombrePlato}',
      ayuda: 'Llegó mercadería o se armaron porciones. Se suma a las '
             '${item.stockTexto} que hay.',
      etiqueta: 'Cantidad que entra',
      etiquetaNota: 'Nota (opcional): proveedor, factura…',
    );
    if (resultado == null) return;
    await _ejecutar(() => _repo.ingresar(item.sucursalPlatoId,
        cantidad: resultado.valor, nota: resultado.nota));
  }

  Future<void> _dialogoAjuste(InventarioItemModel item) async {
    final resultado = await _pedirNumero(
      titulo: 'Ajuste de ${item.nombrePlato}',
      ayuda: 'Cuenta lo que hay físicamente y escríbelo aquí. El sistema tiene '
             '${item.stockTexto}; la diferencia queda registrada en el historial.',
      etiqueta: 'Stock real contado',
      etiquetaNota: 'Motivo (opcional): merma, consumo interno…',
      inicial: item.stock,
    );
    if (resultado == null) return;
    await _ejecutar(() => _repo.ajustar(item.sucursalPlatoId,
        stock: resultado.valor, nota: resultado.nota));
  }

  Future<void> _ejecutar(Future<InventarioItemModel> Function() accion) async {
    try {
      await accion();
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ApiClient.parseError(e)),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<_NumeroYNota?> _pedirNumero({
    required String titulo,
    required String ayuda,
    required String etiqueta,
    required String etiquetaNota,
    double? inicial,
  }) {
    final ctrl = TextEditingController(
      text: inicial == null
          ? ''
          : (inicial == inicial.roundToDouble()
              ? inicial.round().toString()
              : inicial.toString()),
    );
    final notaCtrl = TextEditingController();
    return showDialog<_NumeroYNota>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo,
            style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ayuda,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12.5,
                      color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700),
                decoration: InputDecoration(labelText: etiqueta, isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notaCtrl,
                decoration: InputDecoration(labelText: etiquetaNota, isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final valor = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (valor == null) return;
              Navigator.pop(ctx, _NumeroYNota(valor, notaCtrl.text.trim()));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _verHistorial(InventarioItemModel item) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _HistorialSheet(item: item, repo: _repo),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Poppins', color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumeroYNota {
  final double valor;
  final String nota;
  const _NumeroYNota(this.valor, this.nota);
}

/// Historial de un plato: de dónde salió y a dónde fue cada unidad.
class _HistorialSheet extends StatefulWidget {
  final InventarioItemModel item;
  final InventarioRepository repo;
  const _HistorialSheet({required this.item, required this.repo});

  @override
  State<_HistorialSheet> createState() => _HistorialSheetState();
}

class _HistorialSheetState extends State<_HistorialSheet> {
  List<MovimientoInventarioModel> _movs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final movs = await widget.repo.getMovimientos(widget.item.sucursalPlatoId);
      if (!mounted) return;
      setState(() { _movs = movs; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  ({String etiqueta, Color color, IconData icono}) _estilo(String tipo) {
    switch (tipo) {
      case 'INGRESO':   return (etiqueta: 'Ingreso',   color: AppColors.success, icono: Icons.add);
      case 'VENTA':     return (etiqueta: 'Venta',     color: AppColors.primary, icono: Icons.point_of_sale_outlined);
      case 'ANULACION': return (etiqueta: 'Anulación', color: AppColors.info,    icono: Icons.undo);
      default:          return (etiqueta: 'Ajuste',    color: AppColors.warning, icono: Icons.fact_check_outlined);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Historial · ${widget.item.nombrePlato}',
                style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', color: AppColors.textSecondary)),
                        ),
                      )
                    : _movs.isEmpty
                        ? const Center(
                            child: Text('Todavía no hay movimientos',
                                style: TextStyle(
                                    fontFamily: 'Poppins', color: AppColors.textSecondary)))
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _movs.length,
                            itemBuilder: (_, i) {
                              final m = _movs[i];
                              final e = _estilo(m.tipo);
                              final signo = m.cantidad > 0 ? '+' : '';
                              final cant = m.cantidad == m.cantidad.roundToDouble()
                                  ? m.cantidad.round().toString()
                                  : m.cantidad.toStringAsFixed(3);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackground,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(e.icono, color: e.color, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.numeroOrden != null
                                                ? '${e.etiqueta} · orden #${m.numeroOrden}'
                                                : e.etiqueta,
                                            style: const TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          Text(
                                            '${DateFormat('d MMM · HH:mm', 'es').format(m.fecha.toLocal())}'
                                            '${m.usuario != null ? ' · ${m.usuario}' : ''}',
                                            style: const TextStyle(
                                                fontFamily: 'Poppins', fontSize: 11,
                                                color: AppColors.textSecondary),
                                          ),
                                          if (m.nota != null && m.nota!.isNotEmpty)
                                            Text(m.nota!,
                                                style: const TextStyle(
                                                    fontFamily: 'Poppins', fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                    color: AppColors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('$signo$cant',
                                            style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15, color: e.color)),
                                        Text('queda ${m.stockResultante == m.stockResultante.roundToDouble() ? m.stockResultante.round() : m.stockResultante}',
                                            style: const TextStyle(
                                                fontFamily: 'Poppins', fontSize: 10.5,
                                                color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
