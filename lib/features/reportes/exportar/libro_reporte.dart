import '../../../core/exportar/xlsx_minimo.dart';
import '../../inventario/data/unidades.dart';
import 'datos_exportacion.dart';

// Arma las hojas del Excel a partir de lo reunido. Función pura: sin red ni
// widgets, para poder probarla con datos inventados.
//
// Los totales son fórmulas con el valor ya calculado: sin el valor, Excel
// muestra 0 en Vista protegida, donde no recalcula. Las fórmulas van en
// inglés y con comas, que es como se guardan en el archivo.

const etiquetaAnulada = 'Anulada';
const _si = 'Sí';
const _no = 'No';
const _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

enum _T { texto, negrita, entero, dinero, porcentaje, fecha, fechaHora, cantidad }

class _Col {
  final String titulo;
  final double ancho;
  final _T tipo;
  final bool suma;
  const _Col(this.titulo, this.ancho, [this.tipo = _T.texto, this.suma = false]);
}

Estilo _estilo(_T t) => switch (t) {
      _T.texto => Estilo.normal,
      _T.negrita => Estilo.negrita,
      _T.entero => Estilo.entero,
      _T.dinero => Estilo.dinero,
      _T.porcentaje => Estilo.porcentaje,
      _T.fecha => Estilo.fecha,
      _T.fechaHora => Estilo.fechaHora,
      _T.cantidad => Estilo.cantidad,
    };

Estilo _estiloTotal(_T t) => switch (t) {
      _T.entero => Estilo.totalEntero,
      _T.dinero => Estilo.totalDinero,
      _T.cantidad => Estilo.totalCantidad,
      _ => Estilo.totalEtiqueta,
    };

/// Dinero a centavos: los precios llegan con 6 decimales (precio con IVA ÷
/// 1.15) y en Excel se verían como 2.608696.
double _c(num v) => (v * 100).round() / 100;

/// Cantidades a milésimas, para que 0.1 + 0.2 no salga 0.30000000000000004.
double _q(num v) => (v * 1000).round() / 1000;

Object? _normalizar(Object? v, _T tipo) {
  if (v == null) return null;
  if (v is bool) return v ? _si : _no;
  if (v is num) {
    if (tipo == _T.dinero) return _c(v);
    if (tipo == _T.cantidad) return _q(v);
  }
  return v;
}

String _fecha(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

String _capitalizar(String s) {
  final t = s.trim().toLowerCase().replaceAll('_', ' ');
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

String _periodo(DatosExportacion d) => '${d.alcance} · del ${_fecha(d.desde)} al ${_fecha(d.hasta)}';

/// Hoja con título en la fila 1, período en la 2 y la tabla desde la 4.
Hoja _hoja(String nombre, String titulo, DatosExportacion d, List<_Col> cols, {String? detalle}) {
  final h = Hoja(nombre, [for (final c in cols) c.ancho]);
  h.fila([Celda(titulo, Estilo.titulo)]);
  h.fila([Celda(detalle == null ? _periodo(d) : '${_periodo(d)} · $detalle', Estilo.nota)]);
  h.fila([]);
  return h;
}

/// Agrega una tabla a [h] desde la fila actual. Si [fija], sus encabezados
/// quedan congelados y con filtro (solo una tabla por hoja puede).
///
/// [excluir]: pares (columna, valor) que no entran en los totales, como los
/// comprobantes anulados o las cortesías. Sin exclusiones el total es
/// SUBTOTAL(109, …), que además sigue al filtro; con ellas, SUMIFS.
void _tabla(
  Hoja h,
  List<_Col> cols,
  List<List<Object?>> filas, {
  bool fija = true,
  List<(int, String)> excluir = const [],
  String vacio = 'No hay datos en este período.',
}) {
  final enc = h.filas.length;
  h.fila([for (final c in cols) Celda(c.titulo, Estilo.encabezado)]);
  if (fija) h.filaEncabezado = enc;
  if (filas.isEmpty) {
    h.fila([Celda(vacio, Estilo.nota)]);
    return;
  }
  for (final f in filas) {
    h.fila([
      for (var i = 0; i < cols.length; i++)
        Celda(_normalizar(i < f.length ? f[i] : null, cols[i].tipo), _estilo(cols[i].tipo)),
    ]);
  }
  final ultima = enc + filas.length;
  if (fija) h.ultimaFilaDatos = ultima;
  if (!cols.skip(1).any((c) => c.suma)) return;

  // Filas de Excel (desde 1) de los datos.
  final r1 = enc + 2, r2 = ultima + 1;
  bool entra(List<Object?> f) => excluir.every((x) => f[x.$1] != x.$2);
  h.fila([
    for (var i = 0; i < cols.length; i++)
      if (i == 0)
        Celda(excluir.isEmpty ? 'Total' : 'Total (sin anuladas${excluir.length > 1 ? ' ni cortesías' : ''})',
            Estilo.totalEtiqueta)
      else if (!cols[i].suma)
        const Celda(null, Estilo.totalEtiqueta)
      else
        () {
          final col = letraColumna(i);
          var total = 0.0;
          for (final f in filas) {
            final v = f[i];
            if (v is num && entra(f)) total += v.toDouble();
          }
          final valor = cols[i].tipo == _T.dinero ? _c(total) : _q(total);
          final formula = excluir.isEmpty
              ? 'SUBTOTAL(109,$col$r1:$col$r2)'
              : 'SUMIFS($col$r1:$col$r2,${excluir.map((x) {
                  final c = letraColumna(x.$1);
                  return '$c$r1:$c$r2,"<>${x.$2}"';
                }).join(',')})';
          return Celda(valor, _estiloTotal(cols[i].tipo), formula);
        }(),
  ]);
}

