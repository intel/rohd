// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtool_appbar.dart
// UI for rohd devtool appbar.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_help_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/platform_icon.dart';

/// App bar used by the ROHD DevTools UI.
class DevtoolAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Whether to render color emoji icons where available.
  const DevtoolAppBar({
    super.key,
    this.hasColorEmoji = kIsWeb,
  });

  /// Whether the icon set should prefer color emoji glyphs.
  final bool hasColorEmoji;

  @override

  /// Builds the app bar with help, license, and theme controls.
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;

    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.onPrimary,
      title: const Text('ROHD DevTool (Beta)'),
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'assets/icons/rohd_logo.png',
          fit: BoxFit.contain,
        ),
      ),
      actions: <Widget>[
        // ── Help ──
        DevToolsHelpButton(isDark: isDark),

        // ── Licenses ──
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                showLicensePage(context: context);
              },
              child: const Text(
                'Licenses',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),

        BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
          builder: (context, themeMode) {
            final isDark = themeMode == DevToolsThemeMode.dark;
            return IconButton(
              tooltip:
                  isDark ? 'Switch to light theme' : 'Switch to dark theme',
              onPressed: () {
                context.read<DevToolsThemeCubit>().toggleTheme();
              },
              icon: platformIcon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                isDark ? '☀️' : '🌙',
                size: 24,
                color: accentColor,
                hasColorEmoji: hasColorEmoji,
              ),
            );
          },
        ),
      ],
    );
  }

  @override

  /// The preferred height of the app bar.
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('hasColorEmoji', value: hasColorEmoji));
  }
}
