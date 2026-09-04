// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_structure_page.dart
// Page for the tree structure - used by DevTools extension.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide MetaData;
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_shell_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/devtools_dtd_connection.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart'
    hide serviceManager;
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';
import 'package:rohd_schematic_viewer/schematic_viewer.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Page showing the ROHD module tree alongside details, waveform, and
/// schematics.
///
/// This is used by the DevTools extension (embedded in Chrome DevTools).
/// For standalone mode, see `StandaloneDevToolsPage`.
class TreeStructurePage extends StatefulWidget {
  /// Creates the page with the given [screenSize] for layout calculations.
  const TreeStructurePage({
    required this.screenSize,
    void Function({required bool connected})? onConnectionStateChanged,
    super.key,
  }) : _onConnectionStateChanged = onConnectionStateChanged;

  /// Size of the screen used to determine layout constraints.
  final Size screenSize;

  /// Called when the VM connection state changes (connected/disconnected).
  /// Allows parent widgets (e.g. RohdExtensionModule) to track connection
  /// state for the pause/resume button.
  final void Function({required bool connected})? _onConnectionStateChanged;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Size>('screenSize', screenSize));
  }

  @override
  State<TreeStructurePage> createState() => TreeStructurePageState();
}

/// State for [TreeStructurePage].
///
/// Public so that the parent extension module can call
/// `pauseVmConnection` and `resumeVmConnection` via a `GlobalKey`.
class TreeStructurePageState extends State<TreeStructurePage> {
  late final ScrollController _horizontal;
  late final ScrollController _vertical;

  /// Transport layer for VM service RPCs.
  VmServiceTransport? _vmTransport;

  /// Waveform API adapter wrapping [_vmTransport].
  VmServiceSignalWaveformApi? _waveformApi;

  /// Subscription to waveform structure events.
  StreamSubscription<WaveformUpdateEvent>? _waveformStructureSub;

  /// Whether the VM connection is currently paused by the user.
  bool _isPaused = false;

  // ── Cross-probing ──────────────────────────────────────────────────
  final LocalCrossProbeChannel _crossProbeChannel = LocalCrossProbeChannel();
  late final LocalCrossProbeService _waveformXp;
  late final LocalCrossProbeService _schematicXp;
  late final LocalCrossProbeService _shellXp;

  // ── Source navigation (Go to Source via DTD) ──────────────────────
  SourceNavigationService? _sourceNavService;
  FlcExtensionClient? _extensionClient;

  /// DTD-hosted shell bound to the diagnostics-loaded design.
  late final RohdShellDtdService _shellDtdService;

  /// Listener attached to `dtdManager.connection` that forwards the
  /// current DTD connection into the source navigation service.
  /// Needed so the embedded extension can
  /// invoke `rohd.goToSource` once the DevTools host establishes its
  /// DTD connection.
  VoidCallback? _dtdConnectionListener;

  /// Listener that publishes the DevTools-owned shell on the active DTD.
  VoidCallback? _shellDtdConnectionListener;

  String? _lastQueriedModulePath;

  @override
  void initState() {
    super.initState();
    _horizontal = ScrollController();
    _vertical = ScrollController();
    _waveformXp = LocalCrossProbeService(
      _crossProbeChannel,
      source: 'waveform',
    );
    _schematicXp = LocalCrossProbeService(
      _crossProbeChannel,
      source: 'schematic',
    );
    _shellXp = LocalCrossProbeService(
      _crossProbeChannel,
      source: 'rohd-shell',
    );
    _shellDtdService = RohdShellDtdService(crossProbeService: _shellXp);
    _wireDtdToShell();
  }