/// Antepone la columna Sucursal cuando el libro abarca varias.
List<_Col> _conSucursal(DatosExportacion d, List<_Col> cols) =>
    d.variasSucursales ? [const _Col('Sucursal', 18), ...cols] : cols;

List<Object?> _fila(DatosExportacion d, String sucursal, List<Object?> f) =>
    d.variasSucursales ? [sucursal, ...f] : f;

/// Índice de una columna contando la de Sucursal, si está.
int _ix(DatosExportacion d, int i) => d.variasSucursales ? i + 1 : i;

/// kg, L o u: la unidad en que la gente piensa el insumo, con su factor
/// desde la base (g, ml, u).
(double, String) _unidad(String base) => switch (base) {
      'GRAMO' => (1000, 'kg'),
      'MILILITRO' => (1000, 'L'),
      _ => (1, 'u'),
    };

/// Todas las hojas pedidas, en el orden de [SeccionExcel].
List<Hoja> armarLibro(DatosExportacion d) {
  final hojas = <Hoja>[_resumen(d)];
  final r = d.resumen;
  final hayInventario = d.conInventario.isNotEmpty;
  for (final s in d.secciones.toList()..sort((a, b) => a.index.compareTo(b.index))) {
    if (s.delResumen && s != SeccionExcel.resumen && r == null) continue;
    if (s.esInventario && !hayInventario) continue;
    switch (s) {
      case SeccionExcel.resumen:
        break; // siempre va primera
      case SeccionExcel.platos:
        hojas.add(_platos(d));
      case SeccionExcel.categorias:
        hojas.add(_categorias(d));
      case SeccionExcel.sinVenta:
        hojas.add(_sinVenta(d));
      case SeccionExcel.diaHora:
        hojas.add(_diaHora(d));
      case SeccionExcel.tipo:
        hojas.add(_tipo(d));
      case SeccionExcel.metodosPago:
        hojas.add(_metodos(d));
      case SeccionExcel.personal:
        hojas.add(_personal(d));
      case SeccionExcel.ventasDia:
        hojas.add(_ventasDia(d));
      case SeccionExcel.comprobantes:
        hojas.add(_comprobantes(d));
      case SeccionExcel.detalleVendido:
        hojas.add(_detalle(d));
      case SeccionExcel.cierres:
        hojas
          ..add(_cierres(d))
          ..add(_movimientos(d));
      case SeccionExcel.cortesias:
        hojas.add(_cortesias(d));
      case SeccionExcel.anuladas:
        hojas.add(_anuladas(d));
      case SeccionExcel.insumos:
        hojas.add(_insumos(d));
      case SeccionExcel.platosStock:
        hojas.add(_platosStock(d));
      case SeccionExcel.compras:
        hojas.add(_compras(d));
      case SeccionExcel.proveedores:
        hojas.add(_proveedores(d));
    }
  }
  return hojas;
}

/// Nombre del archivo: "Wasi - Sucursal Centro - 2026-11-01 a 2026-11-12.xlsx".
String nombreArchivo(DatosExportacion d) {
  String iso(DateTime f) =>
      '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';
  final alcance = d.alcance.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final periodo = iso(d.desde) == iso(d.hasta) ? iso(d.desde) : '${iso(d.desde)} a ${iso(d.hasta)}';
  return 'Wasi - ${alcance.isEmpty ? 'Reporte' : alcance} - $periodo.xlsx';
}

// ── Resumen ─────────────────────────────────────────────────────────────────

