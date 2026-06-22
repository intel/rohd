// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Main entry for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'dart:js_interop';

import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_extensions/api.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/const/app_theme.dart';
import 'package:rohd_devtools_extension/rohd_devtools/view/rohd_devtools_page.dart';
import 'package:rohd_devtools_extension/rohd_devtools_observer.dart';
import 'package:web/web.dart' as web;

void main() {
  debugPrint('[main.dart] Starting ROHD DevTools Extension...');
  debugPrint('[main.dart] Platform: ${kIsWeb ? "Web" : "Native"}');

  // Policy: preserve extension UI state across target-app restarts.
  // DevTools emits forceReload when the debugged app restarts, but a full page
  // reload would discard local selection and snapshot state that the extension
  // can now recover through its own reconnect path. Intercept the wrapper event
  // before DevToolsExtension handles it so reconnect is graceful instead of a
  // hard reload.
  _installMessageInterceptor();

  /// Initializing the [BlocObserver] created and calling runApp
  debugPrint('[main.dart] Initializing BlocObserver...');
  Bloc.observer = const RohdDevToolsObserver();

  debugPrint('[main.dart] Calling runApp...');
  runApp(const RohdDevToolsApp());
  debugPrint('[main.dart] runApp called successfully');
}

/// Intercepts DevTools wrapper messages before the ExtensionManager
/// can process them.
///
/// Policy note: this extension intentionally owns restart recovery instead of
/// delegating to the default DevTools page reload path.
///
/// Blocks:
///  - `forceReload`  – prevents the full page reload that would destroy local
///    extension state. Instead, the extension disconnects the stale VM service
///    and requests a fresh VM URI from DevTools so state can survive through a
///    controlled reconnect.
void _installMessageInterceptor() {
  web.window.addEventListener(
      'message',
      ((web.MessageEvent e) {
        try {
          final data = e.data.dartify();
          if (data is! Map) {
            return;
          }
          final type = data['type'];

          final source = data['source'] ?? '?';
          debugPrint('[ROHD-MSG] type=$type source=$source '
              'data=${data['data']}');

          if (type == 'forceReload') {
            debugPrint('[ROHD-MSG] BLOCKED forceReload — '
                'triggering graceful reconnection');
            e.stopImmediatePropagation();

            // After blocking the page reload, disconnect the stale VM
            // service and ask DevTools for the current (restarted) URI.
            // A short delay lets the DevTools wrapper finish its own
            // transition before we re-request.
            Future<void>.delayed(const Duration(milliseconds: 300), () async {
              try {
                if (serviceManager.connectedState.value.connected) {
                  debugPrint('[ROHD-MSG] Disconnecting stale VM...');
                  await serviceManager.manuallyDisconnect();
                }
                debugPrint('[ROHD-MSG] Requesting fresh VM URI '
                    'from DevTools...');
                extensionManager.postMessageToDevTools(DevToolsExtensionEvent(
                    DevToolsExtensionEventType.vmServiceConnection));
              } on Object catch (err) {
                debugPrint('[ROHD-MSG] Reconnection request '
                    'failed: $err');
              }
            });
            return;
          }
        } on Object catch (_) {}
      }).toJS);
}

/// The main ROHD DevTools application.
class RohdDevToolsApp extends StatelessWidget {
  /// Creates the main ROHD DevTools application.
  const RohdDevToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[RohdDevToolsApp] Building app widget...');
    return DevToolsExtension(
        // Reset IdeTheme scaling so extension renders at 1× size
        // regardless of the IDE's editor.fontSize setting.
        child: Builder(builder: (context) {
      final current = ideTheme;
      setGlobal(
          IdeTheme,
          IdeTheme(
              backgroundColor: current.backgroundColor,
              foregroundColor: current.foregroundColor,
              embedMode: current.embedMode,
              isDarkMode: current.isDarkMode));

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final base = isDark ? buildDarkTheme() : buildLightTheme();

      return Theme(data: base, child: const RohdDevToolsPage());
    }));
  }
}
