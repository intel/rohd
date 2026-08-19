// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_theme_test.dart
// Tests for ROHD DevTools theme configurations.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/const/app_theme.dart';

void main() {
  group('buildDarkTheme', () {
    test('preserves the DevTools dark visual contract', () {
      final theme = buildDarkTheme();

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, DarkThemeColors.scaffoldBackground);
      expect(theme.cardColor, DarkThemeColors.cardBackground);
      expect(theme.dividerColor, DarkThemeColors.divider);
      expect(
          theme.appBarTheme.backgroundColor, DarkThemeColors.appBarBackground);
      expect(theme.appBarTheme.foregroundColor, DarkThemeColors.text);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.shadowColor, Colors.transparent);
      expect(theme.hoverColor, Colors.transparent);
      expect(theme.splashColor, Colors.transparent);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(
          theme.textTheme.bodyMedium!.fontFamilyFallback, ['Noto Color Emoji']);
    });
  });

  group('buildLightTheme', () {
    test('preserves the DevTools light visual contract', () {
      final theme = buildLightTheme();

      expect(theme.brightness, Brightness.light);
      expect(
          theme.scaffoldBackgroundColor, LightThemeColors.scaffoldBackground);
      expect(theme.cardColor, LightThemeColors.cardBackground);
      expect(theme.dividerColor, LightThemeColors.divider);
      expect(
          theme.appBarTheme.backgroundColor, LightThemeColors.appBarBackground);
      expect(theme.appBarTheme.foregroundColor, LightThemeColors.text);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.shadowColor, Colors.transparent);
      expect(theme.hoverColor, Colors.transparent);
      expect(theme.splashColor, Colors.transparent);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(
          theme.textTheme.bodyMedium!.fontFamilyFallback, ['Noto Color Emoji']);
    });
  });
}