Hoja _resumen(DatosExportacion d) {
  final h = Hoja('Resumen', [40, 18, 18, 14]);
  h.fila([const Celda('Wasi · Reporte', Estilo.titulo)]);
  h.fila([Celda(_periodo(d), Estilo.nota)]);
  h.fila([Celda('Generado el ${_fecha(d.generado)} a las '
      '${d.generado.hour.toString().padLeft(2, '0')}:${d.generado.minute.toString().padLeft(2, '0')}', Estilo.nota)]);
  h.fila([]);

  final r = d.resumen;
  final notas = <String>[...d.notas];
  if (r != null) {
    final a = r.actual, b = r.anterior;
    h.fila(const [
      Celda('Indicador', Estilo.encabezado),
      Celda('Este período', Estilo.encabezado),
      Celda('Período anterior', Estilo.encabezado),
      Celda('Variación', Estilo.encabezado),
    ]);
    h.filaEncabezado = h.filas.length - 1;
    void fila(String nombre, num? actual, num? anterior, Estilo e) {
      final variacion = (actual != null && anterior != null && anterior != 0)
          ? (actual - anterior) / anterior.abs()
          : null;
      Object? v(num? x) => x == null ? null : (e == Estilo.dinero ? _c(x) : x);
      h.fila([Celda(nombre), Celda(v(actual), e), Celda(v(anterior), e), Celda(variacion, Estilo.porcentaje)]);
    }

    // Las mismas cuentas que la pantalla (getters de TotalesPeriodo).
    fila('Ventas (con IVA)', a.ventas, b.ventas, Estilo.dinero);
    fila('Propinas', a.propinas, b.propinas, Estilo.dinero);
    fila('IVA', a.iva, b.iva, Estilo.dinero);
    fila('Descuentos (sin cortesías)', a.descuentos, b.descuentos, Estilo.dinero);
    fila('Comprobantes', a.comprobantes, b.comprobantes, Estilo.entero);
    if (a.ticketPromedio != null) fila('Ticket promedio', a.ticketPromedio, b.ticketPromedio, Estilo.dinero);
    if (a.promedioPorMesa != null) fila('Promedio por mesa', a.promedioPorMesa, b.promedioPorMesa, Estilo.dinero);
    if (a.promedioPorPersona != null) {
      fila('Promedio por persona', a.promedioPorPersona, b.promedioPorPersona, Estilo.dinero);
    }
    fila('Mesas y pedidos cobrados', a.mesas, b.mesas, Estilo.entero);
    if (a.personas > 0) fila('Personas atendidas', a.personas, b.personas, Estilo.entero);
    if (a.tieneCostos) {
      fila('Costo de lo vendido', a.costo, b.tieneCostos ? b.costo : null, Estilo.dinero);
      fila('Ganancia estimada', a.gananciaEstimada, b.tieneCostos ? b.gananciaEstimada : null, Estilo.dinero);
    }
    fila('Cortesías (unidades)', a.unidadesCortesia, b.unidadesCortesia, Estilo.entero);
    fila('Cortesías (valor de carta)', a.valorCortesias, b.valorCortesias, Estilo.dinero);
    fila('Órdenes anuladas', r.ordenesAnuladas, null, Estilo.entero);
    fila('Valor anulado', r.valorAnulado, null, Estilo.dinero);
    h.ultimaFilaDatos = h.filas.length - 1;

    notas.insert(0, 'Comparado con el período anterior de igual duración: del '
        '${_fecha(r.desdeAnterior)} al ${_fecha(r.hastaAnterior)}. Promedios sin propinas.');
    if (a.promedioPorPersona != null && a.mesasConPersonas < a.mesasEnSala) {
      notas.add('Promedio por persona: según ${a.mesasConPersonas} de ${a.mesasEnSala} mesas con el dato.');
    }
  } else if (d.secciones.any((s) => s.delResumen)) {
    h.fila([const Celda('No se pudo cargar el resumen del período.', Estilo.nota)]);
  }

  if (notas.isNotEmpty) {
    h.fila([]);
    h.fila([const Celda('Notas', Estilo.negrita)]);
    for (final n in notas) {
      h.fila([Celda(n, Estilo.nota)]);
    }
  }
  return h;
}

// ── Del resumen del período ─────────────────────────────────────────────────

