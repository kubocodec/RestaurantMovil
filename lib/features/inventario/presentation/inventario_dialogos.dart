import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../data/inventario_repository.dart';
import '../data/unidades.dart';

// Los diálogos son widgets con estado propio a propósito: sus controllers se
// liberan en dispose(), después de la animación de cierre. Crearlos y
// destruirlos alrededor de showDialog revienta con "A TextEditingController
// was used after being disposed" (ver CLAUDE.md).

const _titulo = TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16);
const _ayuda = TextStyle(
    fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary, height: 1.4);

final _formatoNumero = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

/// Resultado de [CantidadDialog]: la cantidad ya convertida a la unidad base.
class CantidadYNota {
  final double cantidadBase;
  final String nota;
  const CantidadYNota(this.cantidadBase, this.nota);
}

/// Pide una cantidad de un insumo en la unidad que la persona prefiera
/// (g, kg, lb…) y la devuelve convertida a la unidad base.
class CantidadDialog extends StatefulWidget {
  final String titulo;
  final String ayuda;
  final String unidadBase;
  final String etiqueta;
  final double? inicialBase;
  /// Etiqueta del campo de nota; null = sin nota.
  final String? etiquetaNota;
  final bool notaObligatoria;
  final bool permitirCero;
  /// Presentación del insumo ("Botella" de 750 ml): se puede escribir
  /// "11 botellas + 190 ml". null = como siempre, solo la unidad base.
  final Presentacion? presentacion;

  const CantidadDialog({
    super.key,
    required this.titulo,
    required this.ayuda,
    required this.unidadBase,
    required this.etiqueta,
    this.inicialBase,
    this.etiquetaNota,
    this.notaObligatoria = false,
    this.permitirCero = false,
    this.presentacion,
  });

  @override
  State<CantidadDialog> createState() => _CantidadDialogState();
}

class _CantidadDialogState extends State<CantidadDialog> {
  late final TextEditingController _ctrl;
  final _notaCtrl = TextEditingController();
  // Lo que sobra de la última presentación abierta ("+ 190 ml").
  final _restoCtrl = TextEditingController();
  late UnidadCompra _unidad;
  String? _error;

  List<UnidadCompra> get _opciones =>
      Unidades.opciones(widget.unidadBase, p: widget.presentacion);

  /// Está escribiendo en presentaciones (botellas): se muestra el "+ ml".
  bool get _enPresentacion =>
      widget.presentacion != null && _unidad == _opciones.first;

  @override
  void initState() {
    super.initState();
    final p = widget.presentacion;
    final inicial = widget.inicialBase;
    if (p == null) {
      _unidad = Unidades.opciones(widget.unidadBase).first;
      _ctrl = TextEditingController(text: inicial == null ? '' : Unidades.numero(inicial));
      return;
    }
    // Con presentación arranca en botellas, salvo que lo que ya hay sea menos
    // de una: los 60 ml de un cóctel se siguen editando en ml.
    if (inicial != null && inicial > 0 && inicial < p.contenido) {
      _unidad = _opciones[1];
      _ctrl = TextEditingController(text: Unidades.numero(inicial));
    } else {
      _unidad = _opciones.first;
      if (inicial == null) {
        _ctrl = TextEditingController();
      } else {
        final (n, resto) = p.partir(inicial);
        _ctrl = TextEditingController(text: '$n');
        if (resto > 0) _restoCtrl.text = Unidades.numero(resto);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _notaCtrl.dispose();
    _restoCtrl.dispose();
    super.dispose();
  }

  void _aceptar() {
    final valor = Unidades.leer(_ctrl.text);
    // Sin presentación no hay "+ ml": resto 0 y todo queda como siempre.
    var resto = 0.0;
    if (_enPresentacion && _restoCtrl.text.trim().isNotEmpty) {
      final r = Unidades.leer(_restoCtrl.text);
      if (r == null || r < 0) {
        setState(() => _error = 'Lo que sobra no es válido');
        return;
      }
      resto = r;
    }
    if (valor == null || valor < 0 || (!widget.permitirCero && valor == 0 && resto == 0)) {
      setState(() => _error = widget.permitirCero
          ? 'Escribe una cantidad válida'
          : 'Escribe una cantidad mayor que cero');
      return;
    }
    if (widget.notaObligatoria && _notaCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el motivo');
      return;
    }
    Navigator.pop(context, CantidadYNota(valor * _unidad.factor + resto, _notaCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final opciones = _opciones;
    return AlertDialog(
      title: Text(widget.titulo, style: _titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.ayuda, style: _ayuda),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_formatoNumero],
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(labelText: widget.etiqueta, isDense: true),
                    onSubmitted: (_) => _aceptar(),
                  ),
                ),
                if (opciones.length > 1) ...[
                  const SizedBox(width: 10),
                  DropdownButton<UnidadCompra>(
                    value: _unidad,
                    underline: const SizedBox.shrink(),
                    items: opciones
                        .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u.etiqueta,
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary))))
                        .toList(),
                    onChanged: (u) => setState(() => _unidad = u ?? _unidad),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 8),
                    child: Text(Unidades.corta(widget.unidadBase),
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                  ),
              ],
            ),
            if (_enPresentacion) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _restoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_formatoNumero],
                decoration: InputDecoration(
                  labelText: 'Más lo que sobra de una ${widget.presentacion!.singular} abierta (opcional)',
                  suffixText: Unidades.corta(widget.unidadBase),
                  isDense: true,
                ),
                onSubmitted: (_) => _aceptar(),
              ),
            ],
            if (widget.etiquetaNota != null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _notaCtrl,
                maxLength: 200,
                decoration: InputDecoration(
                    labelText: widget.etiquetaNota, isDense: true, counterText: ''),
              ),
            ],
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
        ElevatedButton(onPressed: _aceptar, child: const Text('Aceptar')),
      ],
    );
  }
}

