import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/inventario_repository.dart';
import '../data/unidades.dart';
import 'inventario_dialogos.dart';

/// Compras de la sucursal en los últimos 30 días. Cada compra suma stock y
/// actualiza el costo promedio de sus insumos (y con eso, el de los platos).
class ComprasTab extends StatefulWidget {
  final String sucursalId;
  final InventarioRepository repo;
  const ComprasTab({super.key, required this.sucursalId, required this.repo});

  @override
  State<ComprasTab> createState() => _ComprasTabState();
}

class _ComprasTabState extends State<ComprasTab> with AutomaticKeepAliveClientMixin {
  List<CompraModel> _compras = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final lista = await widget.repo.getCompras(widget.sucursalId);
      if (!mounted) return;
      setState(() { _compras = lista; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _nueva() async {
    final registrada = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => NuevaCompraScreen(sucursalId: widget.sucursalId, repo: widget.repo),
    ));
    if (registrada == true && mounted) _load();
  }

  void _detalle(CompraModel c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DetalleCompraSheet(
          sucursalId: widget.sucursalId, compraId: c.compraId, repo: widget.repo),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final total = _compras.fold(0.0, (s, c) => s + c.total);
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nueva-compra',
        onPressed: _nueva,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Compra'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'Poppins', color: AppColors.textSecondary)),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      Text('Últimos 30 días  ·  \$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                              fontSize: 14, color: AppColors.textPrimary)),
                      const SizedBox(height: 10),
                      if (_compras.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Text(
                            'No hay compras registradas.\n\nCada compra suma al stock y '
                            'actualiza el costo de los insumos y de los platos que los usan.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Poppins', color: AppColors.textSecondary,
                                height: 1.5),
                          ),
                        )
                      else
                        ..._compras.map((c) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                onTap: () => _detalle(c),
                                leading: const Icon(Icons.receipt_outlined,
                                    color: AppColors.earth2),
                                title: Text(c.proveedor ?? 'Sin proveedor',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                subtitle: Text(
                                  '${DateFormat('d MMM yyyy', 'es').format(c.fecha)}'
                                  '${c.numeroDocumento != null ? ' · ${c.numeroDocumento}' : ''}'
                                  ' · ${c.totalItems} insumo${c.totalItems == 1 ? '' : 's'}',
                                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5),
                                ),
                                trailing: Text('\$${c.total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                        fontSize: 15, color: AppColors.primary)),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _DetalleCompraSheet extends StatefulWidget {
  final String sucursalId;
  final String compraId;
  final InventarioRepository repo;
  const _DetalleCompraSheet(
      {required this.sucursalId, required this.compraId, required this.repo});

  @override
  State<_DetalleCompraSheet> createState() => _DetalleCompraSheetState();
}

class _DetalleCompraSheetState extends State<_DetalleCompraSheet> {
  CompraModel? _compra;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.repo.getCompra(widget.sucursalId, widget.compraId).then((c) {
      if (mounted) setState(() => _compra = c);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = ApiClient.parseError(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _compra;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scroll) => c == null
          ? Center(
              child: _error != null
                  ? Text(_error!, textAlign: TextAlign.center)
                  : const CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Text(c.proveedor ?? 'Compra sin proveedor',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                Text(
                  '${DateFormat('d MMM yyyy', 'es').format(c.fecha)}'
                  '${c.numeroDocumento != null ? ' · doc. ${c.numeroDocumento}' : ''}'
                  '${c.usuario != null ? ' · ${c.usuario}' : ''}',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                ),
                if (c.nota != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(c.nota!,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12, fontStyle: FontStyle.italic)),
                  ),
                const SizedBox(height: 12),
                ...c.items.map((i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.nombre,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                          '${Unidades.formato(i.cantidad, i.unidad)} · ${Unidades.costo(i.costoUnitario, i.unidad)}',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                      trailing: Text('\$${i.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                    )),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('Total \$${c.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16,
                          color: AppColors.primary)),
                ),
              ],
            ),
    );
  }
}

/// Una línea de la compra mientras se arma.
class _LineaCompra {
  final InsumoModel insumo;
  final double cantidadBase;
  final double costoTotal;
  const _LineaCompra(this.insumo, this.cantidadBase, this.costoTotal);
}

/// Registrar una compra: proveedor, documento y lo que entró con lo que costó.
/// Se escribe el total de cada línea tal como está en la factura del
/// proveedor; el costo por gramo lo calcula el sistema.
class NuevaCompraScreen extends StatefulWidget {
  final String sucursalId;
  final InventarioRepository repo;
  const NuevaCompraScreen({super.key, required this.sucursalId, required this.repo});

  @override
  State<NuevaCompraScreen> createState() => _NuevaCompraScreenState();
}

class _NuevaCompraScreenState extends State<NuevaCompraScreen> {
  final _documento = TextEditingController();
  final _nota = TextEditingController();
  List<ProveedorModel> _proveedores = [];
  String? _proveedorId;
  DateTime _fecha = DateTime.now();
  final List<_LineaCompra> _lineas = [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarProveedores();
  }

  @override
  void dispose() {
    _documento.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargarProveedores() async {
    try {
      final lista = await widget.repo.getProveedores(widget.sucursalId);
      if (mounted) setState(() => _proveedores = lista);
    } catch (_) {
      // Sin proveedores igual se puede registrar la compra.
    }
  }

  double get _total => _lineas.fold(0.0, (s, l) => s + l.costoTotal);

  Future<void> _agregar() async {
    final ins = await showModalBottomSheet<InsumoModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SelectorInsumoSheet(
        sucursalId: widget.sucursalId,
        repo: widget.repo,
        yaElegidos: _lineas.map((l) => l.insumo.insumoId).toSet(),
      ),
    );
    if (ins == null || !mounted) return;
    final linea = await showDialog<_LineaCompra>(
      context: context,
      builder: (_) => _LineaCompraDialog(insumo: ins),
    );
    if (linea != null) setState(() => _lineas.add(linea));
  }

  Future<void> _nuevoProveedor() async {
    final form = await showDialog<ProveedorForm>(
        context: context, builder: (_) => const ProveedorDialog());
    if (form == null) return;
    try {
      final p = await widget.repo.guardarProveedor(widget.sucursalId,
          nombre: form.nombre, ruc: form.ruc, telefono: form.telefono, email: form.email);
      if (!mounted) return;
      setState(() {
        _proveedores = [..._proveedores, p];
        _proveedorId = p.proveedorId;
      });
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: hoy.subtract(const Duration(days: 365)),
      lastDate: hoy,
    );
    if (f != null) setState(() => _fecha = f);
  }

  Future<void> _registrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar compra',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
            '${_lineas.length} insumo${_lineas.length == 1 ? '' : 's'} por '
            '\$${_total.toStringAsFixed(2)}. Se suman al stock de esta sucursal y '
            'actualizan el costo de los platos que los usan.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      await widget.repo.registrarCompra(
        widget.sucursalId,
        proveedorId: _proveedorId,
        numeroDocumento: _documento.text.trim(),
        fecha: _fecha,
        nota: _nota.text.trim(),
        lineas: _lineas
            .map((l) => CompraLinea(l.insumo.insumoId, l.cantidadBase, l.costoTotal))
            .toList(),
      );
      if (!mounted) return;
      mostrarOk(context, 'Compra registrada');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Nueva compra')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _proveedorId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Proveedor', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Sin proveedor')),
                      ..._proveedores.map((p) => DropdownMenuItem<String?>(
                          value: p.proveedorId,
                          child: Text(p.nombre, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _proveedorId = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Nuevo proveedor',
                  icon: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.primary),
                  onPressed: _nuevoProveedor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _documento,
                    decoration: const InputDecoration(
                        labelText: 'N.º de factura (opcional)', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _elegirFecha,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(DateFormat('d MMM', 'es').format(_fecha)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nota,
              maxLength: 200,
              decoration: const InputDecoration(
                  labelText: 'Nota (opcional)', isDense: true, counterText: ''),
            ),
            const SizedBox(height: 16),
            Text('Lo que entró',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_lineas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Agrega los insumos de la factura con su cantidad y lo que pagaste.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
              )
            else
              ..._lineas.map((l) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      title: Text(l.insumo.nombre,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                          '${Unidades.formato(l.cantidadBase, l.insumo.unidad)} · '
                          '${Unidades.costo(l.cantidadBase > 0 ? l.costoTotal / l.cantidadBase : null, l.insumo.unidad)}',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('\$${l.costoTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                          IconButton(
                            icon: const Icon(Icons.close, color: AppColors.textSecondary),
                            onPressed: () => setState(() => _lineas.remove(l)),
                          ),
                        ],
                      ),
                    ),
                  )),
            OutlinedButton.icon(
              onPressed: _agregar,
              icon: const Icon(Icons.add),
              label: const Text('Agregar insumo'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            onPressed: _lineas.isEmpty || _guardando ? null : _registrar,
            child: _guardando
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Registrar  ·  \$${_total.toStringAsFixed(2)}'),
          ),
        ),
      ),
    );
  }
}