Hoja _platos(DatosExportacion d) {
  final r = d.resumen!;
  final costos = r.actual.tieneCostos;
  final lista = r.platos.where((p) => p.unidades > 0 || p.unidadesCortesia > 0).toList()
    ..sort((a, b) => b.unidades != a.unidades ? b.unidades.compareTo(a.unidades) : b.ventas.compareTo(a.ventas));
  final totalVentas = lista.fold<double>(0, (s, p) => s + p.ventas);
  final cols = [
    const _Col('Plato', 32),
    const _Col('Categoría', 20),
    const _Col('Unidades', 11, _T.entero, true),
    const _Col('Ventas con IVA', 15, _T.dinero, true),
    const _Col('Ventas sin IVA', 15, _T.dinero, true),
    if (costos) ...const [
      _Col('Costo unitario', 14, _T.dinero),
      _Col('Costo total', 14, _T.dinero, true),
      _Col('Ganancia', 14, _T.dinero, true),
      _Col('Margen', 10, _T.porcentaje),
    ],
    const _Col('Unidades regaladas', 12, _T.entero, true),
    const _Col('% de las ventas', 12, _T.porcentaje),
  ];
  final h = _hoja('Platos vendidos', 'Platos vendidos', d, cols,
      detalle: 'precio de carta; las cortesías van aparte');
  _tabla(h, cols, [
    for (final p in lista)
      [
        p.nombre,
        p.categoria,
        p.unidades,
        p.ventas,
        p.ventasSinIva,
        if (costos) ...[
          p.costo,
          p.costo == null ? null : p.costo! * p.unidades,
          p.ganancia,
          (p.ganancia != null && p.ventasSinIva > 0) ? p.ganancia! / p.ventasSinIva : null,
        ],
        p.unidadesCortesia,
        totalVentas > 0 ? p.ventas / totalVentas : null,
      ],
  ]);
  return h;
}

Hoja _categorias(DatosExportacion d) {
  final porCat = <String, (int, int, double)>{}; // platos, unidades, ventas
  for (final p in d.resumen!.platos.where((p) => p.unidades > 0)) {
    final x = porCat[p.categoria] ?? (0, 0, 0.0);
    porCat[p.categoria] = (x.$1 + 1, x.$2 + p.unidades, x.$3 + p.ventas);
  }
  final orden = porCat.entries.toList()..sort((a, b) => b.value.$3.compareTo(a.value.$3));
  final total = orden.fold<double>(0, (s, e) => s + e.value.$3);
  const cols = [
    _Col('Categoría', 28),
    _Col('Platos distintos', 14, _T.entero, true),
    _Col('Unidades', 12, _T.entero, true),
    _Col('Ventas con IVA', 16, _T.dinero, true),
    _Col('% de las ventas', 14, _T.porcentaje),
  ];
  final h = _hoja('Categorías', 'Ventas por categoría', d, cols);
  _tabla(h, cols, [
    for (final e in orden) [e.key, e.value.$1, e.value.$2, e.value.$3, total > 0 ? e.value.$3 / total : null],
  ]);
  return h;
}

Hoja _sinVenta(DatosExportacion d) {
  const cols = [_Col('Plato', 34), _Col('Categoría', 22), _Col('Disponible en el menú', 18)];
  final h = _hoja('Platos sin ventas', 'Platos del menú que no se vendieron', d, cols);
  _tabla(h, cols, [for (final p in d.resumen!.sinVenta) [p.nombre, p.categoria, p.disponible]],
      vacio: 'Todos los platos del menú se vendieron al menos una vez.');
  return h;
}

Hoja _diaHora(DatosExportacion d) {
  final r = d.resumen!;
  const cols = [
    _Col('Día', 14),
    _Col('Hora', 10),
    _Col('Órdenes', 12, _T.entero, true),
    _Col('Ventas', 16, _T.dinero, true),
  ];
  final h = _hoja('Día y hora', 'Ventas por día y hora en que se tomó la orden', d, cols, detalle: 'sin propinas');
  final lista = [...r.porHora]..sort((a, b) => a.dia != b.dia ? a.dia.compareTo(b.dia) : a.hora.compareTo(b.hora));
  _tabla(h, cols, [
    for (final x in lista)
      [x.dia >= 1 && x.dia <= 7 ? _dias[x.dia - 1] : '', '${x.hora.toString().padLeft(2, '0')}:00', x.ordenes, x.ventas],
  ]);

  // Un mes puede tener cinco sábados y cuatro lunes: el promedio por día de
  // la semana divide por cuántos hubo de cada uno, igual que la pantalla.
  final ventasDia = List<double>.filled(7, 0);
  final ordenesDia = List<int>.filled(7, 0);
  for (final x in r.porHora) {
    if (x.dia >= 1 && x.dia <= 7) {
      ventasDia[x.dia - 1] += x.ventas;
      ordenesDia[x.dia - 1] += x.ordenes;
    }
  }
  h.fila([]);
  h.fila([const Celda('Promedio por día de la semana', Estilo.negrita)]);
  const cols2 = [
    _Col('Día', 14),
    _Col('Veces en el período', 10, _T.entero),
    _Col('Órdenes', 12, _T.entero),
    _Col('Ventas', 16, _T.dinero),
  ];
  _tabla(h, [...cols2, const _Col('Promedio por día', 16, _T.dinero)], [
    for (var i = 0; i < 7; i++)
      if (r.diasDelPeriodo[i] > 0)
        [_dias[i], r.diasDelPeriodo[i], ordenesDia[i], ventasDia[i], ventasDia[i] / r.diasDelPeriodo[i]],
  ], fija: false);
  return h;
}

