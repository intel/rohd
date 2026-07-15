// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// standalone_app_shell.dart
// Minimal standalone shell for early startup/connection porting.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/const/app_theme.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/dtd_vm_service_info.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/connection_state_machine.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/view/tree_structure_page.dart';

/// Configuration for the standalone ROHD DevTools app shell.
class StandaloneAppConfig {
  /// Title shown in AppBar.
  final String title;

  /// Strategy for connecting to VM service.
  final VmConnectionStrategy? connectionStrategy;

  /// Constructor for [StandaloneAppConfig].
  const StandaloneAppConfig({
    this.title = 'ROHD DevTools (Standalone)',
    this.connectionStrategy,
  });
}

/// Standalone app entry point that wires up theming and the app shell.
class StandaloneRohdDevToolsApp extends StatelessWidget {
  /// Configuration used by the standalone app shell.
  final StandaloneAppConfig config;

  /// Creates the standalone ROHD DevTools app.
  const StandaloneRohdDevToolsApp({
    super.key,
    this.config = const StandaloneAppConfig(),
  });

  @override

  /// Builds the top-level app and injects theme state.
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => DevToolsThemeCubit(),
        child: BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
          builder: (context, themeMode) {
            final isDark = themeMode == DevToolsThemeMode.dark;

            return MaterialApp(
              title: config.title,
              debugShowCheckedModeBanner: false,
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              darkTheme: buildDarkTheme(),
              theme: buildLightTheme(),
              home: StandaloneDevToolsPage(config: config),
            );
          },
        ),
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<StandaloneAppConfig>('config', config));
  }
}

/// The main standalone page that manages connections and content.
class StandaloneDevToolsPage extends StatefulWidget {
  /// Configuration for the standalone page.
  final StandaloneAppConfig config;

  /// Creates the standalone DevTools page.
  const StandaloneDevToolsPage({required this.config, super.key});

  @override

  /// Creates the mutable state for [StandaloneDevToolsPage].
  State<StandaloneDevToolsPage> createState() => _StandaloneDevToolsPageState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<StandaloneAppConfig>('config', config));
  }
}

