import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/network/api_client.dart';
import '../../inventario/data/inventario_repository.dart';
import '../data/configuracion_repository.dart';

class MenuConfigScreen extends StatefulWidget {
  final String sucursalId;
  final String restaurantId;
  /// Tenant del restaurante que se está configurando. Viaja explícito porque
  /// el superadmin configura restaurantes que NO son su propio tenant: sacarlo
  /// del usuario logueado devolvía las tarifas equivocadas (o ninguna).
  final String tenantId;

  const MenuConfigScreen({
    super.key,
    required this.sucursalId,
    required this.restaurantId,
    required this.tenantId,
  });

  @override
  State<MenuConfigScreen> createState() => _MenuConfigScreenState();
}

class _MenuConfigScreenState extends State<MenuConfigScreen> with SingleTickerProviderStateMixin {
  final _repo = ConfiguracionRepository();
  late final TabController _tabs;

  List<CategoriaModel> _categorias = [];
  List<PlatoModel> _platosSucursal = [];
  bool _loadingCat = true;
  bool _loadingPlatos = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadCategorias();
    _loadPlatosSucursal();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadCategorias() async {
    try {
      setState(() => _loadingCat = true);
      final cats = await _repo.getCategorias(widget.restaurantId);
      setState(() { _categorias = cats; _loadingCat = false; });
    } catch (_) {
      setState(() => _loadingCat = false);
    }
  }

  Future<void> _loadPlatosSucursal() async {
    try {
      setState(() => _loadingPlatos = true);
      final platos = await _repo.getPlatosSucursal(widget.sucursalId);
      setState(() { _platosSucursal = platos; _loadingPlatos = false; });
    } catch (_) {
      setState(() => _loadingPlatos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Menú'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Categorías y Platos', icon: Icon(Icons.restaurant_menu_outlined, size: 18)),
            Tab(text: 'Platos en sucursal', icon: Icon(Icons.price_check_outlined, size: 18)),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
        controller: _tabs,
        children: [
          _CategoriasTab(
            categorias:   _categorias,
            loading:      _loadingCat,
            repo:         _repo,
            restaurantId: widget.restaurantId,
            sucursalId:   widget.sucursalId,
            tenantId:     widget.tenantId,
            // Plato asignado en esta sucursal (precio incluido), por platoId
            asignados:    {for (final p in _platosSucursal) p.platoId: p},
            onChanged:    () { _loadCategorias(); _loadPlatosSucursal(); },
          ),
          _PlatosSucursalTab(
            platos:     _platosSucursal,
            loading:    _loadingPlatos,
            repo:       _repo,
            sucursalId: widget.sucursalId,
            onChanged:  _loadPlatosSucursal,
          ),
        ],
        ),
      ),
    );
  }
}

// ─── TAB 1: CATEGORÍAS ──────────────────────────────────────────────────────

class _CategoriasTab extends StatefulWidget {
  final List<CategoriaModel> categorias;
  final bool loading;
  final ConfiguracionRepository repo;
  final String restaurantId;
  final String sucursalId;
  final String tenantId;
  final Map<String, PlatoModel> asignados;
  final VoidCallback onChanged;

  const _CategoriasTab({
    required this.categorias,
    required this.loading,
    required this.repo,
    required this.restaurantId,
    required this.sucursalId,
    required this.tenantId,
    required this.asignados,
    required this.onChanged,
  });

  @override
  State<_CategoriasTab> createState() => _CategoriasTabState();
}