/// Cantidad (en la unidad que se prefiera) y lo que se pagó por la línea.
class _LineaCompraDialog extends StatefulWidget {
  final InsumoModel insumo;
  const _LineaCompraDialog({required this.insumo});

  @override
  State<_LineaCompraDialog> createState() => _LineaCompraDialogState();
}

class _LineaCompraDialogState extends State<_LineaCompraDialog> {
  final _cantidad = TextEditingController();
  final _costo = TextEditingController();
  late UnidadCompra _unidad;
  String? _error;

  @override
  void initState() {
    super.initState();
    final opciones = Unidades.opciones(widget.insumo.unidad);
    // Las compras de peso suelen venir en kilos o libras, no en gramos.
    _unidad = opciones.length > 1 ? opciones[1] : opciones.first;
  }

  @override
  void dispose() {
    _cantidad.dispose();
    _costo.dispose();
    super.dispose();
  }

  void _aceptar() {
    final cant = Unidades.leer(_cantidad.text);
    final costo = Unidades.leer(_costo.text);
    if (cant == null || cant <= 0) {
      setState(() => _error = 'Escribe la cantidad que entró');
      return;
    }
    if (costo == null || costo < 0) {
      setState(() => _error = 'Escribe cuánto pagaste por esta línea');
      return;
    }
    Navigator.pop(context, _LineaCompra(widget.insumo, cant * _unidad.factor, costo));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.insumo.nombre,
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _cantidad,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Cantidad', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<UnidadCompra>(
                  value: _unidad,
                  underline: const SizedBox.shrink(),
                  items: Unidades.opciones(widget.insumo.unidad)
                      .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u.etiqueta,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary))))
                      .toList(),
                  onChanged: (u) => setState(() => _unidad = u ?? _unidad),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _costo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Total pagado por esta línea', prefixText: '\$ ', isDense: true),
              onSubmitted: (_) => _aceptar(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _aceptar, child: const Text('Agregar')),
      ],
    );
  }
}

