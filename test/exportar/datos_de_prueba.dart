import 'package:restaurant_app/core/models/caja_model.dart';
import 'package:restaurant_app/core/models/factura_model.dart';
import 'package:restaurant_app/core/models/orden_model.dart';
import 'package:restaurant_app/features/inventario/data/inventario_repository.dart';
import 'package:restaurant_app/features/reportes/data/reportes_repository.dart';
import 'package:restaurant_app/features/reportes/data/resumen_periodo_model.dart';
import 'package:restaurant_app/features/reportes/exportar/datos_exportacion.dart';

// Datos inventados con la forma que devuelve el servidor (se arman con los
// mismos fromJson que usa la app). Incluyen a propósito texto con & < > y
// tildes, un comprobante anulado y una cortesía.

ResumenPeriodoModel resumenDePrueba({bool conCostos = true}) => ResumenPeriodoModel.fromJson({
      'alcance': 'Sucursal Centro',
      'desde': '2026-11-01',
      'hasta': '2026-11-12',
      'desdeAnterior': '2026-10-20',
      'hastaAnterior': '2026-10-31',
      'actual': {
        'ventas': 1200.50, 'propinas': 50, 'iva': 140.2, 'descuentos': 10, 'comprobantes': 40,
        'mesas': 35, 'mesasEnSala': 30, 'personas': 0, 'mesasConPersonas': 0, 'ventasConPersonas': 0,
        'costo': conCostos ? 400 : 0, 'lineasConCosto': conCostos ? 12 : 0,
        'unidadesCortesia': 2, 'valorCortesias': 7.5,
      },
      'anterior': {
        'ventas': 1000, 'propinas': 40, 'iva': 120, 'descuentos': 5, 'comprobantes': 38,
        'mesas': 33, 'mesasEnSala': 30, 'personas': 0, 'mesasConPersonas': 0, 'ventasConPersonas': 0,
        'costo': conCostos ? 350 : 0, 'lineasConCosto': conCostos ? 10 : 0,
        'unidadesCortesia': 0, 'valorCortesias': 0,
      },
      'platos': [
        {'platoId': 'p1', 'nombre': 'Encebollado', 'categoria': 'Sopas', 'unidades': 30, 'ventas': 105.0,
          'ventasSinIva': 91.304348, 'costo': conCostos ? 1.2 : null, 'unidadesCortesia': 1},
        {'platoId': 'p2', 'nombre': 'Pizza "Ñandú" & jamón <especial>', 'categoria': 'Pizzas', 'unidades': 12,
          'ventas': 144.0, 'ventasSinIva': 125.217391, 'costo': conCostos ? 4 : null, 'unidadesCortesia': 0},
        {'platoId': 'p3', 'nombre': 'Jugo de naranja', 'categoria': 'Bebidas', 'unidades': 25, 'ventas': 37.5,
          'ventasSinIva': 32.608696, 'costo': null, 'unidadesCortesia': 1},
      ],
      'sinVenta': [
        {'platoId': 'p4', 'nombre': 'Tres leches', 'categoria': 'Postres', 'disponible': false},
      ],
      'porHora': [
        {'dia': 1, 'hora': 13, 'ordenes': 5, 'ventas': 120.0},
        {'dia': 6, 'hora': 20, 'ordenes': 8, 'ventas': 210.25},
      ],
      'diasDelPeriodo': [2, 2, 1, 2, 2, 2, 1],
      'porTipo': [
        {'tipo': 'EN_MESA', 'ordenes': 30, 'ventas': 1000.0},
        {'tipo': 'PARA_LLEVAR', 'ordenes': 8, 'ventas': 150.5},
      ],
      'metodosPago': [
        {'metodo': 'EFECTIVO', 'monto': 800.0},
        {'metodo': 'ADELANTOS', 'monto': 50.0},
      ],
      'meseros': [
        {'nombre': 'Carlos', 'ordenes': 20, 'ventas': 700.0, 'propinas': 30.0},
        {'nombre': 'Andrea', 'ordenes': 18, 'ventas': 450.5, 'propinas': 20.0},
      ],
      'ordenesAnuladas': 1,
      'valorAnulado': 12.0,
    });