  @override
  void dispose() {
    if (_dtdConnectionListener != null) {
      devToolsDtdConnection.removeListener(_dtdConnectionListener!);
      _dtdConnectionListener = null;
    }
    if (_shellDtdConnectionListener != null) {
      devToolsDtdConnection.removeListener(_shellDtdConnectionListener!);
      _shellDtdConnectionListener = null;
    }
    unawaited(_waveformStructureSub?.cancel());
    _waveformXp.dispose();
    _schematicXp.dispose();
    _shellXp.dispose();
    _crossProbeChannel.dispose();
    _shellDtdService.clearDesign();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  /// Initialize (or re-initialize) the waveform data source from the
  /// DevTools service manager.
  ///
  /// Called when `RohdServiceCubit` loads a tree successfully, which
  /// proves the DevTools service manager is available.
  ///
  /// [tree] is the loaded hierarchy; it is wrapped into a
  /// `ModuleStructure` and passed to `setExternalStructure` so the
  /// waveform API can build its DFS signal dictionary.
  ///
  /// [rohdIsolateId] is the isolate discovered by the ROHD service cubit's
  /// isolate scan.  If `null`, falls back to DevTools' `mainIsolate`.
  void _initWaveformDataSource(
    HierarchyOccurrence? tree, {
    String? rohdIsolateId,
    Map<String, dynamic>? schematicJson,
  }) {
    final vmService = devToolsVmService;
    if (vmService == null) {
      return;
    }

    // Prefer the explicitly discovered ROHD isolate; fall back to
    // DevTools' mainIsolate (which may be the test runner).
    final isolateId = rohdIsolateId ?? devToolsMainIsolateId;
    if (isolateId == null) {
      return;
    }

    // Tear down previous data source if any (reconnect case).
    unawaited(_waveformStructureSub?.cancel());
    _waveformStructureSub = null;

    _vmTransport = VmServiceTransport(
      vmService: vmService,
      isolateId: isolateId,
    );
    _waveformApi = VmServiceSignalWaveformApi(_vmTransport!)
      ..schematicModules = schematicJson?['modules'] as Map<String, dynamic>?
      ..rootName = tree?.name
      ..fetchModuleSchematic =
          context.read<RohdServiceCubit>().treeService?.fetchModuleSchematic;
    debugPrint(
      '[TreeStructurePage] Created VmServiceSignalWaveformApi'
      ' (schematicModules: ${schematicJson?['modules'] != null})',
    );

    // Provide the hierarchy tree so the waveform API can build its
    // DFS signal dictionary (compact index mapping).
    if (tree != null) {
      final structure = ModuleStructure(
        metadata: const MetaData(
          source: 'TreeDataSource',
          timescale: '1ps',
          date: '',
        ),
        modules: [tree],
      );
      unawaited(_waveformApi!.setExternalStructure(structure));
      debugPrint(
        '[TreeStructurePage] Provided external structure to '
        'waveform API',
      );
    }

    _waveformStructureSub = _vmTransport!.liveUpdates.listen((event) {
      if (event.reason == WaveformUpdateReason.structureAvailable) {
        debugPrint('[TreeStructurePage] Waveform structure available');
      }
    });

    // Notify parent that we're connected
    widget._onConnectionStateChanged?.call(connected: true);

    // Trigger rebuild so WaveformViewerWrapper picks up the new API
    setState(() {});
  }

  /// Pause waveform fetches — the VM connection stays alive and the
  /// simulation timeline continues to advance, but expensive evaluate()
  /// calls for waveform data and signal values are skipped.
  void pauseVmConnection() {
    if (_isPaused) {
      return;
    }

    debugPrint(
      '[TreeStructurePage] Pausing waveform fetches '
      '(connection stays alive)',
    );

    _vmTransport?.pauseFetches();

    setState(() {
      _isPaused = true;
    });
  }

  /// Resume waveform fetches — immediately backfills any data that
  /// accumulated during the paused gap.
  void resumeVmConnection() {
    if (!_isPaused) {
      return;
    }

    debugPrint('[TreeStructurePage] Resuming waveform fetches');

    setState(() {
      _isPaused = false;
    });

    // Resume fetches and backfill gap data.
    if (_vmTransport != null) {
      unawaited(_vmTransport!.resumeFetches());
    }

    debugPrint('[TreeStructurePage] Waveform fetches resumed');
  }

  /// Bridge the DevTools-managed `dtdManager` connection into the
  /// freshly-created source navigation service, pushing the current
  /// DTD connection state and listening for future changes.
  void _wireDtdToSourceNav() {
    if (_sourceNavService == null) {
      return;
    }
    // Push current value, if available.
    final current = devToolsDtdConnection.value;
    if (current != null) {
      _sourceNavService!.setDtd(current);
    } else {
      debugPrint(
        '[TreeStructurePage] DTD not yet connected — '
        'waiting for dtdManager.connection',
      );
    }
    // Subscribe for future changes (replace any prior listener).
    if (_dtdConnectionListener != null) {
      devToolsDtdConnection.removeListener(_dtdConnectionListener!);
    }
    _dtdConnectionListener = () {
      final dtd = devToolsDtdConnection.value;
      if (dtd != null) {
        _sourceNavService?.setDtd(dtd);
        debugPrint(
          '[TreeStructurePage] DTD connection established '
          '— wired into SourceNavigationService',
        );
      } else {
        _sourceNavService?.clearDtd();
      }
    };
    devToolsDtdConnection.addListener(_dtdConnectionListener!);
  }

  /// Publishes the shell independently of optional source navigation setup.
  void _wireDtdToShell() {
    void registerCurrentDtd() {
      final dtd = devToolsDtdConnection.value;
      if (dtd != null) {
        unawaited(_registerShellOnDtd(dtd));
      }
    }

    registerCurrentDtd();
    _shellDtdConnectionListener = registerCurrentDtd;
    devToolsDtdConnection.addListener(_shellDtdConnectionListener!);
  }

  /// Registers the DevTools-owned design shell on the active DTD connection.
  Future<void> _registerShellOnDtd(DartToolingDaemon dtd) async {
    try {
      await _shellDtdService.register(dtd);
      debugPrint(
          '[TreeStructurePage] Registered DTD service rohdDevtoolsShell');
    } on Object catch (error) {
      debugPrint(
        '[TreeStructurePage] DTD service rohdDevtoolsShell '
        'unavailable: $error',
      );
    }
  }

  /// Replaces the shell interpreter with the newly diagnostics-loaded design.
  void _configureShell(
    HierarchyOccurrence tree,
    Map<String, dynamic>? schematicJson,
  ) {
    if (schematicJson == null) {
      _shellDtdService.clearDesign();
      return;
    }
    _shellDtdService.configure(schematicJson, designName: tree.name);
  }

  @override
  Widget build(BuildContext context) =>
      // Keep DevToolsHierarchyCubit in sync with RohdServiceCubit tree loads
      BlocListener<RohdServiceCubit, RohdServiceState>(
        listener: (context, state) {
          final hierarchyCubit = context.read<DevToolsHierarchyCubit>();
          if (state is RohdServiceLoaded && state.treeModel != null) {
            hierarchyCubit.loadFromNode(state.treeModel!);
            // Auto-select root on initial load
            if (hierarchyCubit.selectedModule == null) {
              hierarchyCubit.selectModule(state.treeModel);
            }
            // Initialize waveform data source.
            // Skip if paused — user deliberately disconnected.
            if (!_isPaused) {
              final serviceCubit = context.read<RohdServiceCubit>();
              final rohdIsoId = serviceCubit.rohdIsolateId;
              final schematicJson =
                  serviceCubit.treeService?.getSchematicJson();
              _configureShell(state.treeModel!, schematicJson);
              _initWaveformDataSource(
                state.treeModel,
                rohdIsolateId: rohdIsoId,
                schematicJson: schematicJson,
              );
              // Initialize cross-probe services when tree service is ready.
              final treeService = serviceCubit.treeService;
              if (treeService != null && _sourceNavService == null) {
                final tspFlc = FlcService(
                  fetchModuleFlc: treeService.fetchModuleFlc,
                  fetchFlcHierarchy: treeService.fetchFlcHierarchy,
                  fetchFlcFilePath: treeService.fetchFlcFilePath,
                  onClearCache: treeService.clearFlcCache,
                );
                _sourceNavService = SourceNavigationService()
                  ..sourceLineFetcher = treeService.fetchSourceLine
                  ..setFlcService(tspFlc);
                _wireDtdToSourceNav();
                _extensionClient?.dispose();
                _extensionClient = FlcExtensionClient(flcService: tspFlc);
                _lastQueriedModulePath = null;
                _queryModuleInfoForSelection(hierarchyCubit.selectedModule);
                debugPrint(
                  '[TreeStructurePage] SourceNavigationService created '
                  '(with FlcService fallback)',
                );
              }
            }
          } else if (state is RohdServiceLoading) {
            hierarchyCubit.setLoading();
          } else if (state is RohdServiceError) {
            hierarchyCubit.setError(state.error);
          } else if (state is RohdServiceInitial) {
            // VM disconnected — tear down waveform data source so we
            // don't hold stale references.
            unawaited(_waveformStructureSub?.cancel());
            _waveformStructureSub = null;
            if (_vmTransport != null) {
              unawaited(_vmTransport!.dispose());
              _vmTransport = null;
            }
            _waveformApi = null;
            // Tear down source navigation services.
            if (_dtdConnectionListener != null) {
              devToolsDtdConnection.removeListener(_dtdConnectionListener!);
              _dtdConnectionListener = null;
            }
            _sourceNavService?.clearDtd();
            _sourceNavService?.clearFlcService();
            _sourceNavService = null;
            _extensionClient?.dispose();
            _extensionClient = null;
            _lastQueriedModulePath = null;
            _shellDtdService.clearDesign();
            widget._onConnectionStateChanged?.call(connected: false);
            setState(() {});
          }
        },
        child: BlocListener<DevToolsHierarchyCubit, DevToolsHierarchyState>(
          listenWhen: (previous, current) {
            final previousSelection = previous is HierarchyLoaded
                ? previous.selectedModule?.path()
                : null;
            final currentSelection = current is HierarchyLoaded
                ? current.selectedModule?.path()
                : null;
            return previousSelection != currentSelection;
          },
          listener: (context, state) {
            final selectedModule =
                state is HierarchyLoaded ? state.selectedModule : null;
            _queryModuleInfoForSelection(selectedModule);
          },
          child: DevToolsSplitLayout(
            moduleTreeConfig: ModuleTreePanelConfig(
              icon: platformIcon(Icons.account_tree, '🌳'),
              refreshIcon: platformIcon(Icons.refresh, '🔃', size: 24),
              onRefresh: () =>
                  context.read<RohdServiceCubit>().evalModuleTree(),
              treeContent: _buildTreeContent(context),
              verticalController: _vertical,
              horizontalController: _horizontal,
            ),
            detailsConfig: DetailsPanelConfig(
              content: SourceFramePointerTracker(
                child: DetailsPanelContent(
                  waveformConfig: WaveformTabConfig(
                    waveformViewer: WaveformViewerWrapper(
                      signalWaveformApi: _waveformApi,
                      crossProbeService: _waveformXp,
                      onGoToSource: _sourceNavService != null
                          ? (format, paths) => _goToSource(paths, format)
                          : null,
                      extensionClient: _extensionClient,
                    ),
                  ),
                  schematicConfig: SchematicTabConfig(
                    assetPath: 'rohd_schematic.json',
                    customWidgetBuilder: ({required isVisible}) =>
                        _buildExtensionSchematicViewer(
                      context,
                      isVisible: isVisible,
                    ),
                  ),
                  noModuleSelectedText: 'No module selected',
                  onSendSignals: (paths) {
                    _crossProbeChannel.broadcast(paths, 'details');
                  },
                  onGoToSource: _sourceNavService != null
                      ? (format, paths) => _goToSource(paths, format)
                      : null,
                  availableSourceFormats: () => resolveNavigableFormats(
                    _extensionClient?.currentModuleInfo.value,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void _queryModuleInfoForSelection(HierarchyOccurrence? module) {
    final client = _extensionClient;
    if (client == null || module == null) {
      return;
    }

    final modulePath = module.path();
    if (_lastQueriedModulePath == modulePath) {
      return;
    }
    _lastQueriedModulePath = modulePath;

    final queryName = module.definition ?? modulePath;
    unawaited(
      client.queryModule(queryName, instancePath: modulePath.split('/')),
    );
  }

  Widget _buildTreeContent(BuildContext context) =>
      BlocBuilder<RohdServiceCubit, RohdServiceState>(
        builder: (context, state) {
          if (state is RohdServiceLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is RohdServiceLoaded) {
            final futureModuleTree = state.treeModel;
            if (futureModuleTree == null) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Friendly Notice: Please make sure that you use the '
                        'Module.build() method to fill in this Module Tree, '
                        'and also remember to put your first breakpoint past '
                        'the start of simulation.',
                        style: TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                        softWrap: true,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () =>
                            context.read<RohdServiceCubit>().evalModuleTree(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              return ModuleTreeCard(futureModuleTree: futureModuleTree);
            }
          } else if (state is RohdServiceError) {
            return Center(child: Text('Error: ${state.error}'));
          } else {
            // RohdServiceInitial – no app connected yet.
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Waiting for ROHD application...\n\n'
                      'Start or restart a debug session with a ROHD '
                      'design. The extension will connect automatically.\n\n'
                      'You can also use the Tools menu in the toolbar to '
                      'open the standalone Wave Viewer or Schematic Viewer.',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                      softWrap: true,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.read<RohdServiceCubit>().evalModuleTree(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Connection'),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      );

  /// Resolve signal paths to enriched frames for the requested [format], then
  /// navigate to the first matching frame via the ROHD VS Code extension.
  Future<void> _goToSource(
    List<String> signalPaths,
    RohdSourceFormat format,
  ) async {
    final nav = _sourceNavService;
    if (nav == null) {
      return;
    }

    final enriched = await nav.resolveSourceFrames(signalPaths, format: format);
    if (enriched.isEmpty) {
      debugPrint(
        '[GoToSource] No ${format.name} frames found for signal — '
        '${format.name} source not available',
      );
      return;
    }

    debugPrint(
      '[GoToSource] format=${format.name}, '
      'enriched=${enriched.length} frames, '
      'types=${enriched.map((e) => e.frame.type).toList()}',
    );

    // Filter to the requested format only. When the user explicitly requests a
    // format, never fall back to unrelated source types.
    final filtered =
        enriched.where((e) => e.frame.type == format.name).toList();
    debugPrint('[GoToSource] filtered=${filtered.length} frames');
    if (filtered.isEmpty) {
      debugPrint(
        '[GoToSource] No ${format.name} frames found for signal — '
        '${format.name} source not available',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    final selectedIndex = await showSourceFramePicker(context, filtered);
    if (selectedIndex == null) {
      return;
    }
    await nav.navigateToFormat(filtered, selectedIndex, format);
  }

  /// Builds the schematic viewer for extension mode, using schematic JSON
  /// from [RohdServiceCubit].
  Widget _buildExtensionSchematicViewer(
    BuildContext context, {
    required bool isVisible,
  }) =>
      BlocBuilder<DevToolsHierarchyCubit, DevToolsHierarchyState>(
        builder: (context, hierarchyState) {
          final hierarchyService = hierarchyState is HierarchyLoaded
              ? hierarchyState.hierarchyService
              : null;
          final selectedModule = hierarchyState is HierarchyLoaded
              ? hierarchyState.selectedModule
              : null;

          // Get schematic JSON from the service cubit
          final serviceState = context.watch<RohdServiceCubit>().state;
          final serviceCubit = context.read<RohdServiceCubit>();
          final schematicJson = serviceState is RohdServiceLoaded
              ? serviceCubit.treeService?.getSchematicJson()
              : null;

          return BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
            builder: (context, themeMode) {
              final schematicThemeMode = themeMode == DevToolsThemeMode.dark
                  ? SchematicThemeMode.dark
                  : SchematicThemeMode.light;

              return BlocBuilder<SnapshotCubit, SnapshotState>(
                builder: (context, _) => EmbeddedSchematicViewer(
                  initialThemeMode: schematicThemeMode,
                  externalHierarchy: hierarchyService,
                  netlistJsonMap: schematicJson,
                  selectedModule: selectedModule,
                  isVisible: isVisible,
                  signalValueLookupFn: _buildSignalValueLookup(context),
                  fetchModuleNetlist:
                      serviceCubit.treeService?.fetchModuleSchematic,
                  crossProbeService: _schematicXp,
                  onGoToSourceCallback: _sourceNavService != null
                      ? (format, paths) => _goToSource(paths, format)
                      : null,
                  extensionClient: _extensionClient,
                ),
              );
            },
          );
        },
      );

  /// Build a signal value lookup from the SnapshotCubit, if available.
  static ({String value, bool computed, String signalId})? Function(
    String wireName,
  )? _buildSignalValueLookup(BuildContext context) {
    final snapshotState = context.watch<SnapshotCubit>().state;
    if (snapshotState is! SnapshotLoaded) {
      return null;
    }

    ({String value, bool computed, String signalId}) hit(SignalSnapshot s) =>
        (value: s.value, computed: s.computed, signalId: s.signalId);

    return (String wireName) {
      final exact = snapshotState.getSignal(wireName);
      if (exact != null) {
        return hit(exact);
      }

      final leafName = wireName.contains('/')
          ? wireName.substring(wireName.lastIndexOf('/') + 1)
          : wireName;
      final byName = snapshotState.getSignalByName(leafName);
      if (byName != null) {
        return hit(byName);
      }

      return null;
    };
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Size>('screenSize', widget.screenSize));
  }
}
