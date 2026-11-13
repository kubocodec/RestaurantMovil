import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_app/core/exportar/xlsx_minimo.dart';
import 'package:restaurant_app/features/reportes/exportar/datos_exportacion.dart';
import 'package:restaurant_app/features/reportes/exportar/libro_reporte.dart';
import 'package:restaurant_app/features/reportes/exportar/recolector.dart';

import 'datos_de_prueba.dart';

Hoja _hoja(List<Hoja> hojas, String nombre) => hojas.firstWhere((h) => h.nombre == nombre);

/// La fila de totales es la última de la tabla; devuelve sus celdas.
List<Celda?> _totales(Hoja h) => h.filas.lastWhere((f) => f.isNotEmpty && f.first?.estilo == Estilo.totalEtiqueta);

int _col(Hoja h, String titulo) =>
    h.filas[h.filaEncabezado!].indexWhere((c) => c?.valor == titulo);

void main() {
  test('cada total es la suma de su columna', () {
    final hojas = armarLibro(datosCompletos());
    final platos = _hoja(hojas, 'Platos vendidos');
    final unidades = _col(platos, 'Unidades');
    final ventas = _col(platos, 'Ventas con IVA');
    final t = _totales(platos);
    expect(t[unidades]!.valor, 30 + 12 + 25);
    expect(t[ventas]!.valor, 286.5);
    expect(t[ventas]!.formula, startsWith('SUBTOTAL(109,'));
  });

  test('los comprobantes anulados se listan pero no suman', () {
    final h = _hoja(armarLibro(datosCompletos()), 'Comprobantes');
    final total = _col(h, 'Total');
    expect(h.filas.where((f) => f.any((c) => c?.valor == etiquetaAnulada)), hasLength(1));
    final t = _totales(h)[total]!;
    expect(t.valor, 34.5); // 23 + 11.5, sin los 100 del anulado
    expect(t.formula, contains('"<>$etiquetaAnulada"'));
  });

  test('en el detalle no suman ni los anulados ni las cortesías', () {
    final h = _hoja(armarLibro(datosCompletos()), 'Detalle de lo vendido');
    final t = _totales(h)[_col(h, 'Subtotal')]!;
    expect(t.valor, 7.0); // solo los encebollados: el seco fue cortesía y el churrasco, anulado
  });

  test('varias formas de pago van en una sola fila', () {
    final h = _hoja(armarLibro(datosCompletos()), 'Comprobantes');
    final pagos = _col(h, 'Formas de pago');
    expect(h.filas.any((f) => f.length > pagos && f[pagos]?.valor == r'Efectivo $13.00 + Tarjeta $10.00'), isTrue);
  });

  test('sin inventario no hay hojas de inventario', () {
    final d = datosCompletos()..conInventario.clear();
    final nombres = armarLibro(d).map((h) => h.nombre).toList();
    for (final n in ['Stock de insumos', 'Stock de platos', 'Compras', 'Proveedores']) {
      expect(nombres, isNot(contains(n)));
    }
  });

  test('sin costos no hay columnas de costo ni de ganancia', () {
    final d = datosCompletos()..resumen = resumenDePrueba(conCostos: false);
    final platos = _hoja(armarLibro(d), 'Platos vendidos');
    final encabezados = platos.filas[platos.filaEncabezado!].map((c) => c?.valor).toList();
    expect(encabezados, isNot(contains('Ganancia')));
    expect(encabezados, isNot(contains('Costo total')));
  });

  test('con varias sucursales las hojas por sucursal llevan la columna Sucursal', () {
    final h = _hoja(armarLibro(datosCompletos(variasSucursales: true)), 'Comprobantes');
    expect(h.filas[h.filaEncabezado!].first?.valor, 'Sucursal');
    // Y el total sigue saliendo bien con la columna corrida.
    expect(_totales(h)[_col(h, 'Total')]!.valor, 34.5);
  });

  test('el detalle por día se limita a 31 días y una sucursal por mes', () {
    expect(RecolectorExcel.detallePorDiaPermitido(31, 1), isTrue);
    expect(RecolectorExcel.detallePorDiaPermitido(40, 1), isFalse);
    expect(RecolectorExcel.detallePorDiaPermitido(31, 2), isTrue);
    expect(RecolectorExcel.detallePorDiaPermitido(31, 3), isFalse);
    expect(RecolectorExcel.diasEntre(DateTime(2026, 11, 1, 22), DateTime(2026, 11, 3, 1)), [
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 2),
      DateTime(2026, 11, 3),
    ]);
  });

  test('las notas aparecen en la hoja Resumen', () {
    final d = datosCompletos()..notas.add('No se incluyó el detalle día por día.');
    final resumen = armarLibro(d).first;
    expect(resumen.nombre, 'Resumen');
    expect(resumen.filas.any((f) => f.any((c) => c?.valor == 'No se incluyó el detalle día por día.')), isTrue);
  });

  test('el nombre del archivo no lleva caracteres que el sistema rechace', () {
    final d = DatosExportacion(
      alcance: 'Bar "La Esquina": Centro/Norte',
      desde: DateTime(2026, 11, 1),
      hasta: DateTime(2026, 11, 12),
      secciones: const {},
      variasSucursales: false,
    );
    expect(nombreArchivo(d), 'Wasi - Bar La Esquina Centro Norte - 2026-11-01 a 2026-11-12.xlsx');
  });

  test('el libro completo se puede escribir (lo valida tool/validar_xlsx.sh)', () {
    final bytes = construirXlsx(armarLibro(datosCompletos(variasSucursales: true)));
    File('build/ejemplo_exportacion.xlsx')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(1000));
  });
}
