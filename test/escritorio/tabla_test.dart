import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_app/core/constants/app_colors.dart';
import 'package:restaurant_app/core/escritorio/tabla.dart';
import 'package:restaurant_app/core/theme/app_theme.dart';

const _columnas = [
  ColumnaTabla('Hora', flex: 1),
  ColumnaTabla('Comprobante', flex: 4),
  ColumnaTabla('Lugar', flex: 2),
  ColumnaTabla('Cliente', flex: 3),
  ColumnaTabla('Cajero', flex: 2),
  ColumnaTabla('Pago', flex: 3),
  ColumnaTabla('SRI', flex: 2),
  ColumnaTabla('Estado', flex: 2),
  ColumnaTabla('Total', flex: 2, derecha: true),
];

Future<void> _pintar(WidgetTester t, List<FilaTabla> filas, {double ancho = 752, double texto = 1}) async {
  t.view.physicalSize = Size(ancho, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(texto)), child: child!),
    home: Scaffold(
      body: TablaEscritorio(
        columnas: _columnas,
        filas: filas,
        vacio: const Text('Sin comprobantes'),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

FilaTabla _fila(int i, VoidCallback onTap) => FilaTabla([
      TablaEscritorio.texto('18:4$i'),
      TablaEscritorio.texto('Nota de venta 001-020-00000008$i con un número largo', negrita: true),
      TablaEscritorio.texto('Terraza 12 · #$i'),
      TablaEscritorio.texto('Consumidor final con un nombre muy largo'),
      TablaEscritorio.texto('Prueba Restaurante'),
      TablaEscritorio.texto('Efectivo + Tarjeta + Transferencia'),
      TablaEscritorio.pildora('Autorizada', AppColors.success),
      TablaEscritorio.pildora('Pagada', AppColors.success),
      TablaEscritorio.numero('\$1,234.5$i', negrita: true),
    ], onTap: onTap);

void main() {
  testWidgets('al tocar una fila se llama su acción', (t) async {
    var tocada = -1;
    await _pintar(t, [for (var i = 0; i < 3; i++) _fila(i, () => tocada = i)]);
    await t.tap(find.text('Terraza 12 · #2'));
    expect(tocada, 2);
  });

  testWidgets('sin filas muestra el mensaje vacío y el encabezado', (t) async {
    await _pintar(t, const []);
    expect(find.text('Sin comprobantes'), findsOneWidget);
    expect(find.text('COMPROBANTE'), findsOneWidget);
  });

  for (final (ancho, texto) in [(752.0, 1.0), (752.0, 1.4), (1440.0, 1.4)]) {
    testWidgets('9 columnas a $ancho px con texto ×$texto no se desbordan', (t) async {
      await _pintar(t, [for (var i = 0; i < 40; i++) _fila(i, () {})], ancho: ancho, texto: texto);
      expect(t.takeException(), isNull);
    });
  }
}