/// Datos de un proveedor para crearlo o editarlo.
class ProveedorForm {
  final String nombre;
  final String? ruc;
  final String? telefono;
  final String? email;
  const ProveedorForm(this.nombre, this.ruc, this.telefono, this.email);
}

class ProveedorDialog extends StatefulWidget {
  final ProveedorModel? proveedor;
  const ProveedorDialog({super.key, this.proveedor});

  @override
  State<ProveedorDialog> createState() => _ProveedorDialogState();
}

class _ProveedorDialogState extends State<ProveedorDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _ruc;
  late final TextEditingController _telefono;
  late final TextEditingController _email;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.proveedor;
    _nombre = TextEditingController(text: p?.nombre ?? '');
    _ruc = TextEditingController(text: p?.ruc ?? '');
    _telefono = TextEditingController(text: p?.telefono ?? '');
    _email = TextEditingController(text: p?.email ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _ruc.dispose();
    _telefono.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.proveedor == null ? 'Nuevo proveedor' : 'Editar proveedor',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nombre,
              autofocus: widget.proveedor == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ruc,
              keyboardType: TextInputType.number,
              maxLength: 13,
              decoration: const InputDecoration(
                  labelText: 'RUC (opcional)', isDense: true, counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (opcional)', isDense: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final nombre = _nombre.text.trim();
            if (nombre.isEmpty) {
              setState(() => _error = 'El nombre es obligatorio');
              return;
            }
            Navigator.pop(context, ProveedorForm(nombre, _t(_ruc), _t(_telefono), _t(_email)));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Proveedores del restaurante (compartidos por sus sucursales).
class ProveedoresTab extends StatefulWidget {
  final String sucursalId;
  final InventarioRepository repo;
  const ProveedoresTab({super.key, required this.sucursalId, required this.repo});

  @override
  State<ProveedoresTab> createState() => _ProveedoresTabState();
}

class _ProveedoresTabState extends State<ProveedoresTab> with AutomaticKeepAliveClientMixin {
  List<ProveedorModel> _proveedores = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final lista = await widget.repo.getProveedores(widget.sucursalId, incluirInactivos: true);
      if (!mounted) return;
      setState(() { _proveedores = lista; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _guardar([ProveedorModel? p]) async {
    final form = await showDialog<ProveedorForm>(
        context: context, builder: (_) => ProveedorDialog(proveedor: p));
    if (form == null) return;
    try {
      await widget.repo.guardarProveedor(widget.sucursalId,
          proveedorId: p?.proveedorId, nombre: form.nombre,
          ruc: form.ruc, telefono: form.telefono, email: form.email);
      if (mounted) _load();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _estado(ProveedorModel p, bool activo) async {
    try {
      await widget.repo.cambiarEstadoProveedor(widget.sucursalId, p.proveedorId, activo);
      if (mounted) _load();
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
        heroTag: 'nuevo-proveedor',
        onPressed: () => _guardar(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Proveedor'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      if (_proveedores.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Text('Todavía no hay proveedores.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Poppins', color: AppColors.textSecondary)),
                        )
                      else
                        ..._proveedores.map((p) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                onTap: () => _guardar(p),
                                title: Text(p.nombre,
                                    style: TextStyle(
                                        fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: p.activo
                                            ? AppColors.textPrimary
                                            : AppColors.textHint)),
                                subtitle: Text(
                                    [
                                      if (p.ruc != null) 'RUC ${p.ruc}',
                                      if (p.telefono != null) p.telefono!,
                                      if (p.email != null) p.email!,
                                    ].join(' · '),
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
                                trailing: Switch(
                                  value: p.activo,
                                  activeColor: AppColors.success,
                                  onChanged: (v) => _estado(p, v),
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}