/// Datos de un insumo para crearlo o editarlo.
class InsumoForm {
  final String nombre;
  final String unidad;
  final String? categoria;
  final double? stockMinimo;
  /// null = sin presentación (se quita si la tenía).
  final Presentacion? presentacion;
  const InsumoForm(this.nombre, this.unidad, this.categoria, this.stockMinimo,
      [this.presentacion]);
}

class InsumoDialog extends StatefulWidget {
  final InsumoModel? insumo;
  const InsumoDialog({super.key, this.insumo});

  @override
  State<InsumoDialog> createState() => _InsumoDialogState();
}

class _InsumoDialogState extends State<InsumoDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _categoria;
  late final TextEditingController _minimo;
  // Presentación opcional: "Botella" de "750" ml.
  late final TextEditingController _presNombre;
  late final TextEditingController _presContenido;
  late String _unidad;
  late UnidadCompra _unidadMinimo;
  late UnidadCompra _unidadContenido;
  String? _error;

  /// La presentación tal como está escrita ahora (null si está incompleta).
  Presentacion? get _presentacion {
    final c = Unidades.leer(_presContenido.text);
    return Presentacion.de(_presNombre.text, c == null ? null : c * _unidadContenido.factor);
  }

  List<UnidadCompra> get _opcionesMinimo => Unidades.opciones(_unidad, p: _presentacion);

  @override
  void initState() {
    super.initState();
    final i = widget.insumo;
    final p = i?.presentacion;
    _nombre = TextEditingController(text: i?.nombre ?? '');
    _categoria = TextEditingController(text: i?.categoria ?? '');
    _unidad = i?.unidad ?? 'GRAMO';
    _presNombre = TextEditingController(text: p?.nombre ?? '');
    _presContenido = TextEditingController(text: p == null ? '' : Unidades.numero(p.contenido));
    _unidadContenido = Unidades.opciones(_unidad).first;
    if (p != null && i?.stockMinimo != null) {
      // El mínimo se muestra en botellas si la tiene: "avisar con 2 botellas".
      _unidadMinimo = Unidades.opciones(_unidad, p: p).first;
      _minimo = TextEditingController(text: Unidades.numero(i!.stockMinimo! / p.contenido));
    } else {
      _minimo = TextEditingController(
          text: i?.stockMinimo == null ? '' : Unidades.numero(i!.stockMinimo!));
      _unidadMinimo = Unidades.opciones(_unidad).first;
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _categoria.dispose();
    _minimo.dispose();
    _presNombre.dispose();
    _presContenido.dispose();
    super.dispose();
  }

  /// Si cambió la presentación y la unidad del mínimo ya no existe, vuelve a
  /// la base para que el DropdownButton no quede con un valor fuera de la lista.
  void _ajustarUnidadMinimo() {
    if (!_opcionesMinimo.contains(_unidadMinimo)) _unidadMinimo = _opcionesMinimo.first;
  }

  void _aceptar() {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio');
      return;
    }
    double? minimo;
    if (_minimo.text.trim().isNotEmpty) {
      final v = Unidades.leer(_minimo.text);
      if (v == null || v < 0) {
        setState(() => _error = 'El mínimo no es válido');
        return;
      }
      minimo = v * _unidadMinimo.factor;
    }
    // Presentación: o completa (nombre y contenido) o vacía.
    final presNombre = _presNombre.text.trim();
    final presTexto = _presContenido.text.trim();
    Presentacion? pres;
    if (presNombre.isNotEmpty || presTexto.isNotEmpty) {
      pres = _presentacion;
      if (pres == null) {
        setState(() => _error = presNombre.isEmpty
            ? 'Escribe el nombre de la presentación (botella, caja…)'
            : 'Escribe cuánto trae una ${presNombre.toLowerCase()}');
        return;
      }
    }
    final cat = _categoria.text.trim();
    Navigator.pop(context, InsumoForm(nombre, _unidad, cat.isEmpty ? null : cat, minimo, pres));
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.insumo != null;
    return AlertDialog(
      title: Text(editando ? 'Editar insumo' : 'Nuevo insumo', style: _titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombre,
              autofocus: !editando,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Nombre (carne de res, papas, aceite…)', isDense: true),
            ),
            const SizedBox(height: 14),
            const Text('Se cuenta en',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: Unidades.base.map((u) {
                final sel = _unidad == u;
                return ChoiceChip(
                  label: Text(Unidades.nombre(u)),
                  selected: sel,
                  labelStyle: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                      color: sel ? AppColors.textOnPrimary : AppColors.textPrimary),
                  selectedColor: AppColors.primary,
                  onSelected: (_) => setState(() {
                    _unidad = u;
                    _unidadContenido = Unidades.opciones(u).first;
                    _unidadMinimo = _opcionesMinimo.first;
                  }),
                );
              }).toList(),
            ),
            if (editando)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                    'Si el insumo ya tiene movimientos o recetas, la unidad no se puede cambiar.',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _categoria,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Grupo (opcional): Carnes, Verduras…', isDense: true),
            ),
            const SizedBox(height: 14),
            const Text('Se compra y se cuenta por (opcional)',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _presNombre,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Botella, caja…', isDense: true),
                    onChanged: (_) => setState(_ajustarUnidadMinimo),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _presContenido,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_formatoNumero],
                    decoration: const InputDecoration(labelText: 'Trae', isDense: true),
                    onChanged: (_) => setState(_ajustarUnidadMinimo),
                  ),
                ),
                if (Unidades.opciones(_unidad).length > 1)
                  DropdownButton<UnidadCompra>(
                    value: _unidadContenido,
                    underline: const SizedBox.shrink(),
                    items: Unidades.opciones(_unidad)
                        .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u.etiqueta,
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary))))
                        .toList(),
                    onChanged: (u) => setState(() {
                      _unidadContenido = u ?? _unidadContenido;
                      _ajustarUnidadMinimo();
                    }),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(Unidades.corta(_unidad),
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                  ),
              ],
            ),
            const Text('Ej: Botella de 750 ml. El stock se verá "12 botellas" en vez de "9 L".',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _minimo,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_formatoNumero],
                    decoration: const InputDecoration(
                        labelText: 'Avisarme cuando queden (opcional)', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<UnidadCompra>(
                  value: _unidadMinimo,
                  underline: const SizedBox.shrink(),
                  items: _opcionesMinimo
                      .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u.etiqueta,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary))))
                      .toList(),
                  onChanged: (u) => setState(() => _unidadMinimo = u ?? _unidadMinimo),
                ),
              ],
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
        ElevatedButton(onPressed: _aceptar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Buscador de insumos para agregar a una receta o a una compra. Permite crear
/// uno nuevo sin salir del flujo.
class SelectorInsumoSheet extends StatefulWidget {
  final String sucursalId;
  final InventarioRepository repo;
  /// Insumos que ya están en la lista (se muestran marcados).
  final Set<String> yaElegidos;

  const SelectorInsumoSheet({
    super.key,
    required this.sucursalId,
    required this.repo,
    this.yaElegidos = const {},
  });

  @override
  State<SelectorInsumoSheet> createState() => _SelectorInsumoSheetState();
}

class _SelectorInsumoSheetState extends State<SelectorInsumoSheet> {
  final _buscar = TextEditingController();
  List<InsumoModel> _insumos = [];
  bool _loading = true;
  String? _error;
  String _filtro = '';

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
    try {
      final lista = await widget.repo.getInsumos(widget.sucursalId);
      if (!mounted) return;
      setState(() { _insumos = lista; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _crear() async {
    final form = await showDialog<InsumoForm>(
        context: context, builder: (_) => const InsumoDialog());
    if (form == null) return;
    try {
      final nuevo = await widget.repo.guardarInsumo(widget.sucursalId,
          nombre: form.nombre, unidad: form.unidad,
          categoria: form.categoria, stockMinimo: form.stockMinimo,
          presentacion: form.presentacion);
      if (mounted) Navigator.pop(context, nuevo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _filtro.isEmpty
        ? _insumos
        : _insumos.where((i) => i.nombre.toLowerCase().contains(_filtro)).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _buscar,
              decoration: const InputDecoration(
                  hintText: 'Buscar insumo...', prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: AppColors.primary),
            title: const Text('Crear insumo nuevo',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
            onTap: _crear,
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : visibles.isEmpty
                        ? const Center(
                            child: Text('No hay insumos con ese nombre',
                                style: TextStyle(
                                    fontFamily: 'Poppins', color: AppColors.textSecondary)))
                        : ListView.builder(
                            controller: scroll,
                            itemCount: visibles.length,
                            itemBuilder: (_, i) {
                              final ins = visibles[i];
                              final ya = widget.yaElegidos.contains(ins.insumoId);
                              return ListTile(
                                title: Text(ins.nombre,
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                subtitle: Text(
                                    '${Unidades.nombre(ins.unidad)}'
                                    '${ins.categoria != null ? ' · ${ins.categoria}' : ''}'
                                    ' · hay ${Unidades.formato(ins.stock, ins.unidad, p: ins.presentacion)}',
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5)),
                                trailing: ya
                                    ? const Icon(Icons.check_circle, color: AppColors.success)
                                    : null,
                                onTap: () => Navigator.pop(context, ins),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// Historial de un plato o de un insumo: de dónde salió y a dónde fue cada
/// unidad. [formatear] muestra la cantidad en su unidad.
class HistorialSheet extends StatefulWidget {
  final String titulo;
  final Future<List<MovimientoInventarioModel>> Function() cargar;
  final String Function(double cantidad) formatear;

  const HistorialSheet({
    super.key,
    required this.titulo,
    required this.cargar,
    required this.formatear,
  });

  @override
  State<HistorialSheet> createState() => _HistorialSheetState();
}

class _HistorialSheetState extends State<HistorialSheet> {
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
      final movs = await widget.cargar();
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
      case 'COMPRA':    return (etiqueta: 'Compra',    color: AppColors.success, icono: Icons.shopping_cart_outlined);
      case 'VENTA':     return (etiqueta: 'Venta',     color: AppColors.primary, icono: Icons.point_of_sale_outlined);
      case 'ANULACION': return (etiqueta: 'Anulación', color: AppColors.info,    icono: Icons.undo);
      case 'MERMA':     return (etiqueta: 'Merma',     color: AppColors.error,   icono: Icons.delete_outline);
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
            child: Text('Historial · ${widget.titulo}', style: _titulo),
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
                                        Text('$signo${widget.formatear(m.cantidad)}',
                                            style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14, color: e.color)),
                                        Text('queda ${widget.formatear(m.stockResultante)}',
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

/// Aviso de error uniforme para las pantallas de inventario.
void mostrarError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ApiClient.parseError(e)),
    backgroundColor: AppColors.error,
  ));
}

void mostrarOk(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(mensaje),
    backgroundColor: AppColors.success,
  ));
}
