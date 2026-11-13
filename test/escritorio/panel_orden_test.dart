import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_app/core/models/orden_model.dart';
import 'package:restaurant_app/core/theme/app_theme.dart';
import 'package:restaurant_app/features/mesas/presentation/panel_orden_mesa.dart';

OrdenModel _orden({bool todoCobrado = false}) => OrdenModel.fromJson({
      'ordenId': 'o1', 'numeroOrden': 12, 'mesaId': 'm4', 'numeroMesa': 'Mesa 4',
      'sucursalId': 's1', 'estado': 'ABIERTA', 'tipoOrden': 'EN_MESA', 'tipoOrigen': 'MESERO',
      'fechaCreacion': '2026-11-13T18:42:00Z', 'nombreUsuario': 'Carlos', 'numComensales': 4,
      'detalles': [
        {'ordenDetalleId': 'd1', 'platoId': 'p1', 'nombrePlato': 'Encebollado', 'cantidad': 2,
          'precioUnitario': 3.5, 'subtotal': 7.0, 'estado': 'LISTO', 'tipoServicio': 'MESA',
          'facturado': todoCobrado, 'cantidadFacturada': todoCobrado ? 2 : 0},
        {'ordenDetalleId': 'd2', 'platoId': 'p2', 'nombrePlato': 'Churrasco con un nombre bastante largo para la fila',
          'cantidad': 1, 'precioUnitario': 8.5, 'subtotal': 8.5, 'estado': 'EN_PREPARACION', 'tipoServicio': 'MESA',
          'observaciones': 'Sin cebolla, término medio', 'facturado': todoCobrado, 'cantidadFacturada': todoCobrado ? 1 : 0},
        {'ordenDetalleId': 'd3', 'platoId': 'p3', 'nombrePlato': 'Cola', 'cantidad': 1,
          'precioUnitario': 1, 'subtotal': 1.0, 'estado': 'CANCELADO', 'tipoServicio': 'MESA'},
      ],
    });

Future<void> _pintar(WidgetTester t, OrdenModel? o, {bool puedeCobrar = true, double texto = 1}) async {
  t.view.physicalSize = const Size(380, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(texto)), child: child!),
    home: Scaffold(
      body: PanelOrdenMesa(
        orden: o,
        puedeCobrar: puedeCobrar,
        onAbrir: () {},
        onPrecuenta: () {},
        onCobrar: () {},
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sin mesa elegida explica qué hacer', (t) async {
    await _pintar(t, null);
    expect(find.textContaining('Toca una mesa ocupada'), findsOneWidget);
    expect(find.text('Cobrar'), findsNothing);
  });

  testWidgets('muestra los platos sin los cancelados y lo que falta cobrar', (t) async {
    await _pintar(t, _orden());
    expect(find.text('Encebollado'), findsOneWidget);
    expect(find.text('Cola'), findsNothing);
    expect(find.text('\$15.50'), findsOneWidget); // 7.00 + 8.50
    expect(find.text('Cobrar'), findsOneWidget);
  });

  testWidgets('el mesero no ve el botón de cobrar', (t) async {
    await _pintar(t, _orden(), puedeCobrar: false);
    expect(find.text('Cobrar'), findsNothing);
    expect(find.text('Abrir orden'), findsOneWidget);
  });

  testWidgets('sin nada por cobrar no ofrece cobrar', (t) async {
    await _pintar(t, _orden(todoCobrado: true));
    expect(find.text('Cobrar'), findsNothing);
  });

  testWidgets('con el texto en "Muy grande" no se desborda', (t) async {
    await _pintar(t, _orden(), texto: 1.4);
    expect(t.takeException(), isNull);
  });
}