Hoja _tipo(DatosExportacion d) {
  final r = d.resumen!;
  final total = r.porTipo.fold<double>(0, (s, t) => s + t.ventas);
  String nombre(String t) => switch (t) {
        'EN_MESA' => 'En mesa',
        'PARA_LLEVAR' => 'Para llevar',
        _ => _capitalizar(t),
      };
  const cols = [
    _Col('Tipo', 20),
    _Col('Órdenes', 12, _T.entero, true),
    _Col('Ventas', 16, _T.dinero, true),
    _Col('%', 10, _T.porcentaje),
  ];
  final h = _hoja('Mesa y para llevar', 'En mesa o para llevar', d, cols, detalle: 'sin propinas');
  _tabla(h, cols, [
    for (final t in r.porTipo) [nombre(t.tipo), t.ordenes, t.ventas, total > 0 ? t.ventas / total : null],
  ]);
  return h;
}

Hoja _metodos(DatosExportacion d) {
  final r = d.resumen!;
  final total = r.metodosPago.fold<double>(0, (s, m) => s + m.monto);
  const cols = [_Col('Método de pago', 24), _Col('Monto', 16, _T.dinero, true), _Col('%', 10, _T.porcentaje)];
  final h = _hoja('Métodos de pago', 'Métodos de pago', d, cols);
  _tabla(h, cols, [
    for (final m in r.metodosPago) [_capitalizar(m.metodo), m.monto, total > 0 ? m.monto / total : null],
  ]);
  if (r.metodosPago.any((m) => m.metodo == 'ADELANTOS')) {
    h.fila([const Celda('Adelantos: dinero recibido antes, en la reserva.', Estilo.nota)]);
  }
  return h;
}

Hoja _personal(DatosExportacion d) {
  final r = d.resumen!;
  final propinas = r.meseros.any((m) => m.propinas > 0);
  final cols = [
    const _Col('Mesero', 24),
    const _Col('Órdenes', 12, _T.entero, true),
    const _Col('Ventas (sin propinas)', 18, _T.dinero, true),
    if (propinas) const _Col('Propinas', 14, _T.dinero, true),
  ];
  final h = _hoja('Personal', 'Ventas por mesero', d, cols, detalle: 'quien tomó la orden, no quien cobró');
  _tabla(h, cols, [
    for (final m in [...r.meseros]..sort((a, b) => b.ventas.compareTo(a.ventas)))
      [m.nombre, m.ordenes, m.ventas, if (propinas) m.propinas],
  ]);
  return h;
}

// ── Día por día ─────────────────────────────────────────────────────────────

Hoja _ventasDia(DatosExportacion d) {
  final personas = d.ventasDia.any((x) => x.$3.totalPersonas > 0);
  final costos = d.ventasDia.any((x) => x.$3.totalCosto > 0);
  final cols = _conSucursal(d, [
    const _Col('Fecha', 12, _T.fecha),
    const _Col('Órdenes', 10, _T.entero, true),
    const _Col('Comprobantes', 13, _T.entero, true),
    const _Col('Mesas cobradas', 13, _T.entero, true),
    if (personas) const _Col('Personas', 10, _T.entero, true),
    const _Col('Ventas', 14, _T.dinero, true),
    const _Col('Descuentos', 13, _T.dinero, true),
    const _Col('IVA', 12, _T.dinero, true),
    const _Col('Propinas', 12, _T.dinero, true),
    const _Col('Neto', 14, _T.dinero, true),
    if (costos) ...const [_Col('Costo', 13, _T.dinero, true), _Col('Ganancia estimada', 15, _T.dinero, true)],
    const _Col('Cortesías (u)', 12, _T.entero, true),
    const _Col('Cortesías (valor)', 14, _T.dinero, true),
  ]);
  final h = _hoja('Ventas por día', 'Ventas día por día', d, cols);
  _tabla(h, cols, [
    for (final (suc, fecha, r) in d.ventasDia)
      _fila(d, suc, [
        fecha,
        r.totalOrdenes,
        r.totalFacturas,
        r.totalMesasCobradas,
        if (personas) r.totalPersonas,
        r.totalVentas,
        r.totalDescuentos,
        r.totalIva,
        r.totalPropinas,
        r.totalNeto,
        if (costos) ...[r.totalCosto, r.gananciaEstimada],
        r.unidadesCortesia,
        r.valorCortesias,
      ]),
  ]);
  return h;
}

