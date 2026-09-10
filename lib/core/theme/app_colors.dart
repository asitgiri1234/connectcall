import 'package:flutter/material.dart';

/// Semantic colour tokens. Widgets reference these by meaning, never by
/// raw hex, so light and dark stay consistent and a rebrand is one file.
class AppColors {
  const AppColors._();

  // Brand
  static const Color primary = Color(0xFF4F46E5); // indigo
  static const Color primaryDark = Color(0xFF818CF8);

  // Call affordances. These keep their meaning in both themes.
  static const Color accept = Color(0xFF16A34A);
  static const Color decline = Color(0xFFDC2626);
  static const Color muted = Color(0xFFEF4444);

  // Presence
  static const Color online = Color(0xFF22C55E);
  static const Color offline = Color(0xFF94A3B8);

  // Network quality indicator
  static const Color qualityGood = Color(0xFF22C55E);
  static const Color qualityFair = Color(0xFFF59E0B);
  static const Color qualityPoor = Color(0xFFEF4444);

  // Light surfaces
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightTextMuted = Color(0xFF64748B);

  // Dark surfaces
  static const Color darkBg = Color(0xFF0B1120);
  static const Color darkSurface = Color(0xFF162032);
  static const Color darkBorder = Color(0xFF1E293B);
  static const Color darkText = Color(0xFFF1F5F9);
  static const Color darkTextMuted = Color(0xFF94A3B8);

  // Call screens are always dark, regardless of app theme. A bright screen
  // against your face mid-call is hostile, and it matches user expectation
  // set by every other calling app.
  static const Color callBg = Color(0xFF0A0F1C);
  static const Color callControl = Color(0x1FFFFFFF);
}