FacturaModel comprobante(String numero, String estado, double total,
        {List<Map<String, dynamic>> items = const [], List<Map<String, dynamic>> pagos = const []}) =>
    FacturaModel.fromJson({
      'facturaVentaId': numero,
      'numeroFactura': numero,
      'ordenId': 'o-$numero',
      'numeroOrden': 7,
      'estado': estado,
      'tipoComprobante': 'FACTURA',
      'subtotal': total / 1.15,
      'descuento': 0,
      'ivaPorcentaje': 15,
      'subtotalGravado': total / 1.15,
      'subtotalSinIva': 0,
      'iva': total - total / 1.15,
      'propina': 0,
      'total': total,
      'nombreCliente': 'Cliente & Hijos',
      'cedulaRucCliente': '0912345678',
      'cajero': 'Caja 1',
      'lugar': 'Mesa 4',
      'fecha': '2026-11-05T18:30:00Z',
      'items': items,
      'pagos': pagos,
    });

CierreDetalladoModel cierreDePrueba() => CierreDetalladoModel.fromJson({
      'aperturaCierreCajaId': 'c1',
      'nombreCaja': 'Caja 1',
      'estado': 'CERRADA',
      'usuarioApertura': 'Ana',
      'usuarioCierre': 'Ana',
      'fechaApertura': '2026-11-05T13:00:00Z',
      'fechaCierre': '2026-11-06T03:00:00Z',
      'montoInicial': 50,
      'totalVentas': 300,
      'totalVentasEfectivo': 200,
      'totalFacturas': 10,
      'totalIngresos': 20,
      'totalEgresos': 15,
      'montoEsperado': 255,
      'montoContado': 250,
      'diferencia': -5,
      'observaciones': 'Faltan \$5',
      'ingresos': [
        {'tipo': 'INGRESO', 'monto': 20, 'concepto': 'Cambio', 'usuario': 'Ana', 'fecha': '2026-11-05T14:00:00Z'},
      ],
      'egresos': [
        {'tipo': 'EGRESO', 'monto': 15, 'concepto': 'Hielo', 'usuario': 'Ana', 'fecha': '2026-11-05T16:00:00Z'},
      ],
      'ventasPorPlato': [],
      'ventasPorMetodo': [],
    });

