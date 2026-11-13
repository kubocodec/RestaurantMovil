import 'package:flutter/material.dart';

import '../models/user_model.dart';

// Opciones del menú lateral de escritorio, por rol.
//
// OJO: el menú de hamburguesa del celular es otro (shared/widgets/
// app_drawer.dart) y no se toca. Si una pantalla nueva entra en uno, mirar
// si también corresponde en el otro.

/// Módulos que solo ven algunos restaurantes o sucursales.
enum ModuloOpcional { inventario, adelantos }

class OpcionMenu {
  final IconData icono;
  final String etiqueta;
  final String ruta;

  /// Otras rutas que también marcan esta opción como activa (la orden de una
  /// mesa marca "Mesas").
  final List<String> tambien;

  /// Título del grupo que empieza con esta opción.
  final String? grupo;
  final ModuloOpcional? modulo;

  const OpcionMenu(this.icono, this.etiqueta, this.ruta,
      {this.tambien = const [], this.grupo, this.modulo});

  Iterable<String> get prefijos => [ruta, ...tambien];
}

List<OpcionMenu> opcionesDe(UserRole rol) => switch (rol) {
      UserRole.admin => const [
          OpcionMenu(Icons.space_dashboard_outlined, 'Panel', '/admin'),
          OpcionMenu(Icons.table_restaurant_outlined, 'Mesas', '/mesero/mesas',
              tambien: ['/mesero/orden', '/mesero/para-llevar'], grupo: 'Operación'),
          OpcionMenu(Icons.receipt_outlined, 'Por cobrar', '/cajero/ordenes', tambien: ['/cajero/factura']),
          OpcionMenu(Icons.soup_kitchen_outlined, 'Cocina', '/cocina'),
          OpcionMenu(Icons.point_of_sale_outlined, 'Caja', '/cajero/caja', grupo: 'Caja'),
          OpcionMenu(Icons.history_rounded, 'Comprobantes', '/cajero/comprobantes'),
          OpcionMenu(Icons.event_available_outlined, 'Adelantos', '/admin/adelantos',
              modulo: ModuloOpcional.adelantos),
          OpcionMenu(Icons.bar_chart_outlined, 'Reportes', '/admin/reportes', grupo: 'Gestión'),
          OpcionMenu(Icons.inventory_2_outlined, 'Inventario', '/admin/inventario',
              modulo: ModuloOpcional.inventario),
          OpcionMenu(Icons.settings_outlined, 'Configuración', '/admin/configuracion'),
        ],
      UserRole.cajero => const [
          OpcionMenu(Icons.space_dashboard_outlined, 'Panel', '/cajero'),
          OpcionMenu(Icons.point_of_sale_outlined, 'Caja', '/cajero/caja', grupo: 'Caja'),
          OpcionMenu(Icons.receipt_outlined, 'Facturación', '/cajero/ordenes', tambien: ['/cajero/factura']),
          OpcionMenu(Icons.history_rounded, 'Comprobantes', '/cajero/comprobantes'),
          OpcionMenu(Icons.event_available_outlined, 'Adelantos', '/cajero/adelantos',
              modulo: ModuloOpcional.adelantos),
          OpcionMenu(Icons.table_restaurant_outlined, 'Tomar pedidos', '/mesero/mesas',
              tambien: ['/mesero/orden', '/mesero/para-llevar'], grupo: 'Operación'),
        ],
      UserRole.mesero => const [
          OpcionMenu(Icons.space_dashboard_outlined, 'Panel', '/mesero'),
          OpcionMenu(Icons.table_restaurant_outlined, 'Mesas', '/mesero/mesas',
              tambien: ['/mesero/orden'], grupo: 'Operación'),
          OpcionMenu(Icons.takeout_dining_outlined, 'Para llevar', '/mesero/para-llevar'),
        ],
      UserRole.cocinero => const [
          OpcionMenu(Icons.space_dashboard_outlined, 'Panel', '/cocinero'),
          OpcionMenu(Icons.soup_kitchen_outlined, 'Órdenes de cocina', '/cocina', grupo: 'Cocina'),
        ],
      UserRole.superadmin => const [
          OpcionMenu(Icons.admin_panel_settings_outlined, 'Panel', '/superadmin'),
        ],
      UserRole.unknown => const [],
    };

bool _bajo(String path, String base) => path == base || path.startsWith('$base/');

/// La opción que corresponde a [path]: la del prefijo más largo que coincida
/// ("/admin/reportes" marca Reportes y no Panel).
OpcionMenu? opcionActiva(List<OpcionMenu> opciones, String path) {
  OpcionMenu? mejor;
  var largo = -1;
  for (final o in opciones) {
    for (final p in o.prefijos) {
      if (_bajo(path, p) && p.length > largo) {
        mejor = o;
        largo = p.length;
      }
    }
  }
  return mejor;
}

/// Pantalla de inicio de cada rol.
String inicioDe(UserRole rol) => switch (rol) {
      UserRole.superadmin => '/superadmin',
      UserRole.admin => '/admin',
      UserRole.cajero => '/cajero',
      UserRole.mesero => '/mesero',
      UserRole.cocinero => '/cocinero',
      UserRole.unknown => '/login',
    };

/// Si [rol] puede estar en [path]. En la web hay barra de direcciones y
/// cualquiera podía escribir /#/admin; el celular no la tiene y ahí no se
/// aplica (ver AppRouter). Los permisos de verdad los pone el backend: esto
/// solo evita pantallas que fallarían al cargar.
bool rutaPermitida(UserRole rol, String path) {
  if (_bajo(path, '/login')) return true;
  return switch (rol) {
    UserRole.superadmin => true,
    UserRole.admin => !_bajo(path, '/superadmin'),
    UserRole.cajero => _bajo(path, '/cajero') || _bajo(path, '/mesero'),
    UserRole.mesero => _bajo(path, '/mesero'),
    UserRole.cocinero => _bajo(path, '/cocinero') || _bajo(path, '/cocina'),
    UserRole.unknown => false,
  };
}

String nombreDelRol(UserRole rol) => switch (rol) {
      UserRole.superadmin => 'Super administrador',
      UserRole.admin => 'Administrador',
      UserRole.cajero => 'Cajero',
      UserRole.mesero => 'Mesero',
      UserRole.cocinero => 'Cocina',
      UserRole.unknown => '',
    };
