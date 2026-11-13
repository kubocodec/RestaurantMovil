// Escritor mínimo de .xlsx (Office Open XML) sobre package:archive.
//
// Dart puro: sin dart:io ni Flutter, así compila igual para el navegador y
// se puede probar con `flutter test`. Validado el 2026-11-12 con archive
// 4.6.0: zip íntegro, XML bien formado, vista previa de macOS y dart2js.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// El orden de este enum ES el índice en `<cellXfs>` de styles.xml: si se
/// agrega un estilo acá, hay que agregar su `<xf>` en la misma posición.
enum Estilo {
  normal,
  encabezado,
  entero,
  dinero,
  porcentaje,
  fecha,
  fechaHora,
  cantidad,
  totalEtiqueta,
  totalDinero,
  totalEntero,
  totalCantidad,
  titulo,
  nota,
  negrita,
}

class Celda {
  /// String, num, DateTime o null (celda vacía con estilo).
  final Object? valor;
  final Estilo estilo;

  /// Fórmula sin el "=". Si viene, [valor] es el resultado ya calculado:
  /// Excel lo muestra en Vista protegida, donde no recalcula.
  final String? formula;

  const Celda(this.valor, [this.estilo = Estilo.normal, this.formula]);
}

class Hoja {
  final String nombre;

  /// Ancho de cada columna, en caracteres.
  final List<double> anchos;
  final List<List<Celda?>> filas = [];

  /// Índice (desde 0) de la fila de encabezados de la tabla. Hasta ahí se
  /// congela el desplazamiento y desde ahí arranca el filtro.
  int? filaEncabezado;

  /// Última fila de datos de la tabla (desde 0, inclusive): hasta ahí llega
  /// el filtro, para que la fila de totales quede fuera.
  int? ultimaFilaDatos;

  Hoja(this.nombre, this.anchos);

  void fila(List<Celda?> celdas) => filas.add(celdas);
}

String letraColumna(int indice) {
  var n = indice + 1;
  final b = StringBuffer();
  final letras = <int>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    letras.add(65 + r);
    n = (n - 1) ~/ 26;
  }
  for (final c in letras.reversed) {
    b.writeCharCode(c);
  }
  return b.toString();
}

/// XML 1.0 no admite la mayoría de los caracteres de control: un nombre de
/// plato pegado desde otro lado con un 0x0B dentro deja el archivo ilegible.
String _xml(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x26) {
      b.write('&amp;');
    } else if (r == 0x3C) {
      b.write('&lt;');
    } else if (r == 0x3E) {
      b.write('&gt;');
    } else if (r == 0x22) {
      b.write('&quot;');
    } else if (r == 0x9 || r == 0xA || r == 0xD || (r >= 0x20 && r != 0xFFFE && r != 0xFFFF)) {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// Nombre de hoja válido: máximo 31 caracteres, sin : \ / ? * [ ] y sin
/// repetirse (Excel compara sin distinguir mayúsculas).
List<String> _nombresDeHoja(List<Hoja> hojas) {
  final usados = <String>{};
  final salida = <String>[];
  for (final h in hojas) {
    var n = h.nombre
        .replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    n = n.replaceAll(RegExp(r"^'+|'+$"), '');
    if (n.isEmpty) n = 'Hoja';
    if (n.length > 31) n = n.substring(0, 31).trim();
    var candidato = n;
    var i = 2;
    while (usados.contains(candidato.toLowerCase())) {
      final sufijo = ' ($i)';
      final base = n.length + sufijo.length > 31 ? n.substring(0, 31 - sufijo.length) : n;
      candidato = '$base$sufijo';
      i++;
    }
    usados.add(candidato.toLowerCase());
    salida.add(candidato);
  }
  return salida;
}

/// Número de serie de Excel: días desde el 30-12-1899. Se toman los campos
/// de la hora LOCAL como si fueran UTC para que ni la zona ni un cambio de
/// hora corran la fecha.
double serieExcel(DateTime d) {
  final l = d.toLocal();
  final comoUtc = DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second);
  return comoUtc.difference(DateTime.utc(1899, 12, 30)).inMilliseconds / 86400000.0;
}

