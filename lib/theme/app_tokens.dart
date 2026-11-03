import 'package:flutter/material.dart';

/// Tokens primitivos: valores crudos. Ningún widget debe usarlos directo;
/// se consumen a través de `AppPalette` y `AppThemeColors`.
class AppPrimitives {
  AppPrimitives._();

  // --- Cool ---
  static const coolBg = Color(0xFFF6FAFC);
  static const coolBgDark = Color(0xFF071A24);
  static const coolSurface = Color(0xFFFFFFFF);
  static const coolSurfaceDark = Color(0xFF0E2836);
  static const coolTeal = Color(0xFF0F766E);
  static const coolTealSoft = Color(0xFF14B8A6);
  static const coolSky = Color(0xFF0369A1);
  static const coolSkySoft = Color(0xFF38BDF8);
  static const coolIndigo = Color(0xFF4F46E5);
  static const coolMint = Color(0xFF6EE7B7);

  // --- Warm ---
  static const warmBg = Color(0xFFFFF8F0);
  static const warmBgDark = Color(0xFF2A0F1E);
  static const warmSurface = Color(0xFFFFFFFF);
  static const warmSurfaceDark = Color(0xFF3B1729);
  static const warmRaspberry = Color(0xFFC2185B);
  static const warmPeach = Color(0xFFE07A5F);
  static const warmPink = Color(0xFFF472B6);
  static const warmPlum = Color(0xFF7C3AED);

  // --- RGB ---
  static const rgbBg = Color(0xFFF3F0FF);
  static const rgbBgDark = Color(0xFF121218);
  static const rgbSurface = Color(0xFFFFFFFF);
  static const rgbSurfaceDark = Color(0xFF1C1C24);
  static const rgbViolet = Color(0xFF6D28D9);
  static const rgbVioletSoft = Color(0xFFA78BFA);
  static const rgbTurquoise = Color(0xFF0E7490);
  static const rgbCyan = Color(0xFF22D3EE);
  static const rgbCoral = Color(0xFFF97362);

  // --- Neutrales ---
  static const ink = Color(0xFF1E293B);
  static const inkSoft = Color(0xFF475569);
  static const paper = Color(0xFFF1F5F9);
  static const line = Color(0xFFCBD5E1);
  static const lineDark = Color(0xFF3A4A5A);
  static const snow = Color(0xFFF8FAFC);

  // --- Estado ---
  static const green600 = Color(0xFF15803D);
  static const green300 = Color(0xFF34D399);
  static const amber600 = Color(0xFFB45309);
  static const amber300 = Color(0xFFFBBF24);
  static const red600 = Color(0xFFB91C1C);
  static const red300 = Color(0xFFFB7185);

  // --- Espaciado (escala 4) ---
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space6 = 24;
  static const double space8 = 32;

  // --- Radios ---
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  // --- Tipografía (sistema, sin fuentes externas) ---
  static const double textXs = 11;
  static const double textSm = 12;
  static const double textMd = 14;
  static const double textLg = 16;
  static const double textXl = 20;
  static const double text2xl = 24;
  static const double text3xl = 28;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Altura mínima táctil (Material/Android).
  static const double touchTarget = 48;
}
