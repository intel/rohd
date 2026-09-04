// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_page.dart
// Page view for the app.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';

/// The main ROHD DevTools page with all necessary BlocProviders.
class RohdDevToolsPage extends StatelessWidget {
  /// Whether the page-owned service cubit manages the global service manager.
  final bool _manageServiceManager;

  /// Creates the ROHD DevTools page.
  const RohdDevToolsPage({
    super.key,
    bool manageServiceManager = true,
  }) : _manageServiceManager = manageServiceManager;

  @override
  Widget build(BuildContext context) {
    debugPrint('[RohdDevToolsPage] Building page with BlocProviders...');
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) {
            debugPrint('[RohdDevToolsPage] Creating DevToolsThemeCubit...');
            return DevToolsThemeCubit();
          },
        ),
        BlocProvider(
          create: (context) {
            debugPrint('[RohdDevToolsPage] Creating RohdServiceCubit...');
            final cubit = RohdServiceCubit(
              manageServiceManager: _manageServiceManager,
            );
            debugPrint('[RohdDevToolsPage] RohdServiceCubit created');
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            debugPrint('[RohdDevToolsPage] Creating TreeSearchTermCubit...');
            final cubit = TreeSearchTermCubit();
            debugPrint('[RohdDevToolsPage] TreeSearchTermCubit created');
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            debugPrint('[RohdDevToolsPage] Creating DevToolsHierarchyCubit...');
            final cubit = DevToolsHierarchyCubit();
            debugPrint('[RohdDevToolsPage] DevToolsHierarchyCubit created');
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            debugPrint('[RohdDevToolsPage] Creating SignalSearchTermCubit...');
            final cubit = SignalSearchTermCubit();
            debugPrint('[RohdDevToolsPage] SignalSearchTermCubit created');
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            debugPrint('[RohdDevToolsPage] Creating DetailsTabCubit...');
            final cubit = DetailsTabCubit();
            debugPrint('[RohdDevToolsPage] DetailsTabCubit created');
            return cubit;
          },
        ),
        BlocProvider(
          create: (context) {
            debugPrint('[RohdDevToolsPage] Creating SnapshotCubit...');
            return SnapshotCubit();
          },
        ),
      ],
      child: const RohdExtensionModule(),
    );
  }
}

/// The main ROHD DevTools module widget.
class RohdExtensionModule extends StatefulWidget {
  /// Creates the ROHD DevTools module.
  const RohdExtensionModule({super.key});

  @override
  State<RohdExtensionModule> createState() => _RohdExtensionModuleState();
}

class _RohdExtensionModuleState extends State<RohdExtensionModule> {
  /// Whether the VM connection is paused (debug events disconnected,
  /// UI state preserved).
  bool _isPaused = false;

  /// Whether the VM connection is live.
  bool _isConnected = false;

  /// Key for the [TreeStructurePage] so we can call pause/resume on it.
  final _treePageKey = GlobalKey<TreeStructurePageState>();

  @override
  void initState() {
    super.initState();
    debugPrint('[RohdExtensionModule] initState called');
  }

  void _onPauseResume() {
    final treeState = _treePageKey.currentState;
    if (treeState == null) {
      return;
    }

    if (_isPaused) {
      debugPrint('[RohdExtensionModule] Resuming waveform fetches');
      treeState.resumeVmConnection();
      setState(() {
        _isPaused = false;
      });
    } else {
      debugPrint('[RohdExtensionModule] Pausing waveform fetches');
      treeState.pauseVmConnection();
      setState(() {
        _isPaused = true;
      });
    }
  }

  /// Called by [TreeStructurePage] when its connection state changes.
  void _onConnectionStateChanged({required bool connected}) {
    if (mounted && _isConnected != connected) {
      setState(() => _isConnected = connected);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[RohdExtensionModule] Building scaffold...');
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      appBar: DevtoolAppBar(
        isPaused: _isPaused,
        onPauseResume: (_isConnected || _isPaused) ? _onPauseResume : null,
      ),
      body: TreeStructurePage(
        key: _treePageKey,
        screenSize: screenSize,
        onConnectionStateChanged: _onConnectionStateChanged,
      ),
    );
  }
}