String _numero(num n) {
  if (n is int) return n.toString();
  final d = n.toDouble();
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

const _cabecera = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _nsMain = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _nsRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _nsPaquete = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// styles.xml. El orden de los bloques lo fija el esquema: numFmts, fonts,
/// fills, borders, cellStyleXfs, cellXfs, cellStyles. Los dos primeros
/// `<fill>` (none y gray125) son obligatorios.
const _estilos = '$_cabecera'
    '<styleSheet xmlns="$_nsMain">'
    '<numFmts count="5">'
    '<numFmt numFmtId="164" formatCode="&quot;\$&quot;#,##0.00"/>'
    '<numFmt numFmtId="165" formatCode="dd/mm/yyyy"/>'
    '<numFmt numFmtId="166" formatCode="dd/mm/yyyy hh:mm"/>'
    '<numFmt numFmtId="167" formatCode="#,##0.###"/>'
    '<numFmt numFmtId="168" formatCode="0.0%"/>'
    '</numFmts>'
    '<fonts count="5">'
    '<font><sz val="11"/><color rgb="FF3E2723"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><color rgb="FF3E2723"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="15"/><color rgb="FF5D4037"/><name val="Calibri"/><family val="2"/></font>'
    '<font><i/><sz val="10"/><color rgb="FF6D4C41"/><name val="Calibri"/><family val="2"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FF5D4037"/><bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF5EFE6"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left/><right/><top style="thin"><color rgb="FF5D4037"/></top><bottom/><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="15">'
    // 0 normal
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1"><alignment vertical="top" wrapText="1"/></xf>'
    // 1 encabezado
    '<xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
    // 2 entero
    '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 3 dinero
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 4 porcentaje
    '<xf numFmtId="168" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 5 fecha
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="left"/></xf>'
    // 6 fechaHora
    '<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="left"/></xf>'
    // 7 cantidad
    '<xf numFmtId="167" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 8 totalEtiqueta
    '<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 9 totalDinero
    '<xf numFmtId="164" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 10 totalEntero
    '<xf numFmtId="3" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 11 totalCantidad
    '<xf numFmtId="167" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 12 titulo
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 13 nota
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 14 negrita
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"><alignment vertical="top" wrapText="1"/></xf>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

Uint8List construirXlsx(List<Hoja> hojas) {
  assert(hojas.isNotEmpty, 'Un libro de Excel necesita al menos una hoja');
  final nombres = _nombresDeHoja(hojas);

  // Textos compartidos: cada texto distinto se guarda una vez.
  final indiceTexto = <String, int>{};
  final textos = <String>[];
  var referencias = 0;
  int texto(String s) {
    referencias++;
    return indiceTexto.putIfAbsent(s, () {
      textos.add(s);
      return textos.length - 1;
    });
  }

  final xmlHojas = <String>[];
  final filtros = <int, String>{}; // índice de hoja -> rango absoluto del filtro

  for (var h = 0; h < hojas.length; h++) {
    final hoja = hojas[h];
    final b = StringBuffer(_cabecera);
    b.write('<worksheet xmlns="$_nsMain" xmlns:r="$_nsRel">');

    // El orden de los hijos de <worksheet> lo fija el esquema, y Excel
    // rechaza el archivo si se altera: sheetViews, sheetFormatPr, cols,
    // sheetData, autoFilter, pageMargins.
    b.write('<sheetViews><sheetView workbookViewId="0"${h == 0 ? ' tabSelected="1"' : ''}>');
    final enc = hoja.filaEncabezado;
    if (enc != null) {
      final primera = 'A${enc + 2}';
      b.write('<pane ySplit="${enc + 1}" topLeftCell="$primera" activePane="bottomLeft" state="frozen"/>');
      b.write('<selection pane="bottomLeft" activeCell="$primera" sqref="$primera"/>');
    }
    b.write('</sheetView></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');

    if (hoja.anchos.isNotEmpty) {
      b.write('<cols>');
      for (var c = 0; c < hoja.anchos.length; c++) {
        b.write('<col min="${c + 1}" max="${c + 1}" width="${hoja.anchos[c]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }

    b.write('<sheetData>');
    var columnas = hoja.anchos.length;
    for (var f = 0; f < hoja.filas.length; f++) {
      final fila = hoja.filas[f];
      if (fila.length > columnas) columnas = fila.length;
      b.write('<row r="${f + 1}">');
      for (var c = 0; c < fila.length; c++) {
        final celda = fila[c];
        if (celda == null) continue;
        final ref = '${letraColumna(c)}${f + 1}';
        final s = celda.estilo.index;
        final v = celda.valor;
        final formula = celda.formula;
        if (formula != null) {
          b.write('<c r="$ref" s="$s"><f>${_xml(formula)}</f>');
          if (v is num && v.isFinite) b.write('<v>${_numero(v)}</v>');
          b.write('</c>');
        } else if (v == null) {
          b.write('<c r="$ref" s="$s"/>');
        } else if (v is num) {
          if (v.isFinite) {
            b.write('<c r="$ref" s="$s"><v>${_numero(v)}</v></c>');
          } else {
            b.write('<c r="$ref" s="$s"/>');
          }
        } else if (v is DateTime) {
          b.write('<c r="$ref" s="$s"><v>${serieExcel(v)}</v></c>');
        } else {
          b.write('<c r="$ref" s="$s" t="s"><v>${texto(v.toString())}</v></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');

    final ult = hoja.ultimaFilaDatos;
    if (enc != null && ult != null && ult > enc && columnas > 0) {
      final fin = letraColumna(columnas - 1);
      b.write('<autoFilter ref="A${enc + 1}:$fin${ult + 1}"/>');
      filtros[h] = "'${nombres[h].replaceAll("'", "''")}'!\$A\$${enc + 1}:\$$fin\$${ult + 1}";
    }
    b.write('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>');
    b.write('</worksheet>');
    xmlHojas.add(b.toString());
  }

  // xl/sharedStrings.xml
  final ss = StringBuffer(_cabecera)
    ..write('<sst xmlns="$_nsMain" count="$referencias" uniqueCount="${textos.length}">');
  for (final t in textos) {
    ss.write('<si><t xml:space="preserve">${_xml(t)}</t></si>');
  }
  ss.write('</sst>');

  // xl/workbook.xml
  final wb = StringBuffer(_cabecera)
    ..write('<workbook xmlns="$_nsMain" xmlns:r="$_nsRel">')
    ..write('<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="17000"/></bookViews>')
    ..write('<sheets>');
  for (var h = 0; h < hojas.length; h++) {
    wb.write('<sheet name="${_xml(nombres[h])}" sheetId="${h + 1}" r:id="rId${h + 1}"/>');
  }
  wb.write('</sheets>');
  if (filtros.isNotEmpty) {
    // Excel guarda el rango de cada filtro también como nombre oculto.
    wb.write('<definedNames>');
    filtros.forEach((h, rango) {
      wb.write('<definedName name="_xlnm._FilterDatabase" localSheetId="$h" hidden="1">${_xml(rango)}</definedName>');
    });
    wb.write('</definedNames>');
  }
  wb.write('</workbook>');

  // xl/_rels/workbook.xml.rels
  final rels = StringBuffer(_cabecera)..write('<Relationships xmlns="$_nsPaquete">');
  for (var h = 0; h < hojas.length; h++) {
    rels.write('<Relationship Id="rId${h + 1}" Type="$_nsRel/worksheet" Target="worksheets/sheet${h + 1}.xml"/>');
  }
  rels
    ..write('<Relationship Id="rId${hojas.length + 1}" Type="$_nsRel/styles" Target="styles.xml"/>')
    ..write('<Relationship Id="rId${hojas.length + 2}" Type="$_nsRel/sharedStrings" Target="sharedStrings.xml"/>')
    ..write('</Relationships>');

  // [Content_Types].xml
  const tipo = 'application/vnd.openxmlformats-officedocument.spreadsheetml';
  final ct = StringBuffer(_cabecera)
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="$tipo.sheet.main+xml"/>');
  for (var h = 0; h < hojas.length; h++) {
    ct.write('<Override PartName="/xl/worksheets/sheet${h + 1}.xml" ContentType="$tipo.worksheet+xml"/>');
  }
  ct
    ..write('<Override PartName="/xl/styles.xml" ContentType="$tipo.styles+xml"/>')
    ..write('<Override PartName="/xl/sharedStrings.xml" ContentType="$tipo.sharedStrings+xml"/>')
    ..write('</Types>');

  const relsRaiz = '$_cabecera'
      '<Relationships xmlns="$_nsPaquete">'
      '<Relationship Id="rId1" Type="$_nsRel/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  final zip = Archive();
  void parte(String ruta, String contenido) =>
      zip.add(ArchiveFile.bytes(ruta, utf8.encode(contenido)));

  // [Content_Types].xml va primero: algunos lectores lo esperan ahí.
  parte('[Content_Types].xml', ct.toString());
  parte('_rels/.rels', relsRaiz);
  parte('xl/workbook.xml', wb.toString());
  parte('xl/_rels/workbook.xml.rels', rels.toString());
  parte('xl/styles.xml', _estilos);
  parte('xl/sharedStrings.xml', ss.toString());
  for (var h = 0; h < xmlHojas.length; h++) {
    parte('xl/worksheets/sheet${h + 1}.xml', xmlHojas[h]);
  }
  return ZipEncoder().encodeBytes(zip);
}