class _CategoriasTabState extends State<_CategoriasTab> {
  ConfiguracionRepository get repo => widget.repo;
  String get restaurantId => widget.restaurantId;
  VoidCallback get onChanged => widget.onChanged;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator());

    final visibles = _busqueda.isEmpty
        ? widget.categorias
        : widget.categorias
            .where((c) => c.nombre.toLowerCase().contains(_busqueda))
            .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'cat_fab',
        onPressed: () => _showCrearCatDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva categoría'),
      ),
      body: widget.categorias.isEmpty
          ? _empty(context)
          : Column(
              children: [
                _BusquedaField(
                  controller: _busquedaCtrl,
                  hint: 'Buscar categoría...',
                  onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
                ),
                Expanded(
                  child: visibles.isEmpty
                      ? _sinResultados()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: visibles.length,
                          itemBuilder: (_, i) => _CategoriaExpansion(
                            categoria:  visibles[i],
                            repo:       repo,
                            sucursalId: widget.sucursalId,
                            tenantId:   widget.tenantId,
                            asignados:  widget.asignados,
                            onChanged:  widget.onChanged,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _sinResultados() => Center(
    child: Text('Sin resultados para "$_busqueda"',
      style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13)),
  );

  Widget _empty(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.category_outlined, size: 64, color: AppColors.cocineroColor.withOpacity(0.4)),
        const SizedBox(height: 16),
        const Text('Sin categorías', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        const Text('Crea categorías para organizar el menú', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(onPressed: () => _showCrearCatDialog(context), icon: const Icon(Icons.add_rounded), label: const Text('Crear categoría')),
      ],
    ),
  );

  void _showCrearCatDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva categoría', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: TextField(controller: ctrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'ej: Entradas, Bebidas, Postres')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = ctrl.text.trim();
              if (nombre.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await repo.crearCategoria(restaurantId: restaurantId, nombre: nombre);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Categoría creada'), backgroundColor: AppColors.success),
                );
                onChanged();
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

class _CategoriaExpansion extends StatefulWidget {
  final CategoriaModel categoria;
  final ConfiguracionRepository repo;
  final String sucursalId;
  final String tenantId;
  final Map<String, PlatoModel> asignados;
  final VoidCallback onChanged;

  const _CategoriaExpansion({
    required this.categoria,
    required this.repo,
    required this.sucursalId,
    required this.tenantId,
    required this.asignados,
    required this.onChanged,
  });

  @override
  State<_CategoriaExpansion> createState() => _CategoriaExpansionState();
}

class _CategoriaExpansionState extends State<_CategoriaExpansion> {
  List<SubcategoriaModel> _subs = [];
  bool _loading = false;
  bool _expanded = false;

  Future<void> _loadSubs() async {
    setState(() => _loading = true);
    try {
      final subs = await widget.repo.getSubcategorias(widget.categoria.categoriaId);
      setState(() { _subs = subs; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              setState(() => _expanded = !_expanded);
              if (_expanded && _subs.isEmpty) _loadSubs();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.cocineroColor.withOpacity(0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.category_outlined, color: AppColors.cocineroColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.categoria.nombre, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14))),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 18),
                    onPressed: () => _showEditarCatDialog(context),
                    tooltip: 'Editar categoría',
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_add_rounded, color: AppColors.primary, size: 20),
                    onPressed: () => _showCrearSubDialog(context),
                    tooltip: 'Agregar subcategoría',
                  ),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          if (_expanded)
            _loading
                ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : _buildSubs(context),
        ],
      ),
    );
  }

  Widget _buildSubs(BuildContext context) {
    if (_subs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          const Text('Sin subcategorías — ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          GestureDetector(
            onTap: () => _showCrearSubDialog(context),
            child: const Text('agregar', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }

    return Column(
      children: _subs.map((sub) => _SubcategoriaRow(
        sub:        sub,
        repo:       widget.repo,
        sucursalId: widget.sucursalId,
        tenantId:   widget.tenantId,
        asignados:  widget.asignados,
        onChanged:  () { _loadSubs(); widget.onChanged(); },
      )).toList(),
    );
  }

  void _showEditarCatDialog(BuildContext context) {
    final ctrl = TextEditingController(text: widget.categoria.nombre);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar categoría', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.sentences,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = ctrl.text.trim();
              if (nombre.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.repo.actualizarCategoria(
                  categoriaId:  widget.categoria.categoriaId,
                  restaurantId: widget.categoria.restaurantId,
                  nombre:       nombre,
                  descripcion:  widget.categoria.descripcion,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Categoría actualizada'), backgroundColor: AppColors.success),
                );
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
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

  void _showCrearSubDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Subcategoría en "${widget.categoria.nombre}"',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'ej: Fríos, Calientes, Jugos'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = ctrl.text.trim();
              if (nombre.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.repo.crearSubcategoria(categoriaId: widget.categoria.categoriaId, nombre: nombre);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Subcategoría creada'), backgroundColor: AppColors.success),
                );
                _loadSubs();
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

class _SubcategoriaRow extends StatefulWidget {
  final SubcategoriaModel sub;
  final ConfiguracionRepository repo;
  final String sucursalId;
  final String tenantId;
  final Map<String, PlatoModel> asignados;
  final VoidCallback onChanged;

  const _SubcategoriaRow({
    required this.sub,
    required this.repo,
    required this.sucursalId,
    required this.tenantId,
    required this.asignados,
    required this.onChanged,
  });

  @override
  State<_SubcategoriaRow> createState() => _SubcategoriaRowState();
}

class _SubcategoriaRowState extends State<_SubcategoriaRow> {
  List<PlatoMasterModel> _platos = [];
  bool _loading = false;
  bool _expanded = false;

  Future<void> _loadPlatos() async {
    setState(() => _loading = true);
    try {
      final p = await widget.repo.getPlatosBySubcategoria(widget.sub.subcategoriaId);
      setState(() { _platos = p; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  /// Aplica una tarifa de IVA a TODOS los platos de la subcategoría. Con 189
  /// platos, marcarlos uno por uno no se hace nunca.
  Future<void> _aplicarIvaSubcategoria(BuildContext context) async {
    final sel = await elegirTasaIva(
      context,
      widget.repo,
      tenantId: widget.tenantId,
      titulo: 'IVA de ${widget.sub.nombre}',
      ayuda: 'Se aplica a todos los platos de esta subcategoría. '
             'Después puedes cambiar los que sean excepción, uno por uno.',
    );
    if (!sel.elegido) return;
    try {
      final n = await widget.repo
          .asignarTasaIvaSubcategoria(widget.sub.subcategoriaId, sel.tasaIvaId);
      if (_expanded) await _loadPlatos();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Tarifa aplicada a $n plato${n == 1 ? '' : 's'}'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error));
      }
    }
  }

  /// Tarifa de un plato suelto: para las excepciones dentro de la subcategoría
  /// (por ejemplo, solo algunas cervezas gravadas).
  Future<void> _aplicarIvaPlato(BuildContext context, PlatoMasterModel plato) async {
    final sel = await elegirTasaIva(
      context,
      widget.repo,
      tenantId: widget.tenantId,
      titulo: 'IVA de ${plato.nombre}',
      ayuda: 'Tarifa de este plato en particular.',
      tasaActualId: plato.tasaIvaId,
    );
    if (!sel.elegido) return;
    try {
      await widget.repo.asignarTasaIvaPlato(plato.platoId, sel.tasaIvaId);
      await _loadPlatos();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded && _platos.isEmpty) _loadPlatos();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.sub.nombre, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary))),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 16),
                  onPressed: () => _showEditarSubDialog(context),
                  tooltip: 'Editar subcategoría',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.percent_rounded, color: AppColors.info, size: 16),
                  onPressed: () => _aplicarIvaSubcategoria(context),
                  tooltip: 'IVA de toda la subcategoría',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.add_box_outlined, color: AppColors.cocineroColor, size: 18),
                  onPressed: () => _showCrearPlatoDialog(context),
                  tooltip: 'Agregar plato',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        if (_expanded)
          _loading
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : _buildPlatos(context),
        const Divider(height: 1, indent: 20, color: Color(0x18000000)),
      ],
    );
  }

  Widget _buildPlatos(BuildContext context) {
    if (_platos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 4, 16, 8),
        child: Row(children: [
          const Text('Sin platos — ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          GestureDetector(
            onTap: () => _showCrearPlatoDialog(context),
            child: const Text('agregar plato', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 16, 8),
      child: Column(
        children: _platos.map((p) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              const Icon(Icons.restaurant_outlined, size: 14, color: AppColors.cocineroColor),
              const SizedBox(width: 8),
              Expanded(child: Text(p.nombre, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))),
              // Tarifa del plato: "—" cuando hereda la del negocio.
              GestureDetector(
                onTap: () => _aplicarIvaPlato(context, p),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('IVA ${p.ivaTexto}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 10.5,
                          fontWeight: FontWeight.w700, color: AppColors.info)),
                ),
              ),
              GestureDetector(
                onTap: () => _showEditarPlatoDialog(context, p),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.edit_outlined, size: 14, color: AppColors.textSecondary),
                ),
              ),
              // Con precio asignado en la sucursal se muestra (tocar para
              // cambiarlo); sin precio, el botón para asignarlo
              Builder(builder: (_) {
                final asignado = widget.asignados[p.platoId];
                return GestureDetector(
                  onTap: () => asignado != null
                      ? _showEditarPrecioDialog(context, p, asignado)
                      : _showAsignarPrecioDialog(context, p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: asignado != null
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      asignado != null ? '\$${asignado.precio.toStringAsFixed(2)}' : 'asignar precio',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700,
                        color: asignado != null ? AppColors.success : AppColors.warning)),
                  ),
                );
              }),
            ],
          ),
        )).toList(),
      ),
    );
  }

  void _showEditarSubDialog(BuildContext context) {
    final ctrl = TextEditingController(text: widget.sub.nombre);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar subcategoría', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.sentences,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = ctrl.text.trim();
              if (nombre.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.repo.actualizarSubcategoria(
                  subcategoriaId: widget.sub.subcategoriaId,
                  categoriaId:    widget.sub.categoriaId,
                  nombre:         nombre,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Subcategoría actualizada'), backgroundColor: AppColors.success),
                );
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
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

  void _showCrearPlatoDialog(BuildContext context) {
    final nombreCtrl = TextEditingController();
    final descCtrl   = TextEditingController();
    final precioCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nuevo plato en "${widget.sub.nombre}"',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre del plato *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio en esta sucursal *',
                  prefixText: '\$  ',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();
              final precio = double.tryParse(precioCtrl.text.trim());
              if (nombre.isEmpty || precio == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nombre y precio son requeridos')),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                final plato = await widget.repo.crearPlato(
                  subcategoriaId: widget.sub.subcategoriaId,
                  nombre:         nombre,
                  descripcion:    descCtrl.text.trim(),
                );
                await widget.repo.asignarPlatoSucursal(
                  sucursalId: widget.sucursalId,
                  platoId:    plato.platoId,
                  precio:     precio,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Plato "$nombre" agregado'),
                    backgroundColor: AppColors.success,
                  ),
                );
                _loadPlatos();
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
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

  void _showEditarPlatoDialog(BuildContext context, PlatoMasterModel plato) {
    final nombreCtrl = TextEditingController(text: plato.nombre);
    final descCtrl   = TextEditingController(text: plato.descripcion ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar: ${plato.nombre}',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre del plato *'),
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
                await widget.repo.actualizarPlato(
                  platoId:        plato.platoId,
                  subcategoriaId: plato.subcategoriaId,
                  nombre:         nombre,
                  descripcion:    descCtrl.text.trim(),
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Plato actualizado'), backgroundColor: AppColors.success),
                );
                _loadPlatos();
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
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

  /// Cambia el precio de un plato ya asignado a la sucursal.
  void _showEditarPrecioDialog(BuildContext context, PlatoMasterModel plato, PlatoModel asignado) {
    final precioCtrl = TextEditingController(text: asignado.precio.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar precio: ${plato.nombre}',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: precioCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Precio *', prefixText: '\$  '),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final precio = double.tryParse(precioCtrl.text.trim());
              if (precio == null || precio <= 0) return;
              Navigator.pop(ctx);
              try {
                await widget.repo.actualizarPrecioPlato(
                  sucursalPlatoId: asignado.sucursalPlatoId,
                  sucursalId:      widget.sucursalId,
                  platoId:         asignado.platoId,
                  precio:          precio,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Precio actualizado'), backgroundColor: AppColors.success),
                );
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
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

  void _showAsignarPrecioDialog(BuildContext context, PlatoMasterModel plato) {
    final precioCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Precio: ${plato.nombre}', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: precioCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Precio *', prefixText: '\$  '),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final precio = double.tryParse(precioCtrl.text.trim());
              if (precio == null) return;
              Navigator.pop(ctx);
              try {
                await widget.repo.asignarPlatoSucursal(
                  sucursalId: widget.sucursalId,
                  platoId:    plato.platoId,
                  precio:     precio,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Precio asignado'), backgroundColor: AppColors.success),
                );
                widget.onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
                );
              }
            },
            child: const Text('Asignar'),
          ),
        ],
      ),
    );
  }
}

