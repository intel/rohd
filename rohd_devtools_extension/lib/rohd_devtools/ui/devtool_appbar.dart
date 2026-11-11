// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtool_appbar.dart
// UI for rohd devtool appbar.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/extension_manager_bridge.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/third_party_license_registry.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_help_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/platform_icon.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/rohd_website_button.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/browser_window.dart';

/// A custom AppBar for the ROHD DevTool application.
///
/// Provides Help, Theme toggle, Licenses, Pause/Resume, and emoji icon
/// support matching the standalone version's app bar.
class DevtoolAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool _hasColorEmoji;
  final bool _isPaused;
  final VoidCallback? _onPauseResume;

  /// Creates a [DevtoolAppBar].
  const DevtoolAppBar({
    super.key,
    bool hasColorEmoji = true,
    bool isPaused = false,
    VoidCallback? onPauseResume,
  })  : _hasColorEmoji = hasColorEmoji,
        _isPaused = isPaused,
        _onPauseResume = onPauseResume;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        FlagProperty(
          'hasColorEmoji',
          value: _hasColorEmoji,
          ifFalse: 'using fallback icons',
        ),
      )
      ..add(
        FlagProperty(
          'isPaused',
          value: _isPaused,
          ifTrue: 'paused',
          ifFalse: 'running',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback?>.has('onPauseResume', _onPauseResume),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      backgroundColor:
          isDark ? const Color(0xFF252526) : const Color(0xFFF5F5F5),
      title: Text(
        'ROHD DevTools',
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      ),
      leading: const RohdWebsiteButton(),
      actions: <Widget>[
        // ── Tools menu ──
        PopupMenuButton<String>(
          icon: platformIcon(
            Icons.construction,
            '🧰',
            size: 24,
            hasColorEmoji: _hasColorEmoji,
          ),
          tooltip: 'Tools',
          onSelected: (url) {
            debugPrint('[Tools] Opening: $url');
            openBrowserTab(url);
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'https://intel.github.io/rohd-wave-viewer/',
              child: Text('Wave Viewer'),
            ),
            const PopupMenuItem<String>(
              value: 'https://intel.github.io/rohd-schematic-viewer/',
              child: Text('Schematic Viewer'),
            ),
            const PopupMenuItem<String>(
              value: 'https://intel.github.io/rohd/rohd-live-debugger/',
              child: Text('Standalone Debugger'),
            ),
          ],
        ),

        // ── Pause / Resume waveform updates ──
        if (_onPauseResume != null)
          IconButton(
            icon: platformIcon(
              _isPaused ? Icons.play_arrow : Icons.pause,
              _isPaused ? '▶️' : '⏸️',
              size: 24,
              hasColorEmoji: _hasColorEmoji,
            ),
            onPressed: _onPauseResume,
            tooltip: _isPaused
                ? 'Resume waveform updates'
                : 'Pause waveform updates (keeps connection alive)',
          ),

        // ── Refresh ──
        IconButton(
          icon: platformIcon(
            Icons.refresh,
            '🔃',
            size: 24,
            hasColorEmoji: _hasColorEmoji,
          ),
          onPressed: () {
            // Trigger a rebuild of the tree structure page
          },
          tooltip: 'Refresh',
        ),

        // ── Help ──
        DevToolsHelpButton(isDark: isDark, hasColorEmoji: _hasColorEmoji),

        // ── Licenses ──
        TextButton(
          onPressed: () {
            showRohdLicensePage(context);
          },
          child: Text(
            'Licenses',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),

        // ── Theme toggle ──
        BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
          builder: (context, themeMode) {
            final isDark = themeMode == DevToolsThemeMode.dark;
            return Tooltip(
              message:
                  isDark ? 'Switch to light theme' : 'Switch to dark theme',
              child: IconButton(
                icon: platformIcon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  isDark ? '☀️' : '🌙',
                  size: 24,
                  hasColorEmoji: _hasColorEmoji,
                ),
                onPressed: () {
                  context.read<DevToolsThemeCubit>().toggleTheme();
                  // Also toggle the DevToolsExtension's outer MaterialApp
                  // theme so colors propagate correctly.
                  setExtensionDarkThemeEnabled(enabled: !isDark);
                },
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
