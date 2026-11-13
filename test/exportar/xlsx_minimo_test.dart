import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_app/core/exportar/xlsx_minimo.dart';

Map<String, String> _partes(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  return {for (final f in zip.files) if (f.isFile) f.name: utf8.decode(f.content as List<int>)};
}

void main() {
  test('el zip trae todas las partes de un libro de Excel', () {
    final partes = _partes(construirXlsx([Hoja('Uno', [10])..fila([const Celda('a')]), Hoja('Dos', [])]));
    expect(partes.keys, containsAll([
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'xl/styles.xml',
      'xl/sharedStrings.xml',
      'xl/worksheets/sheet1.xml',
      'xl/worksheets/sheet2.xml',
    ]));
  });

  test('los nombres de hoja quedan válidos: sin caracteres prohibidos, 31 como máximo y sin repetirse', () {
    final partes = _partes(construirXlsx([
      Hoja('Ventas: noviembre [2026] / centro', []),
      Hoja('Resumen', []),
      Hoja('resumen', []),
      Hoja('Un nombre de hoja larguísimo que no entra en Excel', []),
    ]));
    final nombres = RegExp(r'<sheet name="([^"]*)"')
        .allMatches(partes['xl/workbook.xml']!)
        .map((m) => m.group(1)!)
        .toList();
    expect(nombres, hasLength(4));
    for (final n in nombres) {
      expect(n.length, lessThanOrEqualTo(31), reason: n);
      expect(n, isNot(matches(RegExp(r'[:\\/?*\[\]]'))), reason: n);
    }
    expect(nombres.map((n) => n.toLowerCase()).toSet(), hasLength(4));
  });

  test('un texto con & < > y caracteres de control no rompe el XML', () {
    final partes = _partes(construirXlsx([
      Hoja('H', [])..fila([const Celda('Pizza "Ñandú" & jamón <b>\u000b🍊')]),
    ]));
    final ss = partes['xl/sharedStrings.xml']!;
    expect(ss, contains('Pizza &quot;Ñandú&quot; &amp; jamón &lt;b&gt;🍊'));
    expect(ss.contains('\u000b'), isFalse);
  });

  test('las fechas se guardan como número de serie de Excel en hora local', () {
    expect(serieExcel(DateTime(2026, 11, 12)), 46338);
    expect(serieExcel(DateTime(2026, 11, 12, 18)), closeTo(46338.75, 1e-9));
  });

  test('una fórmula guarda también su valor, para la Vista protegida', () {
    final partes = _partes(construirXlsx([
      Hoja('H', [])..fila([const Celda(5, Estilo.dinero), const Celda(5, Estilo.totalDinero, 'SUBTOTAL(109,A1:A1)')]),
    ]));
    expect(partes['xl/worksheets/sheet1.xml'], contains('<f>SUBTOTAL(109,A1:A1)</f><v>5</v>'));
  });

  test('sin filas de datos no se escribe filtro', () {
    final h = Hoja('H', [10])
      ..fila([const Celda('Encabezado', Estilo.encabezado)])
      ..filaEncabezado = 0;
    expect(_partes(construirXlsx([h]))['xl/worksheets/sheet1.xml'], isNot(contains('autoFilter')));
  });
}
