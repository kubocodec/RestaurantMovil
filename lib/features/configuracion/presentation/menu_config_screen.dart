import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/models/plato_model.dart';
import '../../../core/network/api_client.dart';
import '../data/configuracion_repository.dart';

class MenuConfigScreen extends StatefulWidget {
  final String sucursalId;
  final String restaurantId;

  const MenuConfigScreen({
    super.key,
    required this.sucursalId,
    required this.restaurantId,
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
      body: TabBarView(
        controller: _tabs,
        children: [
          _CategoriasTab(
            categorias:   _categorias,
            loading:      _loadingCat,
            repo:         _repo,
            restaurantId: widget.restaurantId,
            sucursalId:   widget.sucursalId,
            onChanged:    () { _loadCategorias(); _loadPlatosSucursal(); },
          ),
          _PlatosSucursalTab(
            platos:  _platosSucursal,
            loading: _loadingPlatos,
            repo:    _repo,
            onChanged: _loadPlatosSucursal,
          ),
        ],
      ),
    );
  }
}

// ─── TAB 1: CATEGORÍAS ──────────────────────────────────────────────────────

class _CategoriasTab extends StatelessWidget {
  final List<CategoriaModel> categorias;
  final bool loading;
  final ConfiguracionRepository repo;
  final String restaurantId;
  final String sucursalId;
  final VoidCallback onChanged;

  const _CategoriasTab({
    required this.categorias,
    required this.loading,
    required this.repo,
    required this.restaurantId,
    required this.sucursalId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'cat_fab',
        onPressed: () => _showCrearCatDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva categoría'),
      ),
      body: categorias.isEmpty
          ? _empty(context)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: categorias.length,
              itemBuilder: (_, i) => _CategoriaExpansion(
                categoria:  categorias[i],
                repo:       repo,
                sucursalId: sucursalId,
                onChanged:  onChanged,
              ),
            ),
    );
  }

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
  final VoidCallback onChanged;

  const _CategoriaExpansion({required this.categoria, required this.repo, required this.sucursalId, required this.onChanged});

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
        onChanged:  () { _loadSubs(); widget.onChanged(); },
      )).toList(),
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
  final VoidCallback onChanged;

  const _SubcategoriaRow({required this.sub, required this.repo, required this.sucursalId, required this.onChanged});

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
              GestureDetector(
                onTap: () => _showAsignarPrecioDialog(context, p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('\$ precio', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        )).toList(),
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

// ─── TAB 2: PLATOS EN SUCURSAL ───────────────────────────────────────────────

class _PlatosSucursalTab extends StatelessWidget {
  final List<PlatoModel> platos;
  final bool loading;
  final ConfiguracionRepository repo;
  final VoidCallback onChanged;

  const _PlatosSucursalTab({
    required this.platos,
    required this.loading,
    required this.repo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (platos.isEmpty) {
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

    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: platos.length,
        itemBuilder: (_, i) {
          final p = platos[i];
          return Container(
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
                      Text('\$${p.precio.toStringAsFixed(2)}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Switch(
                  value: p.disponible,
                  onChanged: (v) async {
                    try {
                      await repo.toggleDisponibilidadPlato(p.sucursalPlatoId, v);
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
          );
        },
      ),
    );
  }
}