// ─── Campo de búsqueda compartido por ambas pestañas ────────────────────────

class _BusquedaField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _BusquedaField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── TAB 2: PLATOS EN SUCURSAL ───────────────────────────────────────────────

class _PlatosSucursalTab extends StatefulWidget {
  final List<PlatoModel> platos;
  final bool loading;
  final ConfiguracionRepository repo;
  final String sucursalId;
  final VoidCallback onChanged;

  const _PlatosSucursalTab({
    required this.platos,
    required this.loading,
    required this.repo,
    required this.sucursalId,
    required this.onChanged,
  });

  @override
  State<_PlatosSucursalTab> createState() => _PlatosSucursalTabState();
}

class _PlatosSucursalTabState extends State<_PlatosSucursalTab> {
  ConfiguracionRepository get repo => widget.repo;
  String get sucursalId => widget.sucursalId;
  VoidCallback get onChanged => widget.onChanged;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  final _inventarioRepo = InventarioRepository();
  /// Solo los restaurantes con control de inventario activado ven el botón de
  /// stock; para el resto, el módulo no existe.
  bool _inventarioActivo = false;

  @override
  void initState() {
    super.initState();
    _verSiLlevaInventario();
  }

  Future<void> _verSiLlevaInventario() async {
    final alertas = await _inventarioRepo.getAlertas(sucursalId);
    if (mounted) setState(() => _inventarioActivo = alertas.habilitado);
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  /// Activa o desactiva el control de stock de un plato en esta sucursal.
  Future<void> _dialogoStock(BuildContext context, PlatoModel p) async {
    bool controlar = p.controlaStock;
    final stockCtrl = TextEditingController(
        text: p.stock == null ? '' : p.unidadesDisponibles.toString());
    final minimoCtrl = TextEditingController(
        text: p.stockMinimo == null ? '' : p.stockMinimo!.round().toString());
    final unidadCtrl = TextEditingController(text: p.unidad ?? '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Stock de ${p.nombrePlato}',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: controlar,
                  activeColor: AppColors.success,
                  title: const Text('Controlar stock',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text(
                      'Se descuenta al pedir y avisa cuando queda poco',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
                  onChanged: (v) => setDialogState(() => controlar = v),
                ),
                if (controlar) ...[
                  const SizedBox(height: 6),
                  if (!p.controlaStock)
                    TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Cuánto hay ahora', isDense: true),
                    ),
                  if (!p.controlaStock) const SizedBox(height: 10),
                  TextField(
                    controller: minimoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Avisarme cuando queden', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: unidadCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Unidad (botellas, porciones…)', isDense: true),
                  ),
                  if (p.controlaStock) ...[
                    const SizedBox(height: 10),
                    const Text(
                        'El stock se mueve desde Inventario, con ingresos y ajustes, '
                        'para que el historial no tenga huecos.',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11.5,
                            color: AppColors.textSecondary, height: 1.4)),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (guardar != true) return;

    try {
      await _inventarioRepo.configurar(
        p.sucursalPlatoId,
        controlar: controlar,
        stockInicial: double.tryParse(stockCtrl.text.replaceAll(',', '.')),
        stockMinimo: double.tryParse(minimoCtrl.text.replaceAll(',', '.')),
        unidad: unidadCtrl.text.trim(),
      );
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ApiClient.parseError(e)),
            backgroundColor: AppColors.error));
      }
    }
  }

  void _showEditarPrecioDialog(BuildContext context, PlatoModel p) {
    final precioCtrl = TextEditingController(text: p.precio.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar precio: ${p.nombrePlato}',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: precioCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Precio *', prefixText: '\$  '),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final precio = double.tryParse(precioCtrl.text.trim());
              if (precio == null || precio <= 0) return;
              Navigator.pop(ctx);
              try {
                await repo.actualizarPrecioPlato(
                  sucursalPlatoId: p.sucursalPlatoId,
                  sucursalId:      sucursalId,
                  platoId:         p.platoId,
                  precio:          precio,
                );
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Precio actualizado'), backgroundColor: AppColors.success),
                );
                onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator());

    if (widget.platos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_meals_rounded, size: 64, color: Color(0x40795548)),
            SizedBox(height: 16),
            Text('Sin platos asignados', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            SizedBox(height: 8),
            Text('Ve a "Categorías y Platos" para crear y asignar platos', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final visibles = _busqueda.isEmpty
        ? widget.platos
        : widget.platos
            .where((p) => p.nombrePlato.toLowerCase().contains(_busqueda))
            .toList();

    return Column(
      children: [
        _BusquedaField(
          controller: _busquedaCtrl,
          hint: 'Buscar plato...',
          onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
        ),
        Expanded(
          child: visibles.isEmpty
              ? Center(
                  child: Text('Sin resultados para "$_busqueda"',
                    style: const TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13)),
                )
              : RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: visibles.length,
        itemBuilder: (_, i) {
          final p = visibles[i];
          return InkWell(
            onTap: () => _showEditarPrecioDialog(context, p),
            borderRadius: BorderRadius.circular(12),
            child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
              border: p.disponible ? null : Border.all(color: AppColors.error.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.cocineroColor.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.restaurant_outlined, color: AppColors.cocineroColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nombrePlato, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                      Row(
                        children: [
                          Text('\$${p.precio.toStringAsFixed(2)}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit_outlined, size: 12, color: AppColors.textSecondary),
                          if (p.controlaStock) ...[
                            const SizedBox(width: 8),
                            Text(
                              p.agotado
                                  ? 'AGOTADO'
                                  : '${p.unidadesDisponibles}${(p.unidad?.trim().isNotEmpty ?? false) ? ' ${p.unidad!.trim()}' : ' en stock'}',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: p.agotado
                                    ? AppColors.error
                                    : p.bajoMinimo
                                        ? AppColors.warning
                                        : AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (_inventarioActivo)
                  IconButton(
                    tooltip: 'Control de stock',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.inventory_2_outlined, size: 20,
                        color: p.controlaStock
                            ? AppColors.earth2
                            : AppColors.textHint),
                    onPressed: () => _dialogoStock(context, p),
                  ),
                Switch(
                  value: p.disponible,
                  onChanged: (v) async {
                    try {
                      // El PUT exige el cuerpo completo: se reenvía el
                      // precio actual junto con la nueva disponibilidad.
                      await repo.actualizarPrecioPlato(
                        sucursalPlatoId: p.sucursalPlatoId,
                        sucursalId:      sucursalId,
                        platoId:         p.platoId,
                        precio:          p.precio,
                        disponible:      v,
                      );
                      onChanged();
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
                      );
                    }
                  },
                  activeColor: AppColors.success,
                ),
              ],
            ),
            ),
          );
        },
      ),
    ),
        ),
      ],
    );
  }
}

