import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:restaurant_app/core/models/orden_model.dart';
import 'package:restaurant_app/core/theme/app_theme.dart';
import 'package:restaurant_app/features/dashboard/presentation/panel_admin_escritorio.dart';
import 'package:restaurant_app/features/reportes/data/resumen_periodo_model.dart';

OrdenModel _orden(String id, String mesa, String estadoPlato, {String tipo = 'EN_MESA'}) => OrdenModel.fromJson({
      'ordenId': id, 'numeroOrden': 3, 'mesaId': mesa.isEmpty ? '' : 'm$id', 'numeroMesa': mesa,
      'sucursalId': 's1', 'estado': 'ABIERTA', 'tipoOrden': tipo, 'tipoOrigen': 'MESERO',
      'fechaCreacion': '2026-11-12T18:42:00Z', 'nombreUsuario': 'Carlos con un nombre bastante largo',
      'observaciones': tipo == 'PARA_LLEVAR' ? 'Juan, retira 17:00' : null,
      'detalles': [
        {'ordenDetalleId': 'd$id', 'platoId': 'p1', 'nombrePlato': 'Encebollado', 'cantidad': 2,
          'precioUnitario': 3.5, 'subtotal': 7.0, 'estado': estadoPlato, 'tipoServicio': 'MESA'},
      ],
    });

PlatoVentaModel _plato(String n, int u) => PlatoVentaModel(
    platoId: n, nombre: n, categoria: 'X', unidades: u, ventas: u * 3.5, ventasSinIva: u * 3, costo: null, unidadesCortesia: 0);

Future<void> _pintar(WidgetTester t, {required double ancho, double texto = 1, bool vacio = false}) async {
  t.view.physicalSize = Size(ancho, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(texto)), child: child!),
    home: Scaffold(
      body: PanelAdminEscritorio(
        cargando: false,
        ventasHoy: vacio ? 0 : 1284.5,
        facturasHoy: 46,
        mesasOcupadas: 7,
        mesasTotal: 18,
        ordenes: vacio
            ? const []
            : [
                _orden('1', 'Mesa 4', 'EN_PREPARACION'),
                _orden('2', '', 'PENDIENTE', tipo: 'PARA_LLEVAR'),
                _orden('3', 'Terraza 12 con un nombre de mesa larguísimo', 'LISTO'),
              ],
        semanaPrevia: [
          for (var i = 6; i >= 1; i--) (dia: DateTime(2026, 11, 12 - i), ventas: vacio ? 0.0 : 800.0 + i * 90),
        ],
        masVendidos: vacio ? const [] : [_plato('Encebollado', 24), _plato('Seco de pollo', 19), _plato('Jugo', 3)],
        avisoPago: const SizedBox.shrink(),
        avisoInventario: const SizedBox.shrink(),
        onAbrirOrden: (_) {},
        onVerMesas: () {},
        onVerReportes: () {},
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  for (final ancho in [752.0, 1192.0, 1440.0]) {
    testWidgets('se arma sin desbordes a $ancho px', (t) async {
      await _pintar(t, ancho: ancho);
      expect(t.takeException(), isNull);
      expect(find.text('Ventas de los últimos 7 días'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Platos listos'), findsOneWidget);
    });
  }

  testWidgets('con el texto en "Muy grande" no se desborda', (t) async {
    await _pintar(t, ancho: 1192, texto: 1.4);
    expect(t.takeException(), isNull);
  });

  testWidgets('sin ventas ni órdenes muestra los mensajes vacíos', (t) async {
    await _pintar(t, ancho: 1192, vacio: true);
    expect(find.text('No hay órdenes abiertas ahora.'), findsOneWidget);
    expect(find.text('Todavía no hay ventas hoy.'), findsOneWidget);
  });

  testWidgets('compara las ventas de hoy contra ayer', (t) async {
    await _pintar(t, ancho: 1440);
    // Ayer = 800 + 1×90 = 890; hoy 1284.50 → ▲ 44 %
    expect(find.textContaining('▲ 44%'), findsOneWidget);
  });
}
