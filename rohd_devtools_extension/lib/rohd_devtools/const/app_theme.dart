// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_theme.dart
// Centralized theme definitions for ROHD DevTools.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

const _fontFallback = <String>['Noto Color Emoji'];

TextTheme _withFontFallback(TextTheme theme) => theme.apply(
      fontFamilyFallback: _fontFallback,
    );

/// Dark theme colors
class DarkThemeColors {
  /// Colors matching VS Code dark theme.
  static const scaffoldBackground = Color(0xFF1E1E1E);

  /// Card background color.
  static const cardBackground = Color(0xFF252526);

  /// Panel background color.
  static const panelBackground = Color(0xFF252526);

  /// Panel header color.
  static const panelHeader = Color(0xFF333333);

  /// Divider color.
  static const divider = Color(0xFF3C3C3C);

  /// Primary text color.
  static const text = Colors.white;

  /// Secondary text color.
  static const textSecondary = Colors.white70;

  /// AppBar background color.
  static const appBarBackground = Color(0xFF252526);
}

/// Light theme colors
class LightThemeColors {
  /// Slightly darker than white
  /// to reduce eye strain.
  static const scaffoldBackground = Color(0xFFE8E8E8);

  /// Card background color.
  static const cardBackground = Colors.white;

  /// Panel background color.
  static const panelBackground = Color(0xFFFAFAFA);

  /// Panel header color.
  static const panelHeader = Color(0xFFF5F5F5);

  /// Divider color.
  static const divider = Colors.black26;

  /// Primary text color.
  static const text = Colors.black87;

  /// Secondary text color.
  static const textSecondary = Colors.black54;

  /// AppBar background color.
  static const appBarBackground = Color(0xFFF5F5F5);
}

/// AppBar themes
class AppBarThemes {
  /// Dark theme AppBar - matches VS Code dark theme
  static const dark = AppBarTheme(
    backgroundColor: DarkThemeColors.appBarBackground,
    foregroundColor: DarkThemeColors.text,
    elevation: 0,
    shadowColor: Colors.transparent,
  );

  /// Light theme AppBar
  static const light = AppBarTheme(
    backgroundColor: LightThemeColors.appBarBackground,
    foregroundColor: LightThemeColors.text,
    elevation: 0,
    shadowColor: Colors.transparent,
  );
}

/// Build dark theme data
ThemeData buildDarkTheme() => ThemeData.dark().copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4A90A4),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: DarkThemeColors.scaffoldBackground,
      cardColor: DarkThemeColors.cardBackground,
      dividerColor: DarkThemeColors.divider,
      cardTheme: const CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        color: DarkThemeColors.cardBackground,
      ),
      appBarTheme: AppBarThemes.dark,
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF3C3C3C),
        elevation: 8,
        shadowColor: Colors.black54,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF2D2D30).withValues(alpha: 0.90),
        elevation: 16,
        shadowColor: Colors.black54,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      // Disable hover effects (workaround for Flutter #172079)
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      textTheme: _withFontFallback(ThemeData.dark().textTheme),
      primaryTextTheme: _withFontFallback(ThemeData.dark().primaryTextTheme),
    );

/// Build light theme data
ThemeData buildLightTheme() => ThemeData.light().copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A90A4)),
      scaffoldBackgroundColor: LightThemeColors.scaffoldBackground,
      cardColor: LightThemeColors.cardBackground,
      dividerColor: LightThemeColors.divider,
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        color: LightThemeColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
      ),
      appBarTheme: AppBarThemes.light,
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white.withValues(alpha: 0.85),
        elevation: 8,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        textStyle: const TextStyle(color: Colors.black87, fontSize: 13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 16,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(color: Colors.black54, fontSize: 14),
      ),
      // Disable hover effects (workaround for Flutter #172079)
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      textTheme: _withFontFallback(ThemeData.light().textTheme),
      primaryTextTheme: _withFontFallback(ThemeData.light().primaryTextTheme),
    );
