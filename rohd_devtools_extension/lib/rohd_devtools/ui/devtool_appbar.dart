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
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'assets/rohd_icon.png',
          width: 28,
          height: 28,
          fit: BoxFit.contain,
        ),
      ),
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
          onSelected: (value) {
            // The extension iframe is served by DevTools at a path like:
            //   http://host:port/devtools_extensions/rohd_0.0.1/index.html
            // DevTools serves everything under build/ at that root, so
            // the standalone viewers at build/waves/ and build/schematics/
            // are accessible relative to the current directory.
            //
            // The standalone debugger runs on port 9099 on the same host,
            // so we construct an absolute URL for that case.
            final String toolUrl;
            if (value.startsWith('http')) {
              toolUrl = value;
            } else {
              final href = browserCurrentHref();
              final base = href.substring(0, href.lastIndexOf('/') + 1);
              toolUrl = '$base$value';
            }
            debugPrint('[Tools] Opening: $toolUrl');
            openBrowserTab(toolUrl);
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'waves/index.html',
              child: Text('Wave Viewer'),
            ),
            const PopupMenuItem<String>(
              value: 'schematics/index.html',
              child: Text('Schematic Viewer'),
            ),
            const PopupMenuItem<String>(
              value: 'debugger/index.html',
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
        DevToolsHelpButton(isDark: isDark),

        // ── Licenses ──
        TextButton(
          onPressed: () {
            registerBundledThirdPartyLicenses();
            showLicensePage(context: context);
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