String _estadoComprobante(String e) => switch (e) {
      'PAGADA' => 'Pagada',
      'PENDIENTE' => 'Pendiente',
      'ANULADA' => etiquetaAnulada,
      _ => _capitalizar(e),
    };

Hoja _comprobantes(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Fecha y hora', 17, _T.fechaHora),
    _Col('Tipo', 14),
    _Col('Número', 20),
    _Col('Orden', 8, _T.entero),
    _Col('Lugar', 16),
    _Col('Cliente', 26),
    _Col('Cédula / RUC', 15),
    _Col('Subtotal', 12, _T.dinero, true),
    _Col('Descuento', 12, _T.dinero, true),
    _Col('Base 0%', 12, _T.dinero, true),
    _Col('Base gravada', 13, _T.dinero, true),
    _Col('IVA', 11, _T.dinero, true),
    _Col('Propina', 11, _T.dinero, true),
    _Col('Total', 12, _T.dinero, true),
    _Col('Formas de pago', 34),
    _Col('Cajero', 16),
    _Col('Estado', 11),
    _Col('Estado SRI', 13),
    _Col('Autorización SRI', 30),
    _Col('Cortesía', 9),
  ]);
  final h = _hoja('Comprobantes', 'Notas de venta y facturas', d, cols);
  _tabla(h, cols, [
    for (final (suc, c) in d.comprobantes)
      _fila(d, suc, () {
        // Facturas viejas no traen el desglose: se arma con el IVA.
        final double base0, gravada;
        if (c.subtotalGravado != null || c.subtotalSinIva != null) {
          gravada = c.subtotalGravado ?? 0;
          base0 = c.subtotalSinIva ?? 0;
        } else {
          final neto = c.subtotal - c.descuento;
          gravada = c.iva > 0 ? neto : 0;
          base0 = c.iva > 0 ? 0 : neto;
        }
        return [
          c.fecha,
          c.esFactura ? 'Factura' : 'Nota de venta',
          c.numeroFactura,
          c.numeroOrden == 0 ? null : c.numeroOrden,
          c.lugar ?? '',
          c.nombreCliente ?? (c.esFactura ? '' : 'Consumidor final'),
          c.cedulaRucCliente ?? '',
          c.subtotal,
          c.descuento,
          base0,
          gravada,
          c.iva,
          c.propina,
          c.total,
          c.pagos
              .map((p) => '${_capitalizar(p.nombreMetodoPago)}${p.esAdelanto ? ' (adelanto)' : ''} '
                  '\$${_c(p.monto).toStringAsFixed(2)}')
              .join(' + '),
          c.cajero ?? '',
          _estadoComprobante(c.estado),
          c.sriEstado == null ? '' : _capitalizar(c.sriEstado!),
          c.sriAutorizacion ?? '',
          c.cortesia ? _si : '',
        ];
      }()),
  ], excluir: [(_ix(d, 16), etiquetaAnulada)]);
  return h;
}

Hoja _detalle(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Fecha y hora', 17, _T.fechaHora),
    _Col('Comprobante', 20),
    _Col('Orden', 8, _T.entero),
    _Col('Lugar', 16),
    _Col('Plato', 30),
    _Col('Cantidad', 10, _T.entero, true),
    _Col('Subtotal', 12, _T.dinero, true),
    _Col('Cortesía', 9),
    _Col('Estado del comprobante', 14),
  ]);
  final h = _hoja('Detalle de lo vendido', 'Cada plato de cada comprobante', d, cols);
  _tabla(h, cols, [
    for (final (suc, c) in d.comprobantes)
      for (final i in c.items)
        _fila(d, suc, [
          c.fecha,
          c.numeroFactura,
          c.numeroOrden == 0 ? null : c.numeroOrden,
          c.lugar ?? '',
          i.nombre,
          i.cantidad,
          i.subtotal,
          i.cortesia ? _si : '',
          _estadoComprobante(c.estado),
        ]),
  ], excluir: [(_ix(d, 8), etiquetaAnulada), (_ix(d, 7), _si)]);
  return h;
}

