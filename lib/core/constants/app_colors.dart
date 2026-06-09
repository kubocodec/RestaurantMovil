import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // === Paleta principal: Marrón / Tierra / Crema ===
  static const Color primary = Color(0xFF5D4037);       // Marrón oscuro
  static const Color primaryLight = Color(0xFF8D6E63);  // Marrón claro
  static const Color primaryDark = Color(0xFF3E2723);   // Marrón muy oscuro
  static const Color primaryVariant = Color(0xFF795548); // Marrón medio

  // Tonos tierra
  static const Color earth1 = Color(0xFFA1887F); // Tierra claro
  static const Color earth2 = Color(0xFF6D4C41); // Tierra medio
  static const Color earth3 = Color(0xFF4E342E); // Tierra oscuro

  // Fondos crema/beige
  static const Color background = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFF5EFE6);
  static const Color surfaceVariant = Color(0xFFEDE0D4);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Texto
  static const Color textPrimary = Color(0xFF3E2723);
  static const Color textSecondary = Color(0xFF6D4C41);
  static const Color textHint = Color(0xFFA1887F);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Semánticos
  static const Color success = Color(0xFF388E3C);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF57C00);
  static const Color warningLight = Color(0xFFFFF3E0);
  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color info = Color(0xFF1565C0);
  static const Color infoLight = Color(0xFFE3F2FD);

  // Estados de mesa
  static const Color mesaLibre = Color(0xFF43A047);
  static const Color mesaOcupada = Color(0xFFE53935);
  static const Color mesaReservada = Color(0xFF1E88E5);
  static const Color mesaMantenimiento = Color(0xFF757575);

  // Estados de orden/item
  static const Color estadoPendiente = Color(0xFFF57C00);
  static const Color estadoEnProceso = Color(0xFF1E88E5);
  static const Color estadoListo = Color(0xFF43A047);
  static const Color estadoCerrado = Color(0xFF757575);
  static const Color estadoCancelado = Color(0xFFC62828);

  // Divisor y borde
  static const Color divider = Color(0xFFD7CCC8);
  static const Color border = Color(0xFFBCAAA4);

  // Roles colores de badge
  static const Color adminColor = Color(0xFF5D4037);
  static const Color cajeroColor = Color(0xFF2E7D32);
  static const Color meseroColor = Color(0xFF1565C0);
  static const Color cocineroColor = Color(0xFFE65100);
}