/// Un libro con todas las secciones y datos en cada una.
DatosExportacion datosCompletos({bool variasSucursales = false}) {
  final d = DatosExportacion(
    alcance: 'Sucursal Centro',
    desde: DateTime(2026, 11, 1),
    hasta: DateTime(2026, 11, 12),
    secciones: SeccionExcel.values.toSet(),
    variasSucursales: variasSucursales,
    generado: DateTime(2026, 11, 12, 16, 45),
  );
  d.resumen = resumenDePrueba();
  d.ventasDia.add(('Centro', DateTime(2026, 11, 5), ResumenDiarioModel.fromJson({
    'nombreSucursal': 'Centro', 'totalOrdenes': 12, 'totalFacturas': 10, 'totalMesasCobradas': 9,
    'totalVentas': 300, 'totalDescuentos': 2, 'totalIva': 35, 'totalPropinas': 10, 'totalNeto': 255,
    'totalCosto': 90, 'gananciaEstimada': 165, 'unidadesCortesia': 1, 'valorCortesias': 3.5,
  })));
  d.comprobantes.addAll([
    ('Centro', comprobante('001-001-000001', 'PAGADA', 23.0, items: [
      {'nombre': 'Encebollado', 'cantidad': 2, 'subtotal': 7.0},
      {'nombre': 'Seco de pollo', 'cantidad': 1, 'subtotal': 4.5, 'cortesia': true},
    ], pagos: [
      {'nombreMetodoPago': 'EFECTIVO', 'monto': 13.0},
      {'nombreMetodoPago': 'TARJETA', 'monto': 10.0},
    ])),
    ('Centro', comprobante('001-001-000002', 'ANULADA', 100.0, items: [
      {'nombre': 'Churrasco', 'cantidad': 10, 'subtotal': 85.0},
    ])),
    ('Centro', comprobante('001-001-000003', 'PAGADA', 11.5)),
  ]);
  d.cierres.add(('Centro', cierreDePrueba()));
  d.cortesias.add(('Centro', CortesiaItemModel.fromJson({
    'fecha': '2026-11-05T19:00:00Z', 'numeroOrden': 7, 'lugar': 'Mesa 4', 'plato': 'Seco de pollo',
    'cantidad': 1, 'valor': 4.5, 'motivo': 'Cumpleaños', 'autorizadaPor': 'Ana', 'cobrada': true,
  })));
  d.anuladas.add(('Centro', OrdenModel.fromJson({
    'ordenId': 'o9', 'numeroOrden': 9, 'mesaId': 'm1', 'numeroMesa': 'Mesa 2', 'sucursalId': 's1',
    'estado': 'CANCELADA', 'tipoOrden': 'EN_MESA', 'tipoOrigen': 'MESERO',
    'fechaCreacion': '2026-11-04T17:00:00Z', 'fechaCierre': '2026-11-04T17:20:00Z',
    'nombreUsuario': 'Carlos', 'motivoCancelacion': 'Cliente se fue', 'canceladaPor': 'Ana',
    'detalles': [
      {'ordenDetalleId': 'd1', 'platoId': 'p1', 'nombrePlato': 'Encebollado', 'cantidad': 2,
        'precioUnitario': 3.5, 'subtotal': 7.0, 'estado': 'PENDIENTE', 'tipoServicio': 'MESA'},
      {'ordenDetalleId': 'd2', 'platoId': 'p2', 'nombrePlato': 'Cola', 'cantidad': 1,
        'precioUnitario': 1, 'subtotal': 1.0, 'estado': 'CANCELADO', 'tipoServicio': 'MESA'},
    ],
  })));
  d.conInventario.add('s1');
  d.insumos.addAll([
    ('Centro', InsumoModel.fromJson({
      'insumoId': 'i1', 'nombre': 'Ron añejo', 'unidad': 'MILILITRO', 'categoria': 'Licores', 'activo': true,
      'stock': 8440, 'stockMinimo': 4500, 'costoPromedio': 0.0189333, 'valorStock': 159.80,
      'bajoMinimo': false, 'negativo': false, 'presentacionNombre': 'Botella', 'presentacionContenido': 750,
    })),
    ('Centro', InsumoModel.fromJson({
      'insumoId': 'i2', 'nombre': 'Queso fresco', 'unidad': 'GRAMO', 'categoria': 'Lácteos', 'activo': true,
      'stock': -600, 'stockMinimo': 2000, 'costoPromedio': 0.0064, 'valorStock': 0,
      'bajoMinimo': true, 'negativo': true,
    })),
  ]);
  d.platosStock.add(('Centro', InventarioItemModel.fromJson({
    'sucursalPlatoId': 'sp1', 'platoId': 'p5', 'nombrePlato': 'Cerveza 600 ml', 'categoria': 'Bebidas',
    'subcategoria': 'Cervezas', 'modoInventario': 'UNIDADES', 'stock': 3, 'stockMinimo': 12,
    'unidad': 'u', 'agotado': false, 'bajoMinimo': true, 'disponible': true,
  })));
  d.compras.add(('Centro', CompraModel.fromJson({
    'compraId': 'k1', 'fecha': '2026-11-03', 'proveedor': 'Distribuidora Sur', 'numeroDocumento': '001-002-345',
    'total': 58, 'usuario': 'Ana', 'nota': '', 'totalItems': 1,
    'items': [
      {'insumoId': 'i2', 'nombre': 'Queso fresco', 'unidad': 'GRAMO', 'cantidad': 9062.5, 'costoUnitario': 0.0064, 'subtotal': 58},
    ],
  })));
  d.proveedores.add(ProveedorModel.fromJson({
    'proveedorId': 'pr1', 'nombre': 'Distribuidora Sur', 'ruc': '0990000000001', 'telefono': '042000000',
    'email': 'ventas@ejemplo.com', 'activo': true,
  }));
  return d;
}