/// Resultado de elegir tarifa: [elegido] distingue "cancelo" de "elegi heredar".
class SeleccionTasaIva {
  final bool elegido;
  final String? tasaIvaId;
  const SeleccionTasaIva(this.elegido, this.tasaIvaId);
}

/// Pregunta qué tarifa de IVA aplicar. Sirve para un plato suelto y para una
/// subcategoría completa; las tarifas son las del negocio (tenant).
Future<SeleccionTasaIva> elegirTasaIva(
  BuildContext context,
  ConfiguracionRepository repo, {
  required String tenantId,
  required String titulo,
  required String ayuda,
  String? tasaActualId,
}) async {
  if (tenantId.isEmpty) return const SeleccionTasaIva(false, null);

  List<TasaIvaModel> tasas;
  try {
    tasas = await repo.getTasasIva(tenantId);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error));
    }
    return const SeleccionTasaIva(false, null);
  }
  if (!context.mounted) return const SeleccionTasaIva(false, null);

  final predeterminada = tasas.where((t) => t.predeterminada).firstOrNull;

  return await showDialog<SeleccionTasaIva>(
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
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                      tasaActualId == null
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: AppColors.primary, size: 20),
                  title: const Text('Hereda la del negocio',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                  // Decir cuál es evita marcar un plato "por si acaso" sin
                  // saber a qué tarifa iba a caer si lo dejabas heredando.
                  subtitle: Text(
                      predeterminada == null
                          ? 'Ninguna tarifa está marcada como predeterminada'
                          : 'Hoy es ${predeterminada.nombre} · '
                            '${predeterminada.porcentaje.toStringAsFixed(
                                predeterminada.porcentaje % 1 == 0 ? 0 : 2)}%',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                  onTap: () => Navigator.pop(ctx, const SeleccionTasaIva(true, null)),
                ),
                ...tasas.where((t) => t.activo).map((t) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                          tasaActualId == t.tasaIvaId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: AppColors.primary, size: 20),
                      title: Text(
                          '${t.nombre} · ${t.porcentaje.toStringAsFixed(t.porcentaje % 1 == 0 ? 0 : 2)}%',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                      onTap: () => Navigator.pop(ctx, SeleccionTasaIva(true, t.tasaIvaId)),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, const SeleccionTasaIva(false, null)),
                child: const Text('Cancelar')),
          ],
        ),
      ) ??
      const SeleccionTasaIva(false, null);
}
