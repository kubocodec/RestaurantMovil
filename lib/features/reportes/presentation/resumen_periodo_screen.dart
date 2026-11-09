import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/network/api_client.dart';
import '../data/reportes_repository.dart';
import '../data/resumen_periodo_model.dart';
import 'cortesias_screen.dart';
import 'ordenes_anuladas_screen.dart';

/// Resumen general para decidir: cómo le fue al local en el período elegido
/// comparado con el anterior, qué platos se venden y cuáles no, cuándo se
/// vende, cómo se paga, quién vende y cuánto se pierde. Cada sección aparece
/// solo si el local tiene esos datos (costos, personas, propinas…).
class ResumenPeriodoScreen extends StatefulWidget {
  final String restaurantId;
  /// Sucursal con la que se abre; null = todas.
  final String? sucursalId;
  final List<SucursalModel> sucursales;

  const ResumenPeriodoScreen({
    super.key,
    required this.restaurantId,
    required this.sucursalId,
    required this.sucursales,
  });

  @override
  State<ResumenPeriodoScreen> createState() => _ResumenPeriodoScreenState();
}

enum _Periodo { hoy, semana, mes, mesAnterior, personalizado }

enum _VistaPlatos { masVendidos, menosVendidos, sinVenta, rentables }

class _ResumenPeriodoScreenState extends State<ResumenPeriodoScreen> {
  static const _todas = '__todas__';
  static const _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  /// Cuántos platos se listan antes de "Ver todos".
  static const _limite = 10;

  final _repo = ReportesRepository();
  final _fmt = NumberFormat('#,##0.00', 'es');

  _Periodo _periodo = _Periodo.mes;
  late DateTime _desde;
  late DateTime _hasta;
  late String _sucursal;
  ResumenPeriodoModel? _r;
  bool _loading = true;
  String? _error;

