// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// theme_cubit.dart
// Manages light/dark theme toggle for ROHD DevTools.

// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';

/// Enum for theme modes.
enum DevToolsThemeMode {
  /// Light theme mode.
  light,

  /// Dark theme mode.
  dark,
}

/// Cubit for managing DevTools theme state.
class DevToolsThemeCubit extends Cubit<DevToolsThemeMode> {
  /// Constructor for [DevToolsThemeCubit].
  DevToolsThemeCubit() : super(DevToolsThemeMode.dark);

  /// Toggle between light and dark themes.
  void toggleTheme() {
    emit(
      state == DevToolsThemeMode.dark
          ? DevToolsThemeMode.light
          : DevToolsThemeMode.dark,
    );
  }

  /// Set a specific theme mode.
  void setTheme(DevToolsThemeMode mode) {
    emit(mode);
  }

  /// Whether the current theme is dark.
  bool get isDark => state == DevToolsThemeMode.dark;
}