class _StandaloneDevToolsPageState
    extends DevToolsConnectionHostState<StandaloneDevToolsPage> {
  late final RohdServiceCubit _rohdServiceCubit = RohdServiceCubit(
    manageServiceManager: false,
  );
  late final SnapshotCubit _snapshotCubit = SnapshotCubit();
  late final TreeSearchTermCubit _treeSearchTermCubit = TreeSearchTermCubit();
  late final SelectedModuleCubit _selectedModuleCubit = SelectedModuleCubit();
  late final SignalSearchTermCubit _signalSearchTermCubit =
      SignalSearchTermCubit();

  @override

  /// Returns the connection strategy requested by the widget config.
  VmConnectionStrategy? get connectionStrategy =>
      widget.config.connectionStrategy;

  @override

  /// Initializes the connection dialog and supporting listeners.
  void initState() {
    super.initState();
    // Auto-pop the connection dialog after the first frame, once
    // fonts have settled on web (so glyphs render correctly).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !isConnected) {
        unawaited(_showConnectionDialogWhenReady());
      }
    });
  }

  /// Wait for icon fonts to load on web before showing the dialog so
  /// the form's glyphs (e.g. dropdown chevrons) render on the first
  /// frame instead of as boxes.  No-op on native platforms.
  Future<void> _showConnectionDialogWhenReady() async {
    if (kIsWeb) {
      final completer = Completer<void>();
      void onFontsChanged() {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      PaintingBinding.instance.systemFonts.addListener(onFontsChanged);
      await completer.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {},
      );
      PaintingBinding.instance.systemFonts.removeListener(onFontsChanged);

      // Give CanvasKit one extra frame to rasterise the glyphs.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    if (!mounted || isConnected) {
      return;
    }
    await showConnectionDialog();
  }

  @override

  /// Handles a successful VM connection by configuring the ROHD service.
  Future<void> onVmConnected(VmConnectionResult result, String uri) async {
    await _rohdServiceCubit.configureStandaloneVmService(
      result.vmService,
      result.isolateId,
    );
    await _loadHierarchyFromVm();
  }

  @override
  Future<void> onCsmLoadHierarchy() => _loadHierarchyFromVm();

  @override

  /// Clears the standalone tree service when the connection is torn down.
  Future<void> tearDownOldConnection({
    required VmConnectionTransition transition,
  }) async {
    _rohdServiceCubit.treeService = null;
  }

  @override

  /// Reopens the connection dialog after the VM disconnects.
  void onVmDisconnected() {
    // Re-pop the connection dialog so the user can reconnect.
    if (mounted) {
      unawaited(showConnectionDialog());
    }
  }

  @override

  /// Reconfigures the ROHD service after a lightweight reconnect.
  Future<void> onLightweightReconnectSuccess(
    VmConnectionResult result,
    String uri,
  ) async {
    await _rohdServiceCubit.configureStandaloneVmService(
      result.vmService,
      result.isolateId,
    );
    await _loadHierarchyFromVm();
  }

  Future<void> _loadHierarchyFromVm() async {
    await _rohdServiceCubit.evalModuleTree();

    final state = _rohdServiceCubit.state;
    final success = switch (state) {
      RohdServiceLoaded(treeModel: _) => true,
      _ => false,
    };

    connectionStateMachine.handleEvent(HierarchyLoadResult(success: success));
  }

  @override

  /// Releases cubits used by the standalone shell.
  void dispose() {
    unawaited(_rohdServiceCubit.close());
    unawaited(_snapshotCubit.close());
    unawaited(_treeSearchTermCubit.close());
    unawaited(_selectedModuleCubit.close());
    unawaited(_signalSearchTermCubit.close());
    super.dispose();
  }

  void _openConnectionDialog() => unawaited(showConnectionDialog());

  void _disconnect() => unawaited(disconnect());

  /// Override the base dialog content to wire dismiss-on-success and
  /// the standalone shell's discovered-services memory.
  @override

  /// Builds the standalone connection dialog content.
  Widget buildConnectionDialogContent(BuildContext dialogContext) =>
      VmConnectionForm(
        vmServiceUriController: vmServiceUriController,
        dtdUriController: dtdUriController,
        connectionError: connectionError,
        onConnect: () async {
          try {
            await attemptConnection();
            if (mounted && dialogContext.mounted && isConnected) {
              Navigator.of(dialogContext).pop();
            }
          } on Exception catch (e) {
            setState(() {
              connectionError = 'Connection failed: $e';
            });
          }
        },
        cleanVmServiceUri: DevToolsConnectionHostState.cleanVmServiceUri,
        cleanDtdUri: DevToolsConnectionHostState.cleanDtdUri,
        discoverVmServices: discoverVmServices,
        hasColorEmoji: true,
        initialDiscoveredServices: rememberedServices
            ?.map(
              (s) => DiscoveredVmService(
                name: s.name,
                uri: s.uri,
                exposedUri: s.exposedUri,
                isAlive: s.isAlive,
                autoReconnect: s.autoReconnect,
              ),
            )
            .toList(),
        onServicesDiscovered: (services) {
          rememberedServices = services
              .map(
                (s) => DtdVmServiceInfo.fromFields(
                  name: s.name,
                  uri: s.uri,
                  exposedUri: s.exposedUri,
                  isAlive: s.isAlive,
                  autoReconnect: s.autoReconnect,
                ),
              )
              .toList();
        },
      );

  /// Builds the empty state shown before any connection is established.
  Widget _buildEmptyConnectionState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cable_outlined,
            size: 72,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          const Text(
            'Not connected',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to a running ROHD application to begin.',
            style: TextStyle(color: secondaryTextColor),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Connect…'),
            onPressed: () => unawaited(showConnectionDialog()),
          ),
        ],
      ),
    );
  }

  @override

  /// Builds the standalone shell, switching between connected and empty UI.
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.title),
        actions: [
          if (isConnected) ...[
            IconButton(
              tooltip: 'Disconnect',
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off),
            ),
          ] else
            IconButton(
              tooltip: 'Connect…',
              onPressed: _openConnectionDialog,
              icon: const Icon(Icons.link),
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
                  hasColorEmoji: kIsWeb,
                ),
              );
            },
          ),
          DevToolsHelpButton(isDark: isDark),
        ],
      ),
      body: !isConnected
          ? _buildEmptyConnectionState()
          : MultiBlocProvider(
              providers: [
                BlocProvider.value(value: _rohdServiceCubit),
                BlocProvider.value(value: _snapshotCubit),
                BlocProvider.value(value: _treeSearchTermCubit),
                BlocProvider.value(value: _selectedModuleCubit),
                BlocProvider.value(value: _signalSearchTermCubit),
                BlocProvider(create: (context) => DetailsTabCubit()),
              ],
              child: TreeStructurePage(screenSize: MediaQuery.of(context).size),
            ),
    );
  }
}