  _VistaPlatos _vista = _VistaPlatos.masVendidos;
  bool _porDinero = false;
  bool _verTodos = false;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _desde = DateTime(hoy.year, hoy.month, 1);
    _hasta = hoy;
    _sucursal = widget.sucursalId ?? _todas;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await _repo.getResumenPeriodo(
        sucursalId: _sucursal == _todas ? null : _sucursal,
        restaurantId: widget.restaurantId,
        desde: _desde,
        hasta: _hasta,
      );
      if (!mounted) return;
      setState(() { _r = r; _loading = false; _verTodos = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _cambiarPeriodo(_Periodo p) async {
    final hoy = DateTime.now();
    switch (p) {
      case _Periodo.hoy:
        _desde = hoy; _hasta = hoy;
      case _Periodo.semana:
        _desde = hoy.subtract(const Duration(days: 6)); _hasta = hoy;
      case _Periodo.mes:
        _desde = DateTime(hoy.year, hoy.month, 1); _hasta = hoy;
      case _Periodo.mesAnterior:
        _desde = DateTime(hoy.year, hoy.month - 1, 1);
        _hasta = DateTime(hoy.year, hoy.month, 0);
      case _Periodo.personalizado:
        final rango = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: hoy,
          initialDateRange: DateTimeRange(start: _desde, end: _hasta),
          locale: const Locale('es'),
          helpText: 'Elige el período (máximo un año)',
        );
        if (rango == null) return;
        if (rango.end.difference(rango.start).inDays > 365) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El período no puede ser mayor a un año'),
            backgroundColor: AppColors.warning,
          ));
          return;
        }
        _desde = rango.start; _hasta = rango.end;
    }
    setState(() => _periodo = p);
    _load();
  }

  String _rango(DateTime a, DateTime b) {
    final f = DateFormat('d MMM y', 'es');
    return DateUtils.isSameDay(a, b) ? f.format(a) : '${f.format(a)} — ${f.format(b)}';
  }

  String _m(double v) => '\$${_fmt.format(v)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Resumen del período'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFiltros(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? _buildError()
                      : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_rango(_desde, _hasta),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chipPeriodo('Hoy', _Periodo.hoy),
              _chipPeriodo('Últimos 7 días', _Periodo.semana),
              _chipPeriodo('Este mes', _Periodo.mes),
              _chipPeriodo('Mes anterior', _Periodo.mesAnterior),
              _chipPeriodo('Elegir fechas', _Periodo.personalizado),
            ],
          ),
          if (widget.sucursales.length > 1)
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _sucursal,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(
                        value: _todas,
                        child: Text('Todas las sucursales',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      ...widget.sucursales.map((s) => DropdownMenuItem(
                        value: s.sucursalId,
                        child: Text(s.nombre,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                      )),
                    ],
                    onChanged: (id) {
                      if (id == null || id == _sucursal) return;
                      setState(() => _sucursal = id);
                      _load();
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chipPeriodo(String label, _Periodo p) => _chip(label, _periodo == p, () => _cambiarPeriodo(p));

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontFamily: 'Poppins', fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppColors.textPrimary,
      ),
      selected: selected,
      selectedColor: AppColors.primary,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }

  Widget _buildBody() {
    final r = _r;
    if (r == null) return const SizedBox.shrink();
    final sinDatos = r.actual.comprobantes == 0 && r.actual.unidadesCortesia == 0;
    final unaSucursal = _sucursal != _todas;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // En tablet las tarjetas no se estiran de borde a borde.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildResultados(r),
                  const SizedBox(height: 14),
                  if (sinDatos)
                    _tarjeta(
                      titulo: 'Sin ventas en este período',
                      icono: Icons.info_outline,
                      children: const [
                        Text('Elige otro período o sucursal para ver platos, horarios y meseros.',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  _buildPlatos(r),
                  if (!sinDatos) ...[
                    const SizedBox(height: 14),
                    _buildCategorias(r),
                    const SizedBox(height: 14),
                    _buildCuando(r),
                    const SizedBox(height: 14),
                    _buildComo(r),
                    if (r.meseros.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildMeseros(r),
                    ],
                  ],
                  const SizedBox(height: 14),
                  _buildPerdidas(r, unaSucursal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. Cómo te fue ──────────────────────────────────────────────────────

  Widget _buildResultados(ResumenPeriodoModel r) {
    final a = r.actual, b = r.anterior;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.alcance,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 12)),
          const SizedBox(height: 2),
          const Text('Ventas',
              style: TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 13)),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              Text(_m(a.ventas),
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 30)),
              _Variacion(actual: a.ventas, anterior: b.ventas, claro: true),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 22,
            runSpacing: 12,
            children: [
              _Kpi(label: 'Comprobantes', valor: '${a.comprobantes}',
                  actual: a.comprobantes.toDouble(), anterior: b.comprobantes.toDouble()),
              if (a.ticketPromedio != null)
                _Kpi(label: 'Ticket promedio', valor: _m(a.ticketPromedio!),
                    actual: a.ticketPromedio, anterior: b.ticketPromedio),
              if (a.promedioPorMesa != null)
                _Kpi(label: 'Promedio por mesa', valor: _m(a.promedioPorMesa!),
                    actual: a.promedioPorMesa, anterior: b.promedioPorMesa),
              if (a.promedioPorPersona != null)
                _Kpi(label: 'Por persona', valor: _m(a.promedioPorPersona!),
                    actual: a.promedioPorPersona, anterior: b.promedioPorPersona),
              if (a.tieneCostos)
                _Kpi(label: 'Ganancia estimada', valor: _m(a.gananciaEstimada),
                    actual: a.gananciaEstimada, anterior: b.tieneCostos ? b.gananciaEstimada : null),
            ],
          ),
          const SizedBox(height: 12),
          Text('Comparado con ${_rango(r.desdeAnterior, r.hastaAnterior)}. '
              'Promedios sin propinas.',
              style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 11)),
          if (a.promedioPorPersona != null && a.mesasConPersonas < a.mesasEnSala)
            Text('Por persona: según ${a.mesasConPersonas} de ${a.mesasEnSala} mesas con el dato.',
                style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 11)),
        ],
      ),
    );
  }

  // ── 2. Platos ───────────────────────────────────────────────────────────

  Widget _buildPlatos(ResumenPeriodoModel r) {
    final vendidos = r.platos.where((p) => p.unidades > 0).toList();
    final hayRentables = vendidos.any((p) => p.ganancia != null);
    if (_vista == _VistaPlatos.rentables && !hayRentables) _vista = _VistaPlatos.masVendidos;
    final totalVentas = vendidos.fold<double>(0, (s, p) => s + p.ventas);
    final totalUnidades = vendidos.fold<int>(0, (s, p) => s + p.unidades);

    final List<Widget> filas;
    String? nota;
    switch (_vista) {
      case _VistaPlatos.masVendidos:
      case _VistaPlatos.menosVendidos:
        final orden = [...vendidos]..sort((x, y) => _porDinero
            ? y.ventas.compareTo(x.ventas)
            : (y.unidades != x.unidades ? y.unidades.compareTo(x.unidades) : y.ventas.compareTo(x.ventas)));
        final lista = _vista == _VistaPlatos.masVendidos ? orden : orden.reversed.toList();
        final maximo = orden.isEmpty ? 0.0 : (_porDinero ? orden.first.ventas : orden.first.unidades.toDouble());
        final visibles = _verTodos ? lista : lista.take(_limite).toList();
        filas = [
          for (final p in visibles)
            _FilaPlato(
              puesto: _vista == _VistaPlatos.masVendidos
                  ? lista.indexOf(p) + 1
                  : orden.length - lista.indexOf(p),
              nombre: p.nombre,
              categoria: p.categoria,
              detalle: '${p.unidades} u · ${_m(p.ventas)} · '
                  '${_pct(_porDinero ? p.ventas : p.unidades.toDouble(), _porDinero ? totalVentas : totalUnidades.toDouble())}'
                  '${p.unidadesCortesia > 0 ? ' · ${p.unidadesCortesia} regalado${p.unidadesCortesia == 1 ? '' : 's'}' : ''}',
              fraccion: maximo > 0 ? (_porDinero ? p.ventas : p.unidades.toDouble()) / maximo : 0,
              color: _vista == _VistaPlatos.masVendidos ? AppColors.success : AppColors.warning,
            ),
        ];
        if (lista.length > _limite) filas.add(_botonVerTodos(lista.length));
        nota = 'Precio de carta con IVA. El % es sobre el total de platos vendidos.';
      case _VistaPlatos.sinVenta:
        final visibles = _verTodos ? r.sinVenta : r.sinVenta.take(_limite * 2).toList();
        filas = [
          if (r.sinVenta.isEmpty)
            const Text('Todos los platos del menú se vendieron al menos una vez.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.success)),
          for (final p in visibles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  const Icon(Icons.remove_circle_outline, size: 18, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nombre,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(p.disponible ? p.categoria : '${p.categoria} · marcado como no disponible',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ];
        if (r.sinVenta.length > _limite * 2 && !_verTodos) filas.add(_botonVerTodos(r.sinVenta.length));
        nota = 'Platos activos del menú que no se vendieron en el período: candidatos a promocionar '
            'o a sacar del menú.';
      case _VistaPlatos.rentables:
        final orden = vendidos.where((p) => p.ganancia != null).toList()
          ..sort((x, y) => y.ganancia!.compareTo(x.ganancia!));
        final maximo = orden.isEmpty ? 0.0 : orden.first.ganancia!;
        final visibles = _verTodos ? orden : orden.take(_limite).toList();
        filas = [
          for (final p in visibles)
            _FilaPlato(
              puesto: orden.indexOf(p) + 1,
              nombre: p.nombre,
              categoria: p.categoria,
              detalle: 'Deja ${_m(p.ganancia!)} · ${p.unidades} u · '
                  'margen ${_pct(p.ganancia!, p.ventasSinIva)}',
              fraccion: maximo > 0 ? (p.ganancia! / maximo).clamp(0, 1).toDouble() : 0,
              color: AppColors.primary,
            ),
        ];
        if (orden.length > _limite) filas.add(_botonVerTodos(orden.length));
        nota = 'Ventas sin IVA menos el costo registrado de cada plato. '
            'Solo platos con costo.';
    }

    return _tarjeta(
      titulo: 'Platos',
      icono: Icons.restaurant_menu_outlined,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _chip('Más vendidos', _vista == _VistaPlatos.masVendidos, () => _verVista(_VistaPlatos.masVendidos)),
            _chip('Menos vendidos', _vista == _VistaPlatos.menosVendidos, () => _verVista(_VistaPlatos.menosVendidos)),
            _chip('Sin ventas (${r.sinVenta.length})', _vista == _VistaPlatos.sinVenta,
                () => _verVista(_VistaPlatos.sinVenta)),
            if (hayRentables)
              _chip('Más rentables', _vista == _VistaPlatos.rentables, () => _verVista(_VistaPlatos.rentables)),
          ],
        ),
        if (_vista == _VistaPlatos.masVendidos || _vista == _VistaPlatos.menosVendidos) ...[
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Text('Ordenar por:',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
              _chip('Unidades', !_porDinero, () => setState(() => _porDinero = false)),
              _chip('Dinero', _porDinero, () => setState(() => _porDinero = true)),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (filas.isEmpty)
          const Text('No hubo platos vendidos en este período.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary))
        else
          ...filas,
        const SizedBox(height: 6),
        Text(nota, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  void _verVista(_VistaPlatos v) => setState(() { _vista = v; _verTodos = false; });

  Widget _botonVerTodos(int total) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () => setState(() => _verTodos = !_verTodos),
      child: Text(_verTodos ? 'Ver menos' : 'Ver todos ($total)'),
    ),
  );

  String _pct(double parte, double total) =>
      total > 0 ? '${(parte / total * 100).toStringAsFixed(parte / total >= 0.1 ? 0 : 1)}%' : '—';

  // ── 3. Por categoría ────────────────────────────────────────────────────

  Widget _buildCategorias(ResumenPeriodoModel r) {
    final porCat = <String, double>{};
    for (final p in r.platos) {
      porCat[p.categoria] = (porCat[p.categoria] ?? 0) + p.ventas;
    }
    final orden = porCat.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = orden.fold<double>(0, (s, e) => s + e.value);
    return _tarjeta(
      titulo: 'Por categoría',
      icono: Icons.category_outlined,
      children: [
        for (final e in orden)
          _Barra(
            etiqueta: e.key,
            valor: '${_m(e.value)} · ${_pct(e.value, total)}',
            fraccion: total > 0 ? e.value / orden.first.value : 0,
          ),
      ],
    );
  }

  // ── 4. Cuándo se vende ──────────────────────────────────────────────────

  Widget _buildCuando(ResumenPeriodoModel r) {
    // Por día: promedio por cada lunes, martes… del período, porque un mes
    // puede tener cinco sábados y cuatro lunes.
    final ventasDia = List<double>.filled(7, 0);
    final ventasHora = <int, double>{};
    final ordenesHora = <int, int>{};
    for (final h in r.porHora) {
      if (h.dia >= 1 && h.dia <= 7) ventasDia[h.dia - 1] += h.ventas;
      ventasHora[h.hora] = (ventasHora[h.hora] ?? 0) + h.ventas;
      ordenesHora[h.hora] = (ordenesHora[h.hora] ?? 0) + h.ordenes;
    }
    final promDia = [
      for (var i = 0; i < 7; i++)
        r.diasDelPeriodo[i] > 0 ? ventasDia[i] / r.diasDelPeriodo[i] : null,
    ];
    final maxDia = promDia.whereType<double>().fold<double>(0, (m, v) => v > m ? v : m);
    final mejorDia = maxDia > 0 ? promDia.indexOf(maxDia) : -1;

    final horas = ventasHora.keys.toList()..sort();
    final maxHora = ventasHora.values.fold<double>(0, (m, v) => v > m ? v : m);
    final horaPico = ventasHora.entries.isEmpty
        ? null
        : ventasHora.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    String h2(int h) => '${h.toString().padLeft(2, '0')}:00';

    return _tarjeta(
      titulo: 'Cuándo se vende',
      icono: Icons.schedule_outlined,
      children: [
        if (mejorDia >= 0)
          _Destacado(texto: 'Día más fuerte: ${_dias[mejorDia]} '
              '(${_m(maxDia)} en promedio)'),
        if (horaPico != null)
          _Destacado(texto: 'Hora pico: ${h2(horaPico)} a ${h2(horaPico + 1)} '
              '(${ordenesHora[horaPico]} órdenes)'),
        const SizedBox(height: 8),
        const _Subtitulo('Promedio de ventas por día'),
        for (var i = 0; i < 7; i++)
          if (promDia[i] != null)
            _Barra(
              etiqueta: _dias[i],
              valor: _m(promDia[i]!),
              fraccion: maxDia > 0 ? promDia[i]! / maxDia : 0,
              resaltar: i == mejorDia,
            ),
        const SizedBox(height: 10),
        const _Subtitulo('Ventas por hora en que se tomó la orden'),
        for (final h in horas)
          _Barra(
            etiqueta: h2(h),
            valor: '${_m(ventasHora[h]!)} · ${ordenesHora[h]} órd.',
            fraccion: maxHora > 0 ? ventasHora[h]! / maxHora : 0,
            resaltar: h == horaPico,
          ),
        const SizedBox(height: 4),
        const Text('Sin propinas.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  // ── 5. Cómo se vende ────────────────────────────────────────────────────

  Widget _buildComo(ResumenPeriodoModel r) {
    String tipo(String t) => switch (t) {
      'EN_MESA' => 'En mesa',
      'PARA_LLEVAR' => 'Para llevar',
      _ => _capitalizar(t.replaceAll('_', ' ')),
    };
    final totalTipo = r.porTipo.fold<double>(0, (s, t) => s + t.ventas);
    final maxTipo = r.porTipo.fold<double>(0, (m, t) => t.ventas > m ? t.ventas : m);
    final totalPago = r.metodosPago.fold<double>(0, (s, m) => s + m.monto);
    final maxPago = r.metodosPago.fold<double>(0, (m, x) => x.monto > m ? x.monto : m);
    return _tarjeta(
      titulo: 'Cómo se vende',
      icono: Icons.point_of_sale_outlined,
      children: [
        const _Subtitulo('Mesa o para llevar (sin propinas)'),
        for (final t in r.porTipo)
          _Barra(
            etiqueta: tipo(t.tipo),
            valor: '${_m(t.ventas)} · ${_pct(t.ventas, totalTipo)} · ${t.ordenes} órd.',
            fraccion: maxTipo > 0 ? t.ventas / maxTipo : 0,
          ),
        if (r.metodosPago.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _Subtitulo('Métodos de pago'),
          for (final m in r.metodosPago)
            _Barra(
              etiqueta: _capitalizar(m.metodo),
              valor: '${_m(m.monto)} · ${_pct(m.monto, totalPago)}',
              fraccion: maxPago > 0 ? m.monto / maxPago : 0,
            ),
          if (r.metodosPago.any((m) => m.metodo == 'ADELANTOS'))
            const Text('Adelantos: dinero recibido antes, en la reserva.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
        ],
      ],
    );
  }

  static String _capitalizar(String s) {
    final t = s.trim().toLowerCase();
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  // ── 6. Personal ─────────────────────────────────────────────────────────

  Widget _buildMeseros(ResumenPeriodoModel r) {
    final hayPropinas = r.meseros.any((m) => m.propinas > 0);
    final maximo = r.meseros.fold<double>(0, (m, x) => x.ventas > m ? x.ventas : m);
    return _tarjeta(
      titulo: 'Personal',
      icono: Icons.badge_outlined,
      children: [
        for (final m in r.meseros)
          _Barra(
            etiqueta: m.nombre,
            valor: '${_m(m.ventas)} · ${m.ordenes} órd.'
                '${hayPropinas ? ' · propinas ${_m(m.propinas)}' : ''}',
            fraccion: maximo > 0 ? m.ventas / maximo : 0,
          ),
        const SizedBox(height: 4),
        const Text('Quien tomó la orden, no quien cobró. Ventas sin propinas.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  // ── 7. Pérdidas ─────────────────────────────────────────────────────────

  Widget _buildPerdidas(ResumenPeriodoModel r, bool unaSucursal) {
    final a = r.actual;
    final sucursalId = _sucursal;
    return _tarjeta(
      titulo: 'Pérdidas y regalos',
      icono: Icons.trending_down_outlined,
      children: [
        _FilaMonto(
          etiqueta: 'Órdenes anuladas (${r.ordenesAnuladas})',
          valor: _m(r.valorAnulado),
          onTap: unaSucursal
              ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OrdenesAnuladasScreen(sucursalId: sucursalId)))
              : null,
        ),
        _FilaMonto(
          etiqueta: 'Cortesías (${a.unidadesCortesia})',
          valor: _m(a.valorCortesias),
          onTap: unaSucursal
              ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CortesiasScreen(sucursalId: sucursalId)))
              : null,
        ),
        _FilaMonto(etiqueta: 'Descuentos', valor: _m(a.descuentos)),
        const SizedBox(height: 4),
        const Text('Anuladas y cortesías a precio de carta sin IVA: no son ventas ni entran a caja.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _tarjeta({required String titulo, required IconData icono, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
      ),
    );
  }
}

/// ▲ 12% / ▼ 5% contra el período anterior. Sin base de comparación no
/// muestra nada (un "+100%" desde cero no dice nada útil).
class _Variacion extends StatelessWidget {
  final double? actual;
  final double? anterior;
  final bool claro;
  const _Variacion({required this.actual, required this.anterior, this.claro = false});

  @override
  Widget build(BuildContext context) {
    final a = actual, b = anterior;
    if (a == null || b == null || b <= 0) return const SizedBox.shrink();
    final pct = (a - b) / b * 100;
    final sube = pct >= 0;
    final color = claro
        ? (sube ? const Color(0xFFB9F6CA) : const Color(0xFFFFCDD2))
        : (sube ? AppColors.success : AppColors.error);
    return Text('${sube ? '▲' : '▼'} ${pct.abs().toStringAsFixed(pct.abs() >= 10 ? 0 : 1)}%',
        style: TextStyle(color: color, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12));
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String valor;
  final double? actual;
  final double? anterior;
  const _Kpi({required this.label, required this.valor, this.actual, this.anterior});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(valor,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
            _Variacion(actual: actual, anterior: anterior, claro: true),
          ],
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 10)),
      ],
    );
  }
}

class _FilaPlato extends StatelessWidget {
  final int puesto;
  final String nombre;
  final String categoria;
  final String detalle;
  final double fraccion;
  final Color color;
  const _FilaPlato({
    required this.puesto,
    required this.nombre,
    required this.categoria,
    required this.detalle,
    required this.fraccion,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 28),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$puesto',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                Text('$categoria · $detalle',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraccion.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final double fraccion;
  final bool resaltar;
  const _Barra({required this.etiqueta, required this.valor, required this.fraccion, this.resaltar = false});

  @override
  Widget build(BuildContext context) {
    final color = resaltar ? AppColors.success : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Etiqueta y valor bajan de línea con el texto en "Muy grande".
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              Text(etiqueta,
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: resaltar ? FontWeight.w700 : FontWeight.w600)),
              Text(valor,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraccion.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Destacado extends StatelessWidget {
  final String texto;
  const _Destacado({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 6),
          Expanded(
            child: Text(texto,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Subtitulo extends StatelessWidget {
  final String texto;
  const _Subtitulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(texto,
        style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
  );
}

class _FilaMonto extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final VoidCallback? onTap;
  const _FilaMonto({required this.etiqueta, required this.valor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(etiqueta,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
            ),
            Text(valor,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
            ],
          ],
        ),
      ),
    );
  }
}