Hoja _cierres(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Fecha', 12, _T.fecha),
    _Col('Caja', 16),
    _Col('Abrió', 16),
    _Col('Cerró', 16),
    _Col('Apertura', 17, _T.fechaHora),
    _Col('Cierre', 17, _T.fechaHora),
    _Col('Monto inicial', 13, _T.dinero, true),
    _Col('Ventas', 13, _T.dinero, true),
    _Col('Ventas en efectivo', 15, _T.dinero, true),
    _Col('Ingresos', 12, _T.dinero, true),
    _Col('Egresos', 12, _T.dinero, true),
    _Col('Esperado', 13, _T.dinero, true),
    _Col('Contado', 13, _T.dinero, true),
    _Col('Diferencia', 12, _T.dinero, true),
    _Col('Comprobantes', 12, _T.entero, true),
    _Col('Propinas', 12, _T.dinero, true),
    _Col('Observaciones', 30),
  ]);
  final h = _hoja('Cierres de caja', 'Aperturas y cierres de caja', d, cols,
      detalle: 'diferencia negativa = faltante');
  _tabla(h, cols, [
    for (final (suc, c) in d.cierres)
      _fila(d, suc, [
        c.fechaApertura,
        c.nombreCaja,
        c.usuarioApertura,
        c.usuarioCierre ?? '',
        c.fechaApertura,
        c.fechaCierre,
        c.montoInicial,
        c.totalVentas,
        c.totalVentasEfectivo,
        c.totalIngresos,
        c.totalEgresos,
        c.montoEsperado,
        c.montoContado,
        c.diferencia,
        c.totalFacturas,
        c.totalPropinas,
        c.observaciones ?? '',
      ]),
  ]);
  return h;
}

Hoja _movimientos(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Fecha y hora', 17, _T.fechaHora),
    _Col('Caja', 16),
    _Col('Tipo', 10),
    _Col('Concepto', 34),
    _Col('Monto', 12, _T.dinero),
    _Col('Usuario', 16),
  ]);
  final filas = <(DateTime, List<Object?>)>[
    for (final (suc, c) in d.cierres)
      for (final m in [...c.ingresos, ...c.egresos])
        (m.fecha, _fila(d, suc, [m.fecha, c.nombreCaja, m.esIngreso ? 'Ingreso' : 'Egreso', m.concepto, m.monto, m.usuario])),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final h = _hoja('Movimientos de caja', 'Ingresos y egresos de caja', d, cols);
  _tabla(h, cols, [for (final f in filas) f.$2]);
  return h;
}

// ── Pérdidas ────────────────────────────────────────────────────────────────

Hoja _cortesias(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Fecha y hora', 17, _T.fechaHora),
    _Col('Orden', 8, _T.entero),
    _Col('Lugar', 16),
    _Col('Plato', 30),
    _Col('Cantidad', 10, _T.entero, true),
    _Col('Valor de carta', 14, _T.dinero, true),
    _Col('Motivo', 30),
    _Col('Autorizó', 16),
    _Col('Mesa ya cobrada', 12),
  ]);
  final h = _hoja('Cortesías', 'Platos regalados', d, cols);
  _tabla(h, cols, [
    for (final (suc, c) in d.cortesias)
      _fila(d, suc, [c.fecha, c.numeroOrden, c.lugar, c.plato, c.cantidad, c.valor, c.motivo ?? '', c.autorizadaPor ?? '', c.cobrada]),
  ]);
  return h;
}

Hoja _anuladas(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Fecha y hora', 17, _T.fechaHora),
    _Col('Orden', 8, _T.entero),
    _Col('Lugar', 16),
    _Col('Tomada por', 16),
    _Col('Anuló', 16),
    _Col('Motivo', 34),
    _Col('Platos', 9, _T.entero, true),
    _Col('Total', 12, _T.dinero, true),
  ]);
  final h = _hoja('Órdenes anuladas', 'Órdenes anuladas', d, cols);
  _tabla(h, cols, [
    for (final (suc, o) in d.anuladas)
      _fila(d, suc, () {
        // Igual que la pantalla: sin los ítems que ya estaban cancelados.
        final items = o.detalles.where((x) => x.estado != 'CANCELADO').toList();
        return [
          o.fechaCierre ?? o.fechaCreacion,
          o.numeroOrden,
          o.lugar,
          o.nombreUsuario,
          o.canceladaPor ?? '',
          o.motivoCancelacion ?? '',
          items.fold<int>(0, (s, x) => s + x.cantidad),
          items.fold<double>(0, (s, x) => s + x.subtotal),
        ];
      }()),
  ]);
  return h;
}

// ── Inventario ──────────────────────────────────────────────────────────────

