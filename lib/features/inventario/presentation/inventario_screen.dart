import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/inventario_repository.dart';
import 'compras_tab.dart';
import 'insumos_tab.dart';
import 'inventario_dialogos.dart';
import 'receta_screen.dart';

/// Inventario de la sucursal, en dos niveles que conviven:
/// - Insumos: lo que se descuenta por receta (gramos de carne, ml de aceite),
///   con sus compras y proveedores.
/// - Platos por unidades: cervezas, botellas, porciones armadas.
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Inventario'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Insumos'),
              Tab(text: 'Platos'),
              Tab(text: 'Compras'),
              Tab(text: 'Proveedores'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              InsumosTab(sucursalId: widget.sucursalId, repo: _repo),
              _PlatosTab(sucursalId: widget.sucursalId, repo: _repo),
              ComprasTab(sucursalId: widget.sucursalId, repo: _repo),
              ProveedoresTab(sucursalId: widget.sucursalId, repo: _repo),
            ],
          ),
        ),
      ),
    );
  }
}

/// Platos con control: los que se cuentan por unidades (con ingreso y ajuste)
/// y, aparte, los que descuentan insumos por receta.
class _PlatosTab extends StatefulWidget {
  final String sucursalId;
  final InventarioRepository repo;
  const _PlatosTab({required this.sucursalId, required this.repo});

  @override
  State<_PlatosTab> createState() => _PlatosTabState();
}

class _PlatosTabState extends State<_PlatosTab> with AutomaticKeepAliveClientMixin {
  InventarioRepository get _repo => widget.repo;

  @override
  bool get wantKeepAlive => true;

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

  List<InventarioItemModel> get _porUnidades =>
      _items.where((i) => i.modoInventario == 'UNIDADES').toList();
  List<InventarioItemModel> get _conReceta =>
      _items.where((i) => i.modoInventario == 'RECETA').toList();
  List<InventarioItemModel> get _agotados => _porUnidades.where((i) => i.agotado).toList();
  List<InventarioItemModel> get _bajos => _porUnidades.where((i) => i.bajoMinimo).toList();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _error != null
            ? _buildError()
            : _buildBody();
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
                'Desde Configuración → Menú, en cada plato: cuéntalo por unidades '
                '(cervezas, botellas, porciones armadas) o arma su receta para que '
                'descuente insumos.',
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
          ..._porUnidades.map(_buildItem),
          if (_conReceta.isNotEmpty) ...[
            if (_porUnidades.isNotEmpty) const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Descuentan insumos por receta',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
            ..._conReceta.map(_buildReceta),
          ],
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

  Widget _buildReceta(InventarioItemModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined, color: AppColors.earth2),
        title: Text(item.nombrePlato,
            style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(item.categoria,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RecetaScreen(
              sucursalId: widget.sucursalId,
              platoId: item.platoId,
              nombrePlato: item.nombrePlato,
            ),
          ));
          if (mounted) _load();
        },
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
      builder: (_) => HistorialSheet(
        titulo: item.nombrePlato,
        cargar: () => _repo.getMovimientos(item.sucursalPlatoId),
        formatear: (c) => c == c.roundToDouble() ? c.round().toString() : c.toStringAsFixed(3),
      ),
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
