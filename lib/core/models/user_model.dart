import 'package:equatable/equatable.dart';

enum UserRole { superadmin, admin, cajero, mesero, cocinero, unknown }

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.superadmin: return 'Super Administrador';
      case UserRole.admin:      return 'Administrador';
      case UserRole.cajero:     return 'Cajero';
      case UserRole.mesero:     return 'Mesero';
      case UserRole.cocinero:   return 'Cocinero';
      case UserRole.unknown:    return 'Usuario';
    }
  }

  static UserRole fromString(String? value) {
    final s = value?.replaceFirst('ROLE_', '').toUpperCase();
    switch (s) {
      case 'SUPER_ADMIN':
      case 'SUPERADMIN':
      case 'ADMINISTRADOR': return UserRole.superadmin;
      case 'ADMIN':         return UserRole.admin;
      case 'CAJERO':        return UserRole.cajero;
      case 'MESERO':        return UserRole.mesero;
      case 'COCINERO':      return UserRole.cocinero;
      default:              return UserRole.unknown;
    }
  }
}

class UserModel extends Equatable {
  final String id;
  final String nombre;
  final String usuario;
  final String correo;
  final UserRole rol;
  final String sucursalId;
  final String restaurantId;
  final String tenantId;
  final String sucursalNombre;
  final String accessToken;
  final String refreshToken;
  /// Aviso de pago del servicio próximo a vencer (null si no aplica).
  final String? avisoPago;

  const UserModel({
    required this.id,
    required this.nombre,
    required this.usuario,
    required this.correo,
    required this.rol,
    required this.sucursalId,
    required this.restaurantId,
    required this.tenantId,
    required this.sucursalNombre,
    required this.accessToken,
    required this.refreshToken,
    this.avisoPago,
  });

  factory UserModel.fromLoginResponse(Map<String, dynamic> json) {
    final d = json['data'] ?? json;
    final rolRaw = d['rol'];
    final rolStr = rolRaw is String ? rolRaw : (rolRaw is Map ? rolRaw['nombre'] : null);
    return UserModel(
      id:            d['usuarioId']?.toString() ?? '',
      nombre:        d['nombre']?.toString() ?? '',
      usuario:       d['usuario']?.toString() ?? '',
      correo:        d['correo']?.toString() ?? '',
      rol:           UserRoleExtension.fromString(rolStr),
      sucursalId:    d['sucursalId']?.toString() ?? '',
      restaurantId:  d['restaurantId']?.toString() ?? '',
      tenantId:      d['tenantId']?.toString() ?? '',
      sucursalNombre: '',
      accessToken:   d['accessToken']?.toString() ?? '',
      refreshToken:  d['refreshToken']?.toString() ?? '',
      avisoPago:     d['avisoPago']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'nombre': nombre, 'usuario': usuario, 'correo': correo,
    'rol': rol.name, 'sucursalId': sucursalId, 'restaurantId': restaurantId,
    'tenantId': tenantId, 'sucursalNombre': sucursalNombre,
    'accessToken': accessToken, 'refreshToken': refreshToken,
    'avisoPago': avisoPago,
  };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id:            json['id']?.toString() ?? '',
    nombre:        json['nombre']?.toString() ?? '',
    usuario:       json['usuario']?.toString() ?? '',
    correo:        json['correo']?.toString() ?? '',
    rol:           UserRoleExtension.fromString(json['rol']?.toString()),
    sucursalId:    json['sucursalId']?.toString() ?? '',
    restaurantId:  json['restaurantId']?.toString() ?? '',
    tenantId:      json['tenantId']?.toString() ?? '',
    sucursalNombre: json['sucursalNombre']?.toString() ?? '',
    accessToken:   json['accessToken']?.toString() ?? '',
    refreshToken:  json['refreshToken']?.toString() ?? '',
    avisoPago:     json['avisoPago']?.toString(),
  );

  @override
  List<Object?> get props => [id, usuario, rol, sucursalId, accessToken];
}