Hoja _insumos(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Insumo', 28),
    _Col('Categoría', 16),
    _Col('Stock', 11, _T.cantidad),
    _Col('Unidad', 8),
    _Col('Stock en su presentación', 22),
    _Col('Mínimo', 10, _T.cantidad),
    _Col('Costo promedio por unidad', 15, _T.dinero),
    _Col('Valor del stock', 14, _T.dinero, true),
    _Col('Estado', 12),
    _Col('Activo', 8),
  ]);
  final h = _hoja('Stock de insumos', 'Stock de insumos', d, cols, detalle: 'stock al momento de descargar');
  final lista = [...d.insumos]..sort((a, b) => a.$2.nombre.toLowerCase().compareTo(b.$2.nombre.toLowerCase()));
  _tabla(h, cols, [
    for (final (suc, i) in lista)
      _fila(d, suc, () {
        final (factor, unidad) = _unidad(i.unidad);
        return [
          i.nombre,
          i.categoria ?? '',
          i.stock / factor,
          unidad,
          Unidades.formato(i.stock, i.unidad, p: i.presentacion),
          i.stockMinimo == null ? null : i.stockMinimo! / factor,
          i.costoPromedio == null ? null : i.costoPromedio! * factor,
          i.valorStock,
          i.negativo ? 'Negativo' : i.bajoMinimo ? 'Por reponer' : 'Bien',
          i.activo,
        ];
      }()),
  ]);
  return h;
}

Hoja _platosStock(DatosExportacion d) {
  String modo(String m) => switch (m) {
        'UNIDADES' => 'Por unidades',
        'RECETA' => 'Por receta',
        _ => 'Sin control',
      };
  final cols = _conSucursal(d, const [
    _Col('Plato', 30),
    _Col('Categoría', 18),
    _Col('Subcategoría', 18),
    _Col('Control', 14),
    _Col('Stock', 10, _T.cantidad),
    _Col('Mínimo', 10, _T.cantidad),
    _Col('Estado', 13),
    _Col('Disponible', 10),
  ]);
  final h = _hoja('Stock de platos', 'Stock de platos', d, cols,
      detalle: 'los platos por receta descuentan insumos y no tienen stock propio');
  final lista = [...d.platosStock]
    ..sort((a, b) => a.$2.nombrePlato.toLowerCase().compareTo(b.$2.nombrePlato.toLowerCase()));
  _tabla(h, cols, [
    for (final (suc, p) in lista)
      _fila(d, suc, [
        p.nombrePlato,
        p.categoria,
        p.subcategoria,
        modo(p.modoInventario),
        p.modoInventario == 'UNIDADES' ? p.stock : null,
        p.modoInventario == 'UNIDADES' ? p.stockMinimo : null,
        p.modoInventario != 'UNIDADES' ? '' : p.agotado ? 'Agotado' : p.bajoMinimo ? 'Por agotarse' : 'Bien',
        p.disponible,
      ]),
  ]);
  return h;
}

Hoja _compras(DatosExportacion d) {
  final cols = _conSucursal(d, const [
    _Col('Fecha', 12, _T.fecha),
    _Col('Proveedor', 22),
    _Col('Documento', 16),
    _Col('Insumo', 26),
    _Col('Cantidad', 10, _T.cantidad),
    _Col('Unidad', 8),
    _Col('Costo unitario', 13, _T.dinero),
    _Col('Subtotal', 13, _T.dinero, true),
    _Col('Registró', 16),
    _Col('Nota', 28),
  ]);
  final h = _hoja('Compras', 'Compras de insumos', d, cols);
  _tabla(h, cols, [
    for (final (suc, c) in d.compras)
      if (c.items.isEmpty)
        _fila(d, suc, [c.fecha, c.proveedor ?? '', c.numeroDocumento ?? '', '', null, '', null, c.total, c.usuario ?? '', c.nota ?? ''])
      else
        for (final i in c.items)
          _fila(d, suc, () {
            final (factor, unidad) = _unidad(i.unidad);
            return [
              c.fecha,
              c.proveedor ?? '',
              c.numeroDocumento ?? '',
              i.nombre,
              i.cantidad / factor,
              unidad,
              i.costoUnitario * factor,
              i.subtotal,
              c.usuario ?? '',
              c.nota ?? '',
            ];
          }()),
  ]);
  return h;
}

Hoja _proveedores(DatosExportacion d) {
  const cols = [_Col('Proveedor', 28), _Col('RUC', 16), _Col('Teléfono', 14), _Col('Correo', 28), _Col('Activo', 8)];
  final h = _hoja('Proveedores', 'Proveedores', d, cols);
  final lista = [...d.proveedores]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  _tabla(h, cols, [for (final p in lista) [p.nombre, p.ruc ?? '', p.telefono ?? '', p.email ?? '', p.activo]]);
  return h;
}
