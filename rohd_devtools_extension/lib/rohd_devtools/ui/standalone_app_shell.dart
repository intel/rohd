// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// standalone_app_shell.dart
// Shared app shell for standalone (Linux and Web) entry points.
// This contains common UI and state management code.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';

import 'package:dart_wellen/dart_wellen.dart';
import 'package:dtd/dtd.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide MetaData;
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/const/app_theme.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/examples/rohd_examples.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/dtd_vm_service_info.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/third_party_license_registry.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';
import 'package:rohd_schematic_viewer/schematic_viewer.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:vm_service/vm_service.dart' hide Stack;

/// Configuration for the standalone app.
class StandaloneAppConfig {
  /// Title shown in AppBar.
  final String title;

  /// Path prefix for assets (e.g., 'assets/' on Linux, '' on web).
  final String assetPathPrefix;

  /// Strategy for connecting to VM service.
  final VmConnectionStrategy? connectionStrategy;

  /// Default example index to start with.
  final int defaultExampleIndex;

  /// Constructor for [StandaloneAppConfig].
  const StandaloneAppConfig({
    this.title = 'ROHD DevTools (Standalone)',
    this.assetPathPrefix = '',
    this.connectionStrategy,
    this.defaultExampleIndex = 0, // Counter (first in-process example)
  });
}

/// Shared standalone app widget.
class StandaloneRohdDevToolsApp extends StatelessWidget {
  /// Configuration for the standalone app.
  final StandaloneAppConfig config;

  /// Constructor for [StandaloneRohdDevToolsApp].
  const StandaloneRohdDevToolsApp({
    super.key,
    this.config = const StandaloneAppConfig(),
  });

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => DevToolsThemeCubit(),
        child: BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
          builder: (context, themeMode) {
            final isDark = themeMode == DevToolsThemeMode.dark;
            return MaterialApp(
              title: 'ROHD DevTools',
              debugShowCheckedModeBanner: false,
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              darkTheme: buildDarkTheme(),
              theme: buildLightTheme(),
              builder: (context, child) => Stack(
                children: [
                  child!,
                  // Pre-warm icon and emoji fonts by painting them invisibly
                  // on the first frame. Opacity(0) still paints (unlike
                  // Offstage), forcing Skia to load and cache the glyphs
                  // before the connection form appears.
                  const Positioned(
                    left: -9999,
                    child: Opacity(
                      opacity: 0,
                      child: Row(
                        children: [
                          Icon(Icons.developer_board, size: 1),
                          Icon(Icons.cloud, size: 1),
                          Icon(Icons.link, size: 1),
                          Icon(Icons.build, size: 1),
                          Icon(Icons.folder_open, size: 1),
                          Icon(Icons.show_chart, size: 1),
                          Text('🔧☁️🔌🔗📂🛠️', style: TextStyle(fontSize: 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              home: StandaloneDevToolsPage(config: config),
            );
          },
        ),
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      ObjectFlagProperty<StandaloneAppConfig>(
        'config',
        config,
        ifNull: 'default',
      ),
    );
  }
}

/// Main DevTools page - shows full UI immediately with mock data.
class StandaloneDevToolsPage extends StatefulWidget {
  /// Configuration for the standalone app.
  final StandaloneAppConfig config;

  /// Constructor for [StandaloneDevToolsPage].
  const StandaloneDevToolsPage({required this.config, super.key});

  @override
  State<StandaloneDevToolsPage> createState() => _StandaloneDevToolsPageState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      ObjectFlagProperty<StandaloneAppConfig>('config', config, ifNull: 'none'),
    );
  }
}

class _StandaloneDevToolsPageState
    extends DevToolsConnectionHostState<StandaloneDevToolsPage> {
  // Connection state - starts as not connected (shows connection page first)
  bool _isConnected = false;

  // True while the VM connection handshake is in progress.
  // Set immediately so the main UI composites (with a loading indicator)
  // without waiting for the WebSocket + isolate search to complete.
  bool _isConnecting = false;

  // True when the VM service has been detected as dead (polling failed).
  // The UI stays on the main page but the AppBar badge turns red.
  // The user can hit Refresh to reload design data without reconnecting.
  bool _isVmDead = false;

  // True when the user deliberately disconnected from the VM via the
  // plug/pause button.  The main UI stays visible (tree, schematic,
  // waveforms are preserved) but the VM service is torn down to reduce
  // load on the ROHD program.  Clicking the icon again reconnects.
  bool _isPaused = false;

  // The VM service URI that was active before pausing, so we can
  // reconnect to the same VM.
  String? _lastVmServiceUri;

  // The isolate ID from the last successful connection.  Used during
  // reconnect to detect whether the same VM process is still running
  // (same ID → lightweight reconnect) or a fresh process started at
  // the same URI (different ID → full reconnect).
  String? _lastIsolateId;

  // The name of the VM we connected to (from DiscoveredVmService.name).
  // Used for auto-reconnect: after a VM death we re-discover via DTD and
  // try to find a newly spawned VM with the same name.
  String? _connectedVmName;

  // Whether automatic reconnection by name is enabled for the current
  // session.  Set when the user connects to a VM that has
  // [DiscoveredVmService.autoReconnect] checked.
  bool _autoReconnect = false;

  // Tree model - starts with loopback data
  TreeModel? _treeModel;

  /// The schematic JSON extracted from the ROHD WaveformService.
  Map<String, dynamic>? _schematicJson;

  /// Signal paths whose modules are currently being expanded (fetching full
  /// connectivity from the server).  Prevents duplicate fetch requests.
  final Set<String> _pendingModuleExpansions = {};

  String? _error;

  /// Whether color emoji fonts are available on this system.
  /// Web always uses emoji; native starts optimistically and verifies.
  late bool _hasColorEmoji;

  // Data source abstraction - starts with loopback mode
  TreeDataSource? _dataSource;
  late int _selectedExampleIndex;

  // Whether a user-supplied design JSON has been loaded in loopback mode.
  // When true, the "Load Waveform" button is shown.
  bool _hasLoadedDesign = false;

  // Human-readable name of the loaded design (e.g. file name).
  String? _loadedDesignName;

  /// In-process transport for real ROHD examples.
  late InProcessTransport _inProcessTransport;

  /// In-process waveform data source for real ROHD examples (legacy).
  InProcessWaveformDataSource? _inProcessWaveformDataSource;

  /// Completer that keeps the in-process ROHD example alive.
  /// Complete it to shut down the example (when switching or disconnecting).
  Completer<void>? _exampleKeepAlive;
  late VmServiceTransport _vmTransport;
  SignalWaveformApi? _waveformApi;

  // Monotonically increasing counter bumped on every full reconnect.
  // Used in the WaveformViewerWrapper key so Flutter recreates the widget
  // (and its repository / BLoC state) instead of reusing stale data.
  int _connectionGeneration = 0;

  // Monitored signal hierarchy paths saved before a full reconnect.
  // After the new hierarchy loads and SignalBloc is recreated, these
  // paths are passed to SignalBloc so it can attempt to re-add each
  // signal to the monitor list.  Cleared after being handed off.
  List<String> _savedMonitoredSignalPaths = [];

  // Cubits - created once in initState to prevent recreation on rebuilds
  late final TreeSearchTermCubit _treeSearchTermCubit;
  late final SignalSearchTermCubit _signalSearchTermCubit;
  late final DetailsTabCubit _detailsTabCubit;
  late final DevToolsHierarchyCubit _hierarchyCubit;
  late final SnapshotCubit _snapshotCubit;

  /// Cross-call cache for [evaluateSignalOnDemand].  Cleared on snapshot
  /// changes; reset on hierarchy reload.
  final _evalCache = EvalOnDemandCache();
  int? _evalCacheSnapshotTime;

  /// Shared [NetlistEvaluator] instance.
  ///
  /// Created lazily from [_schematicJson] and [_treeModel].  Invalidated
  /// when either changes (hierarchy reload, new connection, etc.).
  /// Used by details-pane, schematic-hover, and waveform-synthesis.
  NetlistEvaluator? _sharedEvaluator;

  /// Get or create the shared [NetlistEvaluator].
  NetlistEvaluator? _getSharedEvaluator() {
    if (_sharedEvaluator != null) {
      return _sharedEvaluator;
    }
    final modules = _schematicJson?['modules'] as Map<String, dynamic>?;
    if (modules == null) {
      return null;
    }
    _sharedEvaluator = NetlistEvaluator(modules, _evalCache);
    debugPrint('[Shell] Created shared NetlistEvaluator');
    return _sharedEvaluator;
  }

  /// Shared cross-probe channel and per-viewer services.
  final LocalCrossProbeChannel _crossProbeChannel = LocalCrossProbeChannel();
  late final LocalCrossProbeService _waveformXp;
  late final LocalCrossProbeService _schematicXp;
  late final LocalCrossProbeService _shellXp;

  // ── Source navigation (Go to Source via DTD) ──────────────────────
  SourceNavigationService? _sourceNavService;

  /// Extension client — exposes what source formats are available per module.
  /// Created alongside [_sourceNavService] using the same [FlcService].
  FlcExtensionClient? _extensionClient;

  /// The current FlcService backing [_extensionClient], kept for DTD
  /// queryModule refresh (file-existence sanity check).
  FlcService? _currentFlcService;

  // ValueNotifier for snapshot availability — survives Navigator
  // route caching and updates the wave viewer's snapshot button
  // reactively via ValueListenableBuilder.
  final ValueNotifier<bool> _canSnapshotNotifier = ValueNotifier<bool>(false);

  // Cached dropdown items to prevent recreation on rebuild
  late final List<DropdownMenuItem<int>> _exampleDropdownItems;

  // Cached callbacks to prevent recreation on rebuild
  late final ValueChanged<int?> _onExampleChanged;
  late final VoidCallback _onDisconnect;
  late final VoidCallback _onConnect;
  late final VoidCallback _onPauseVm;
  late final VoidCallback _onResumeVm;
  late final VoidCallback _onRefresh;
  late final VoidCallback _onLicenses;
  late final VoidCallback _onLoadDesign;
  late final VoidCallback _onLoadWaveform;

  // Cached AppBar widget - only recreated when state actually changes
  _StandaloneAppBar? _cachedAppBar;
  bool _lastIsLoopbackMode = false;
  bool _lastIsVmConnected = false;
  bool _lastIsConnecting = false;
  bool _lastIsVmDead = false;
  bool _lastIsPaused = false;
  int _lastSelectedExampleIndex = 1;
  bool _lastHasColorEmoji = false;
  bool _lastHasLoadedDesign = false;

  // VM service reference (for disposal)
  VmService? _vmService;

  // VM liveness polling timer — cancels on disconnect or dispose
  Timer? _vmLivenessTimer;

  // Remembered VM services across reconnects (includes dead ones)
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  VmConnectionStrategy? get connectionStrategy =>
      widget.config.connectionStrategy;

  @override
  Future<void> onCsmLoadHierarchy() => _loadModuleTree();

  @override
  Future<void> onBeforeVmConnected(
    VmConnectionResult result,
    String uri, {
    required VmConnectionTransition transition,
  }) async {
    _handleBeforeVmConnected(result, uri, transition: transition);
  }

  @override
  Future<void> onVmConnected(VmConnectionResult result, String uri) async {
    debugPrint('[Connection] Creating VmServiceTreeDataSource...');
    final vmDataSource = VmServiceTreeDataSource(
      vmService: result.vmService,
      isolateId: result.isolateId,
    );

    _initVmWaveformDataSource(result.vmService, result.isolateId);
    _handleConnectedVmState(result, uri, vmDataSource);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadModuleTree());
    });
    debugPrint('[Connection] Deferred _loadModuleTree to next frame');
  }

  @override
  Widget buildConnectionDialogContent(BuildContext dialogContext) =>
      VmConnectionForm(
        vmServiceUriController: vmServiceUriController,
        dtdUriController: dtdUriController,
        connectionError: connectionError,
        onConnect: () async {
          try {
            await attemptConnection();
            if (mounted && dialogContext.mounted && _isConnected) {
              Navigator.of(dialogContext).pop();
            }
          } on Exception catch (e) {
            setState(() {
              connectionError = 'Connection failed: $e';
            });
          }
        },
        onDemoMode: () {
          Navigator.of(dialogContext).pop();
          onDemoModeRequested();
        },
        showDemoButton: true,
        hasColorEmoji: _hasColorEmoji,
        cleanVmServiceUri: DevToolsConnectionHostState.cleanVmServiceUri,
        cleanDtdUri: DevToolsConnectionHostState.cleanDtdUri,
        discoverVmServices: discoverVmServices,
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

  @override
  void onDemoModeRequested() {
    unawaited(_enterDemoMode());
  }

  @override
  Future<void> tearDownOldConnection({
    required VmConnectionTransition transition,
  }) =>
      _tearDownOldConnection(transition);

  @override
  void onVmDisconnected() {
    _handleExplicitDisconnect();
  }

  @override
  Future<void> onVmPaused() async {
    debugPrint('[Pause] Pausing waveform fetches (connection stays alive)');
    _handlePausedVm();
    setState(() {
      _isPaused = true;
    });
    debugPrint(
      '[Pause] Fetches paused — VM still connected at '
      '$_lastVmServiceUri',
    );
  }

  @override
  Future<void> onVmResumed() async {
    debugPrint('[Resume] Resuming waveform fetches');
    setState(() {
      _isPaused = false;
    });
    await _handleResumedVm();
    debugPrint('[Resume] Fetches resumed — gap data backfilled');
  }

  @override
  Future<void> onLightweightReconnectSuccess(
    VmConnectionResult result,
    String uri,
  ) async {
    final newDataSource = await _handleLightweightReconnectSuccess(result);
    setState(() {
      _vmService = result.vmService;
      _dataSource = newDataSource;
      _isConnecting = false;
      _isPaused = false;
      _isVmDead = false;
      _lastIsolateId = result.isolateId;
    });
  }

  @override
  void onVmDead() {
    setState(() {
      _isVmDead = true;
    });
  }

  @override
  void onVmRecovered() {
    setState(() {
      _isVmDead = false;
    });
  }

  @override
  void onDtdConnected(DartToolingDaemon dtd) {
    _handleDtdConnected(dtd);
    unawaited(_registerCrossProbeOnDtd(dtd));
    unawaited(_registerSignalFormatOnDtd(dtd));
  }

  @override
  void onDtdDisconnected() {
    _handleDtdDisconnected();
  }

  Future<void> _registerCrossProbeOnDtd(DartToolingDaemon dtd) async {
    try {
      final services = await dtd.getRegisteredServices();
      final registered = services.clientServices.any(
        (service) =>
            service.name == rohdCrossProbeDtdServiceName &&
            service.methods.containsKey(rohdCrossProbeSendDtdMethod),
      );
      if (registered) {
        return;
      }
      await dtd.registerService(
        rohdCrossProbeDtdServiceName,
        rohdCrossProbeSendDtdMethod,
        (parameters) async {
          final paths = jsonDecode(parameters['paths'].asString);
          if (paths is! List || !paths.every((path) => path is String)) {
            throw const FormatException('paths must be a list of strings.');
          }
          _shellXp.send(paths.cast<String>(), source: 'rohd-shell-cli');
          return const {'type': 'RohdCrossProbeResponse', 'ok': true};
        },
      );
    } on Object catch (error) {
      debugPrint('[CrossProbe] DTD service unavailable: $error');
    }
  }

  Future<void> _registerSignalFormatOnDtd(DartToolingDaemon dtd) async {
    try {
      final services = await dtd.getRegisteredServices();
      final registered = services.clientServices.any(
        (service) =>
            service.name == rohdSignalFormatDtdServiceName &&
            service.methods.containsKey(rohdSignalFormatGetDtdMethod),
      );
      if (registered) {
        return;
      }
      await dtd.registerService(
        rohdSignalFormatDtdServiceName,
        rohdSignalFormatGetDtdMethod,
        (parameters) async {
          final path = parameters['path'].asString;
          final hierarchyState = _hierarchyCubit.state;
          final address = hierarchyState is HierarchyLoaded
              ? hierarchyState.hierarchyService?.pathnameToAddress(path)
              : null;
          return {
            'type': 'RohdSignalFormatResponse',
            'format': SignalValueFormatRegistry.formatToString(
              SignalValueFormatRegistry.formatForAny([address]),
            ),
          };
        },
      );
    } on Object catch (error) {
      debugPrint('[SignalFormat] DTD service unavailable: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedExampleIndex = widget.config.defaultExampleIndex.clamp(
      0,
      rohdExamples.length - 1,
    );

    // Detect color emoji font availability
    // Assume emoji is available (optimistic) to avoid icon flash on startup.
    // The async check will flip to false if no color emoji font is found.
    _hasColorEmoji = true;
    if (!kIsWeb) {
      unawaited(_detectEmojiFont());
    }

    // Create cubits once - use BlocProvider.value() in build to avoid
    // recreation
    _treeSearchTermCubit = TreeSearchTermCubit();
    _signalSearchTermCubit = SignalSearchTermCubit();
    _detailsTabCubit = DetailsTabCubit();
    _hierarchyCubit = DevToolsHierarchyCubit();
    _snapshotCubit = SnapshotCubit();

    // Cache dropdown items to prevent recreation on rebuild
    _exampleDropdownItems = _buildExampleDropdownItems();

    // Cache callbacks to prevent recreation on rebuild
    _onExampleChanged = (index) {
      if (index != null) {
        unawaited(_switchExample(index));
      }
    };
    _onDisconnect = () => unawaited(disconnect());
    _onConnect = () => unawaited(showConnectionDialog());
    _onPauseVm = () => unawaited(pauseVm());
    _onResumeVm = () => unawaited(resumeVm());
    _onRefresh = () => unawaited(_fullRefresh());
    _onLicenses = _showLicenses;
    _onLoadDesign = () => unawaited(_loadDesignFromFile());
    _onLoadWaveform = () => unawaited(_loadWaveformFromFile());

    // Note: We don't initialize loopback mode here anymore.
    // The main UI is shown immediately with empty panels, and the
    // connection dialog opens automatically so the user can connect
    // to a VM or choose "Demo mode" to enter loopback mode.

    // Cross-probing: create per-viewer services on the shared channel.
    _waveformXp = LocalCrossProbeService(
      _crossProbeChannel,
      source: 'waveform',
    );
    _schematicXp = LocalCrossProbeService(
      _crossProbeChannel,
      source: 'schematic',
    );
    _shellXp = LocalCrossProbeService(_crossProbeChannel, source: 'rohd-shell');

    // Show the connection dialog once fonts are loaded so icon glyphs
    // render correctly on the first frame of the dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isConnected) {
        unawaited(_showConnectionDialogWhenReady());
      }
    });
  }

  /// Build dropdown items from [rohdExamples].
  List<DropdownMenuItem<int>> _buildExampleDropdownItems() =>
      rohdExamples.asMap().entries.map((entry) {
        final index = entry.key;
        final example = entry.value;
        return DropdownMenuItem<int>(value: index, child: Text(example.name));
      }).toList();

  /// Default signals to pre-load in the waveform monitor for each example.
  /// These are discovered dynamically from the real ROHD module hierarchy,
  /// so we start with an empty list and let the tree load populate them.
  static List<String> _defaultMonitoredSignals(int exampleIndex) => [];

  /// Initialize loopback mode with the selected example.
  ///
  /// Launches a real ROHD simulation in-process, then creates
  /// in-process tree and waveform data sources that call ROHD services
  /// directly.
  Future<void> _initLoopbackMode() async {
    final examples = rohdExamples;
    if (_selectedExampleIndex >= examples.length) {
      debugPrint('[Shell] Invalid example index: $_selectedExampleIndex');
      return;
    }

    final example = examples[_selectedExampleIndex];
    debugPrint('[Shell] Launching in-process example: ${example.name}');

    // Shut down any previous in-process example.
    _shutdownInProcessExample();

    // Launch the ROHD simulation.  This builds the module, runs simulation,
    // and returns a Completer we can complete to shut it down.
    try {
      _exampleKeepAlive = await example.launcher();
    } on Exception catch (e) {
      debugPrint('[Shell] Example launch failed: $e');
      setState(() {
        _error = 'Failed to launch example: $e';
      });
      return;
    }

    // Create data sources that call the ROHD singletons directly.
    final inProcessDataSource = InProcessTreeDataSource(name: example.name);
    _dataSource = inProcessDataSource;
    _inProcessTransport = InProcessTransport(name: example.name);
    _inProcessWaveformDataSource = InProcessWaveformDataSource(
      name: example.name,
    );
    _waveformApi = LoopbackSignalWaveformApi(_inProcessTransport)
      ..evalCache = _evalCache;

    // Initialize cross-probe source navigation with in-process FlcService.
    // This proxies the ROHD extension's DTD services locally — the lookup
    // calls ModuleServices directly instead of going over DTD.
    final loopbackFlc = FlcService(
      fetchModuleFlc: inProcessDataSource.fetchModuleFlc,
      fetchFlcHierarchy: inProcessDataSource.fetchFlcHierarchy,
      fetchFlcFilePath: inProcessDataSource.fetchFlcFilePath,
      onClearCache: inProcessDataSource.clearFlcCache,
    );
    _sourceNavService = SourceNavigationService()..setFlcService(loopbackFlc);
    _extensionClient?.dispose();
    _extensionClient = FlcExtensionClient(flcService: loopbackFlc);
    _currentFlcService = loopbackFlc;
    debugPrint('[Shell] SourceNavigationService created (loopback mode)');

    // Pre-load default signals for this example.
    _savedMonitoredSignalPaths = _defaultMonitoredSignals(
      _selectedExampleIndex,
    );

    // Defer tree loading until after the UI frame renders.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadModuleTree());
    });
  }

  /// Shut down a running in-process ROHD example.
  void _shutdownInProcessExample() {
    if (_exampleKeepAlive != null && !_exampleKeepAlive!.isCompleted) {
      _exampleKeepAlive!.complete();
      debugPrint('[Shell] Completed in-process example keep-alive');
    }
    _exampleKeepAlive = null;
    _inProcessWaveformDataSource = null;
    // Tear down loopback source navigation.
    _sourceNavService?.clearFlcService();
    _sourceNavService = null;
    _extensionClient?.dispose();
    _extensionClient = null;
    _currentFlcService = null;
  }

  /// Tear down all state from a previous VM connection.
  ///
  /// Disposes the old waveform data source, cancels subscriptions,
  /// clears stale tree/schematic/hierarchy/snapshot data, and bumps
  /// the connection generation so the WaveformViewerWrapper is fully
  /// recreated.  Safe to call even when no prior connection exists
  /// (e.g. the very first connect).
  Future<void> _tearDownOldConnection(VmConnectionTransition transition) async {
    // Each step is individually guarded so that a failure in one step
    // (e.g. LateInitializationError on first connect) never prevents
    // subsequent steps from executing.  Without this resilience, a
    // single error can leave stale cubits, metadata, and widget keys
    // intact — causing wrong timebase/data on the next connection.

    // Shut down any running in-process ROHD example (completes the
    // keep-alive Completer, resets the simulator, clears the waveform
    // data source) so design data doesn't leak into the next session.
    try {
      _shutdownInProcessExample();
    } on Object catch (e) {
      debugPrint('[Connection] _shutdownInProcessExample failed: $e');
    }

    // Save monitored signal keys before disposing so they can be
    // restored in the new SignalBloc after the next hierarchy loads.
    // Only save when the transport is still connected — a disposed
    // transport still holds stale keys that must not be re-saved.
    try {
      if (_vmTransport.isConnected) {
        final keys = _vmTransport.trackedSignalKeys;
        if (keys.isNotEmpty) {
          _savedMonitoredSignalPaths = keys;
          debugPrint(
            '[Connection] Saved ${keys.length} monitored signal paths '
            'for restore: $keys',
          );
        }
      }
    } on Object catch (_) {
      // _vmTransport is `late` — first connect hasn't set it yet.
      // Clear stale saved paths (e.g. demo-mode defaults) so they don't
      // leak into the next connection's monitor list.
      _savedMonitoredSignalPaths = [];
    }

    // Waveform data source
    try {
      await _vmTransport.dispose();
    } on Object catch (_) {
      // _vmTransport is `late` — first connect hasn't set it yet.
    }
    _waveformApi = null;

    // Tree data source
    try {
      await _dataSource?.dispose();
    } on Exception catch (e) {
      debugPrint('[Connection] dataSource dispose failed: $e');
    }

    // Old VM service
    try {
      unawaited(_vmService?.dispose());
    } on Exception catch (e) {
      debugPrint('[Connection] vmService dispose failed: $e');
    }

    // Snapshot/evaluator state is always connection-scoped.
    _snapshotCubit.clear();
    _evalCache.reset();
    _sharedEvaluator = null;
    _error = null;

    if (transition.preservesAppState) {
      debugPrint(
        '[Connection] Tore down transport for same-VM restart — '
        'preserving widget state',
      );
      return;
    }

    _hierarchyCubit.clear();

    // Stale model/UI state
    _treeModel = null;
    _schematicJson = null;
    _pendingModuleExpansions.clear();
    _hasLoadedDesign = false;
    _loadedDesignName = null;

    // Bump generation so the WaveformViewerWrapper key changes and
    // Flutter creates a brand-new widget (with fresh BLoC + repository)
    // instead of recycling stale state.
    _connectionGeneration++;

    debugPrint(
      '[Connection] Tore down old connection — '
      'generation=$_connectionGeneration',
    );
  }

  /// Initialize VM service waveform data source for live mode.
  void _initVmWaveformDataSource(VmService vmService, String isolateId) {
    _vmTransport = VmServiceTransport(
      vmService: vmService,
      isolateId: isolateId,
    );
    _waveformApi = VmServiceSignalWaveformApi(_vmTransport)
      ..schematicModules = _schematicJson?['modules'] as Map<String, dynamic>?
      ..rootName = _treeModel?.name
      ..fetchModuleSchematic = _dataSource?.fetchModuleSchematic
      ..evalCache = _evalCache
      ..sharedEvaluator = _getSharedEvaluator();
    debugPrint('[Connection] Created VmServiceSignalWaveformApi');

    // Immediately fetch the current simulation time so the waveform
    // panel shows the real endTime even when connecting to an already-
    // paused isolate (no new pause event will fire to trigger _onPause).
    unawaited(_vmTransport.fetchAndEmitCurrentTime());
  }

  /// Detect color emoji font availability without causing rebuild flicker.
  Future<void> _detectEmojiFont() async {
    final hasFont = await isEmojiFontInstalled();
    if (mounted && hasFont != _hasColorEmoji) {
      setState(() => _hasColorEmoji = hasFont);
    }
    debugPrint('[StandaloneDevTools] Color emoji available: $hasFont');
  }

  /// Switch to a different example hierarchy.
  Future<void> _switchExample(int index) async {
    setState(() {
      _selectedExampleIndex = index;
      _hasLoadedDesign = false;
      _loadedDesignName = null;
    });

    // Dispose old data sources.
    if (_dataSource is InProcessTreeDataSource ||
        _dataSource is StaticJsonTreeDataSource) {
      await _dataSource?.dispose();
    }
    _shutdownInProcessExample();

    // Launch the new example and create data sources.
    final examples = rohdExamples;
    if (index >= examples.length) {
      return;
    }

    final example = examples[index];
    debugPrint('[Shell] Switching to example: ${example.name}');

    try {
      _exampleKeepAlive = await example.launcher();
    } on Exception catch (e) {
      debugPrint('[Shell] Example launch failed: $e');
      setState(() => _error = 'Failed to launch example: $e');
      return;
    }

    _dataSource = InProcessTreeDataSource(name: example.name);
    _inProcessTransport = InProcessTransport(name: example.name);
    _inProcessWaveformDataSource = InProcessWaveformDataSource(
      name: example.name,
    );
    _waveformApi = LoopbackSignalWaveformApi(_inProcessTransport)
      ..evalCache = _evalCache;

    // Pre-load default signals for this example.
    _savedMonitoredSignalPaths = _defaultMonitoredSignals(index);

    await _loadModuleTree();
  }

  @override
  void dispose() {
    _vmLivenessTimer?.cancel();
    stopDtdListener();
    _horizontalController.dispose();
    _verticalController.dispose();
    unawaited(_dataSource?.dispose());
    unawaited(_vmService?.dispose());
    // Dispose cubits
    unawaited(_treeSearchTermCubit.close());
    unawaited(_signalSearchTermCubit.close());
    unawaited(_detailsTabCubit.close());
    unawaited(_hierarchyCubit.close());
    unawaited(_snapshotCubit.close());
    _canSnapshotNotifier.dispose();
    _waveformXp.dispose();
    _schematicXp.dispose();
    _shellXp.dispose();
    _crossProbeChannel.dispose();
    super.dispose();
  }

  /// Whether connected to a VM service (vs loopback mode).
  bool get _isVmConnected => _vmService != null;

  /// Whether in loopback/demo mode (in-process or file-backed).
  bool get _isLoopbackMode =>
      _dataSource is InProcessTreeDataSource ||
      _dataSource is StaticJsonTreeDataSource;

  Future<RohdDesignCommandTarget?> _shellTarget() async {
    if (_dataSource is InProcessTreeDataSource) {
      return const InProcessRohdDesignTarget();
    }
    final currentVmService = _vmService;
    final currentIsolateId = _lastIsolateId;
    if (currentVmService == null || currentIsolateId == null || _isVmDead) {
      return null;
    }
    return VmServiceRohdDesignTarget(currentVmService, currentIsolateId);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _syncLocalConnectionStateFromHost();
    _syncCanSnapshot();
  }

  /// Push the current snapshot-availability to the [ValueNotifier] that
  /// the wave viewer's snapshot button listens to via
  /// [ValueListenableBuilder].  Called automatically after every
  /// [setState]; the notifier deduplicates so only actual changes
  /// trigger a rebuild.
  void _syncCanSnapshot() {
    _canSnapshotNotifier.value =
        (_isVmConnected && !_isVmDead) || _isLoopbackMode;
  }

  void _syncLocalConnectionStateFromHost() {
    _isConnected = isConnected;
    _isConnecting = isConnecting;
    _isVmDead = isVmDead;
    _isPaused = isPaused;
    _vmService = vmService;
    _lastVmServiceUri = lastVmServiceUri;
    _lastIsolateId = lastIsolateId;
    _connectedVmName = connectedVmName;
    _autoReconnect = autoReconnect;
  }

  /// Wait for icon fonts to finish loading, then show the connection dialog.
  ///
  /// On Flutter web (CanvasKit), fonts from FontManifest.json are loaded and
  /// parsed by the WASM Skia engine asynchronously. There is no reliable
  /// framework-level signal for when glyphs are actually renderable — the
  /// `systemFonts` notification fires before CanvasKit finishes parsing.
  /// We wait for the notification AND an additional frame to allow CanvasKit
  /// to rasterise the glyphs, with a hard delay fallback.
  Future<void> _showConnectionDialogWhenReady() async {
    if (kIsWeb) {
      final completer = Completer<void>();
      void onFontsChanged() {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      PaintingBinding.instance.systemFonts.addListener(onFontsChanged);
      // Wait for the font-loaded signal (or timeout as fallback).
      await completer.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {},
      );
      PaintingBinding.instance.systemFonts.removeListener(onFontsChanged);

      // Give CanvasKit one more frame to rasterise the glyphs after loading.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    if (!mounted || _isConnected) {
      return;
    }
    await showConnectionDialog();
  }

  void _handleBeforeVmConnected(
    VmConnectionResult result,
    String uri, {
    required VmConnectionTransition transition,
  }) {
    final previousUri = transition.previousUri;
    final previousIsolateId = transition.previousIsolateId;
    if (!transition.isSameLogicalVm &&
        previousIsolateId != null &&
        result.isolateId != previousIsolateId) {
      debugPrint(
        '[Connection] Isolate ID changed '
        '($previousIsolateId → ${result.isolateId}) with '
        'URI change ($previousUri → $uri) — '
        'clearing saved monitored signals',
      );
      _savedMonitoredSignalPaths = [];
    } else if (transition.isSameLogicalVm &&
        previousIsolateId != null &&
        result.isolateId != previousIsolateId) {
      debugPrint(
        '[Connection] Isolate ID changed '
        '($previousIsolateId → ${result.isolateId}) at the same URI '
        '($uri) during same-VM restart — preserving saved monitored '
        'signals',
      );
    }
  }

  void _handleConnectedVmState(
    VmConnectionResult result,
    String vmServiceUri,
    VmServiceTreeDataSource vmDataSource,
  ) {
    // Transition to the main UI immediately — shows AppBar, empty panels,
    // and a loading indicator while the (potentially large) design JSON
    // is fetched and parsed in the background.
    setState(() {
      _vmService = result.vmService;
      _dataSource = vmDataSource;
      _isConnected = true;
      _isConnecting = false;
      _isVmDead = false;
      _isPaused = false;

      final vmFlc = FlcService(
        fetchModuleFlc: vmDataSource.fetchModuleFlc,
        fetchFlcHierarchy: vmDataSource.fetchFlcHierarchy,
        fetchFlcFilePath: vmDataSource.fetchFlcFilePath,
        onClearCache: vmDataSource.clearFlcCache,
      );
      _sourceNavService = SourceNavigationService()
        ..sourceLineFetcher = vmDataSource.fetchSourceLine
        ..setFlcService(vmFlc);
      _extensionClient?.dispose();
      _extensionClient = FlcExtensionClient(flcService: vmFlc);
      _currentFlcService = vmFlc;
      if (persistentDtd != null && !persistentDtd!.isClosed) {
        _sourceNavService!.setDtd(persistentDtd!);
      }
      debugPrint('[Shell] SourceNavigationService created');
      _lastVmServiceUri = vmServiceUri;
      _lastIsolateId = result.isolateId;
    });
  }

  void _handleExplicitDisconnect() {
    // Explicit disconnect — don't carry signals to a future connection.
    _savedMonitoredSignalPaths = [];

    setState(() {
      _vmService = null;
      _dataSource = null;
      _treeModel = null;
      _error = null;
      _isConnected = false;
      _isConnecting = false;
      _isVmDead = false;
      _isPaused = false;
      connectionError = null;
      _lastVmServiceUri = null;
      _lastIsolateId = null;
      _connectedVmName = null;
      _autoReconnect = false;
      _hasLoadedDesign = false;
      _loadedDesignName = null;
      _sourceNavService?.clearFlcService();
      _sourceNavService = null;
      _extensionClient?.dispose();
      _extensionClient = null;
      _currentFlcService = null;
    });

    unawaited(showConnectionDialog());
  }

  void _handlePausedVm() {
    _vmTransport.pauseFetches();
  }

  Future<void> _handleResumedVm() => _vmTransport.resumeFetches();

  Future<VmServiceTreeDataSource> _handleLightweightReconnectSuccess(
    VmConnectionResult result,
  ) async {
    await _vmTransport.reconnect(
      result.vmService,
      result.isolateId,
      preserveTracking: true,
    );

    unawaited(_vmTransport.fetchAndEmitCurrentTime());

    return VmServiceTreeDataSource(
      vmService: result.vmService,
      isolateId: result.isolateId,
    );
  }

  void _handleDtdConnected(DartToolingDaemon dtd) {
    _sourceNavService?.setDtd(dtd);
  }

  void _handleDtdDisconnected() {
    _sourceNavService?.clearDtd();
  }

  /// Full design+waveform refresh used by the module tree refresh button.
  ///
  /// Flushes all cached design/waveform state (snapshot, evaluator,
  /// waveform cache) and bumps the connection generation so that a
  /// brand-new WaveformViewerWrapper (with fresh BLoC + repository) is
  /// created.  Then reloads the module tree — which re-fetches structure
  /// and endTime from the data source.
  Future<void> _fullRefresh() async {
    debugPrint('[Refresh] Full design+waveform refresh');

    // Flush cached evaluation / snapshot state.
    _snapshotCubit.clear();
    _evalCache.reset();
    _sharedEvaluator = null;

    // Clear schematic so it's refetched.
    _schematicJson = null;

    // Bump generation so WaveformViewerWrapper is fully recreated —
    // this gives us a fresh SignalBloc, WaveformRepository (empty
    // waveform cache), and RohdModuleBloc (empty endTime metadata).
    _connectionGeneration++;
    debugPrint(
      '[Refresh] Bumped connection generation to '
      '$_connectionGeneration',
    );

    // For VM connections, also flush the per-signal timepoints in the
    // data source so the next fetch retrieves full waveform history
    // instead of only incremental data since the last fetch.
    try {
      _vmTransport.untrackAllSignals();
    } on Object catch (_) {
      // late init / loopback — no VM data source
    }

    // For loopback, clear the cached module structure so it's re-read
    // from WaveformService on the next getModuleStructure() call.
    _inProcessWaveformDataSource?.clearCache();

    // Clear the waveform API caches (structure, index maps, waveform
    // data) so everything is re-fetched from scratch.
    final api = _waveformApi;
    if (api is LoopbackSignalWaveformApi) {
      api.clearCache();
    } else if (api is VmServiceSignalWaveformApi) {
      api.clearCache();
    }

    // Re-fetch the current simulation time so endTime is correct.
    if (_waveformApi != null) {
      try {
        final time = await _waveformApi!.getCurrentTime();
        if (time != null && time > 0) {
          debugPrint('[Refresh] Current simulation time: $time');
        }
      } on Object catch (_) {}
    }

    // Reload the module tree (re-fetches hierarchy + schematic +
    // endTime from the data source).
    await _loadModuleTree();
  }

  Future<void> _loadModuleTree() async {
    debugPrint(
      '[LoadTree] _loadModuleTree called, _dataSource: '
      '${_dataSource?.runtimeType}',
    );
    if (_dataSource == null) {
      debugPrint('[LoadTree] _dataSource is null, returning');
      return;
    }

    // Capture the connection generation so we can detect if a
    // disconnect/reconnect happened while we were awaiting.  If the
    // generation changes, this invocation must bail out to avoid
    // writing stale data from an old design into the new API.
    final startGeneration = _connectionGeneration;
    final previousSelectedModulePath = _hierarchyCubit.selectedModule?.path();

    debugPrint('[LoadTree] Loading module tree...');
    // Signal loading via the cubit only — no setState so the rest of the
    // app (waveform, schematic, AppBar) is untouched.
    _error = null;
    _hierarchyCubit.setLoading();

    try {
      debugPrint('[LoadTree] Calling evalModuleTree...');
      var tree = await _dataSource!.evalModuleTree();
      debugPrint('[LoadTree] evalModuleTree returned: ${tree?.runtimeType}');

      // Bail out if the connection changed during the await.
      if (_connectionGeneration != startGeneration) {
        debugPrint('[LoadTree] Generation changed — aborting stale load');
        return;
      }

      // If eval returned null but the VM is alive, the isolate may have
      // changed (e.g. hot restart).  Try to re-discover the main isolate
      // and create a fresh data source before giving up.
      if (tree == null && _isVmConnected && _vmService != null) {
        debugPrint('[LoadTree] Tree is null — trying isolate rediscovery');
        final refreshed = await _tryRefreshDataSource();
        if (refreshed) {
          tree = await _dataSource!.evalModuleTree();
          debugPrint('[LoadTree] After rediscovery: ${tree?.runtimeType}');
        }
      }

      // Bail out if the connection changed during isolate rediscovery.
      if (_connectionGeneration != startGeneration) {
        debugPrint('[LoadTree] Generation changed — aborting stale load');
        return;
      }

      // Extract schematic JSON from data source if available
      final schematicJson = _dataSource!.getSchematicJson();
      if (schematicJson != null) {
        debugPrint(
          '[LoadTree] Schematic JSON available: '
          '${schematicJson.length} keys',
        );
      } else {
        debugPrint('[LoadTree] No schematic JSON from data source');
      }

      if (tree == null && _isVmConnected) {
        // Check if the VM service connection is actually still alive.
        // After a debugger restart the old VmService object is disposed
        // but _vmService isn't cleared until we detect it.  If the
        // connection is dead, fire VmDied immediately so auto-reconnect
        // kicks in — don't wait for the 30-second liveness polling cycle.
        final alive = await isVmServiceAlive();
        if (!alive) {
          debugPrint('[LoadTree] VM service is dead — triggering VmDied');
          connectionStateMachine.handleEvent(const VmDied());
          if (mounted) {
            setState(() {
              _isVmDead = true;
            });
          }
          if (_autoReconnect) {
            unawaited(attemptAutoReconnect());
          }
          return;
        }

        // The ROHD app may not have finished building ModuleTree yet.
        // Instead of retrying in a blocking loop ("spinning"), we notify
        // the state machine that the attempt returned null.  The CSM
        // will automatically retry on the next debug pause event when
        // the app is more likely to have data ready.
        debugPrint(
          '[LoadTree] Tree is null — CSM will retry on next '
          'debug pause',
        );
        connectionStateMachine.handleEvent(
          const HierarchyLoadResult(success: false),
        );

        // Re-subscribe to debug events in case the subscription was
        // lost during reconnect.  This is idempotent — if already
        // subscribed, it just cancels and re-adds the listener.
        if (_vmService != null) {
          unawaited(connectionStateMachine.subscribeToDebugEvents(_vmService!));
        }

        _hierarchyCubit.setError(
          'Waiting for design data — will load automatically at next '
          'breakpoint',
        );
        return;
      }

      _treeModel = tree;
      _schematicJson = schematicJson;
      _sharedEvaluator = null; // invalidate; will be recreated lazily

      // Push schematic modules, root name, and fetch callback to the
      // waveform API for client-side evaluation of computed signals.
      final api = _waveformApi;
      if (schematicJson != null) {
        final modules = schematicJson['modules'] as Map<String, dynamic>?;
        if (api is VmServiceSignalWaveformApi) {
          api.schematicModules = modules;
          if (tree != null) {
            api.rootName = tree.name;
          }
          api
            ..fetchModuleSchematic = _dataSource?.fetchModuleSchematic
            ..sharedEvaluator = _getSharedEvaluator();
        } else if (api is LoopbackSignalWaveformApi) {
          api
            ..schematicModules = modules
            ..fetchModuleSchematic = _dataSource?.fetchModuleSchematic
            ..sharedEvaluator = _getSharedEvaluator();
        }
      }

      // Notify the state machine of the successful load.
      if (tree != null) {
        connectionStateMachine.handleEvent(
          const HierarchyLoadResult(success: true),
        );
        if (schematicJson != null) {
          connectionStateMachine.markSchematicLoaded();
        }
      }

      // Update the shared hierarchy cubit so embedded viewers can access it
      if (tree != null) {
        // Assign index-based addresses to every node and signal so
        // OccurrenceAddress-based lookups and cross-probing work.
        tree.buildAddresses();

        _hierarchyCubit.loadFromNode(tree);

        final restoredSelection = previousSelectedModulePath == null
            ? null
            : _findHierarchyOccurrenceByPath(tree, previousSelectedModulePath);
        if (restoredSelection != null) {
          _hierarchyCubit.selectModule(restoredSelection);
        }

        // Wire the hierarchy into source navigation so instance paths
        // (from the waveform viewer) can be translated to definition
        // paths for FLC lookup.
        final hs = _hierarchyCubit.state;
        if (hs is HierarchyLoaded &&
            hs.hierarchyService != null &&
            _sourceNavService != null) {
          _sourceNavService!.setHierarchy(hs.hierarchyService!);
        }

        // Push the hierarchy-derived module structure to the waveform API
        // so it builds its DFS dictionary from the same tree the hierarchy
        // cubit uses.  This avoids a redundant fetch of module data via
        // WaveformService — WaveformService should only transport signal
        // *values*, not module structure.
        if (_waveformApi != null && _connectionGeneration == startGeneration) {
          final structure = ModuleStructure(
            metadata: const MetaData(
              source: 'TreeDataSource',
              timescale: '1ps',
              date: '',
            ),
            modules: [tree],
          );
          final wfApi = _waveformApi;
          if (wfApi is VmServiceSignalWaveformApi) {
            await wfApi.setExternalStructure(structure);
          } else if (wfApi is LoopbackSignalWaveformApi) {
            await wfApi.setExternalStructure(structure);
          }
        }

        // Auto-select the top block so the Module panel highlights it and
        // the Details tab shows its signals.  Only do this on the initial
        // load (when nothing is selected yet) so that a user's manual
        // selection is preserved across refreshes.
        if (_connectionGeneration != startGeneration) {
          debugPrint('[LoadTree] Generation changed — aborting stale load');
          return;
        }
        if (_hierarchyCubit.selectedModule == null) {
          _hierarchyCubit.selectModule(tree);
        }

        // setState so non-cubit-driven parts of the UI (schematic viewer,
        // AppBar) also see the updated _treeModel / _schematicJson.
        if (mounted) {
          setState(() {});
        }

        // In loopback mode, take an initial snapshot so signal values
        // are visible in the schematic hover / details pane immediately.
        if (_isLoopbackMode && _waveformApi != null) {
          final signalValueSource = WaveformSignalValueSource(
            api: _waveformApi!,
          );
          final time = await signalValueSource.getCurrentTime();
          if (time != null && time > 0) {
            unawaited(_snapshotCubit.takeSnapshot(signalValueSource, time));
          }
        }
      } else {
        _hierarchyCubit.clear();
      }
    } on Object catch (error, stackTrace) {
      debugPrint('[LoadTree] Error loading module tree: $error\n$stackTrace');
      _error = 'Error loading module tree: $error';
      _hierarchyCubit.setError('Error loading module tree: $error');
    }
  }

  /// Try to refresh the tree data source by re-discovering the current
  /// main isolate.  Returns true if the data source was replaced.
  ///
  /// This handles the case where the isolate changed (hot restart, debugger
  /// reload) but the VM service connection is still alive.
  Future<bool> _tryRefreshDataSource() async {
    final vm = _vmService;
    if (vm == null) {
      return false;
    }
    try {
      // During a debugger restart the test isolate (with ROHD) may not
      // have spawned yet.  Retry a few times with a short delay so we
      // don't give up prematurely and wait for the CSM debug-pause retry.
      String? newIsolateId;
      const maxRetries = 4;
      const retryDelay = Duration(milliseconds: 500);

      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        final vmInfo = await vm.getVM().timeout(const Duration(seconds: 3));
        final isolates = vmInfo.isolates ?? [];
        if (isolates.isEmpty) {
          if (attempt < maxRetries) {
            debugPrint(
              '[LoadTree] No isolates yet '
              '(attempt $attempt/$maxRetries) — retrying',
            );
            await Future<void>.delayed(retryDelay);
            continue;
          }
          return false;
        }

        for (final ref in isolates) {
          final id = ref.id;
          if (id == null) {
            continue;
          }
          try {
            final iso = await vm
                .getIsolate(id)
                .timeout(const Duration(milliseconds: 500));
            final libs = iso.libraries ?? [];
            final hasRohd = libs.any(
              (lib) =>
                  lib.uri != null &&
                  lib.uri!.contains('rohd') &&
                  lib.uri!.contains('inspector_service'),
            );
            if (hasRohd) {
              newIsolateId = id;
              break;
            }
          } on Exception {
            continue;
          }
        }

        if (newIsolateId != null) {
          break;
        }

        // Isolates exist but none had ROHD yet.  On the last attempt,
        // fall back to the first isolate only if it differs from the
        // current one (otherwise there's nothing new to try).
        if (attempt < maxRetries) {
          debugPrint(
            '[LoadTree] ROHD isolate not found yet '
            '(attempt $attempt/$maxRetries, '
            '${isolates.length} isolate(s)) — retrying',
          );
          await Future<void>.delayed(retryDelay);
        } else {
          newIsolateId = isolates.first.id;
        }
      }

      if (newIsolateId == null) {
        return false;
      }

      // If the isolate is the same, no point in replacing the data source
      if (newIsolateId == _lastIsolateId) {
        return false;
      }

      debugPrint(
        '[LoadTree] Isolate changed: $_lastIsolateId → '
        '$newIsolateId — refreshing data source',
      );
      _lastIsolateId = newIsolateId;

      // Replace the tree data source with the correct isolate
      await _dataSource?.dispose();
      final newDataSource = VmServiceTreeDataSource(
        vmService: vm,
        isolateId: newIsolateId,
      );
      setState(() {
        _dataSource = newDataSource;
      });

      // Also update the waveform data source to use the correct isolate.
      // Without this, _vmTransport still points at the old
      // (wrong) isolate and all evaluate() calls return null.
      await _vmTransport.reconnect(vm, newIsolateId, preserveTracking: true);
      debugPrint(
        '[LoadTree] Waveform data source updated to '
        'isolate $newIsolateId',
      );

      // Clear stale cached data from the previous isolate's session.
      // The waveform API caches the old dictionary, structure, and
      // waveform data — all invalid after the debugger reloaded.
      final api = _waveformApi;
      if (api is VmServiceSignalWaveformApi) {
        api.clearCache();
        debugPrint('[LoadTree] Cleared VmServiceSignalWaveformApi cache');
      }

      // Keep the current tree/schematic widgets alive until the refreshed
      // design data arrives from the restarted VM.
      _snapshotCubit.clear();
      _evalCache.reset();
      _sharedEvaluator = null;

      // Update the CSM identity
      final identity = VmIdentity(
        uri: _lastVmServiceUri ?? '',
        isolateId: newIsolateId,
        vmName: _connectedVmName,
      );
      connectionStateMachine.handleEvent(ConnectionEstablished(vm, identity));
      unawaited(connectionStateMachine.subscribeToDebugEvents(vm));

      return true;
    } on Exception catch (e) {
      debugPrint('[LoadTree] Isolate rediscovery failed: $e');
      return false;
    }
  }

  HierarchyOccurrence? _findHierarchyOccurrenceByPath(
    HierarchyOccurrence root,
    String path,
  ) {
    if (root.path() == path) {
      return root;
    }

    for (final child in root.children) {
      final match = _findHierarchyOccurrenceByPath(child, path);
      if (match != null) {
        return match;
      }
    }

    return null;
  }

  // NOTE: _retryLoadModuleTree has been removed.  The old approach used
  // an exponential-backoff loop (2s, 4s, 8s, ...) that "spun" after
  // connect waiting for data.  The ConnectionStateMachine now handles
  // retries: when a debug pause event arrives and hierarchy data is
  // still missing, it triggers a single _loadModuleTree call.  This is
  // event-driven instead of polling-driven.

  /// Show licenses page (cached callback to prevent rebuild).
  void _showLicenses() {
    registerBundledThirdPartyLicenses();
    showLicensePage(context: context);
  }

  /// Get or create cached AppBar - only recreates if values changed.
  _StandaloneAppBar _getAppBar() {
    final currentIsLoopbackMode = _isLoopbackMode;
    final currentIsVmConnected = _isVmConnected;

    if (_cachedAppBar == null ||
        _lastIsLoopbackMode != currentIsLoopbackMode ||
        _lastIsVmConnected != currentIsVmConnected ||
        _lastIsConnecting != _isConnecting ||
        _lastIsVmDead != _isVmDead ||
        _lastIsPaused != _isPaused ||
        _lastSelectedExampleIndex != _selectedExampleIndex ||
        _lastHasColorEmoji != _hasColorEmoji ||
        _lastHasLoadedDesign != _hasLoadedDesign ||
        _cachedAppBar!._extensionClient != _extensionClient) {
      _lastIsLoopbackMode = currentIsLoopbackMode;
      _lastIsVmConnected = currentIsVmConnected;
      _lastIsConnecting = _isConnecting;
      _lastIsVmDead = _isVmDead;
      _lastIsPaused = _isPaused;
      _lastSelectedExampleIndex = _selectedExampleIndex;
      _lastHasColorEmoji = _hasColorEmoji;
      _lastHasLoadedDesign = _hasLoadedDesign;
      _cachedAppBar = _StandaloneAppBar(
        title: widget.config.title,
        isLoopbackMode: currentIsLoopbackMode,
        isVmConnected: currentIsVmConnected,
        isConnecting: _isConnecting,
        isVmDead: _isVmDead,
        isPaused: _isPaused,
        selectedExampleIndex: _selectedExampleIndex,
        exampleDropdownItems: _exampleDropdownItems,
        onExampleChanged: _onExampleChanged,
        onDisconnect: _onDisconnect,
        onConnect: _onConnect,
        onPause: _onPauseVm,
        onResume: _onResumeVm,
        onRefresh: _onRefresh,
        onLicenses: _onLicenses,
        onLoadDesign: _onLoadDesign,
        onLoadWaveform: _onLoadWaveform,
        hasLoadedDesign: _hasLoadedDesign,
        loadedDesignName: _loadedDesignName,
        canConnect: widget.config.connectionStrategy != null,
        hasColorEmoji: _hasColorEmoji,
        extensionClient: _extensionClient,
        hierarchyCubit: _hierarchyCubit,
        onRefreshModuleInfo: _refreshModuleInfoViaDtd,
      );
    }
    return _cachedAppBar!;
  }

  // Cached body widget - rebuilt when tree model, error state, or
  // connection generation changes.  Connection generation MUST be
  // tracked so that the WaveformViewerWrapper (which is baked into
  // the cached widget tree) gets the new _waveformApi after a
  // reconnect instead of routing to the disposed old data source.
  Widget? _cachedBody;
  TreeModel? _lastTreeModel;
  String? _lastError;
  int _lastConnectionGeneration = 0;

  Widget _getCachedBody(BuildContext context) {
    if (_cachedBody == null ||
        _lastTreeModel != _treeModel ||
        _lastError != _error ||
        _lastConnectionGeneration != _connectionGeneration) {
      _lastTreeModel = _treeModel;
      _lastError = _error;
      _lastConnectionGeneration = _connectionGeneration;
      _cachedBody = _buildBody(context);
    }
    return _cachedBody!;
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        // Use BlocProvider.value to reuse existing cubits
        // (prevents recreation on rebuild)
        providers: [
          BlocProvider.value(value: _treeSearchTermCubit),
          BlocProvider.value(value: _signalSearchTermCubit),
          BlocProvider.value(value: _detailsTabCubit),
          BlocProvider.value(value: _hierarchyCubit),
          BlocProvider.value(value: _snapshotCubit),
        ],
        // Use Column with independent RepaintBoundary for each section
        // This completely isolates AppBar repaints from body repaints
        child: Column(
          children: [
            // AppBar in its own RepaintBoundary with Listener to absorb pointer
            // events This prevents pointer event bubbling that could cause
            // waveform flicker on hover
            RepaintBoundary(
              child: Listener(
                onPointerMove: (_) {}, // Consume pointer move events
                onPointerDown: (_) {}, // Consume pointer down events
                onPointerUp: (_) {}, // Consume pointer up events
                behavior: HitTestBehavior.opaque,
                child: _getAppBar(),
              ),
            ),
            // Body in its own RepaintBoundary
            Expanded(child: RepaintBoundary(child: _getCachedBody(context))),
          ],
        ),
      );

  /// Enter demo mode with loopback data.
  Future<void> _enterDemoMode() async {
    connectionStateMachine.handleEvent(const DemoModeEntered());
    // Set connected first so the main UI renders immediately
    setState(() {
      _isConnected = true;
    });
    await _initLoopbackMode();
  }

  /// Load a design JSON file from the user's file system.
  ///
  /// Supports ROHD hierarchy, Yosys netlist, and Unified formats.
  /// The loaded design replaces the current loopback example.
  /// After loading, the "Load Waveform" button becomes available.
  ///
  /// Uses file_selector (same as the wave viewer) for consistent native
  /// file dialog behavior on Linux, macOS, and Windows.
  Future<void> _loadDesignFromFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Design files',
        extensions: <String>['json'],
      );
      final xfile = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (xfile == null) {
        return; // User cancelled
      }

      final bytes = await xfile.readAsBytes();
      if (bytes.isEmpty) {
        setState(() {
          _error = 'Could not read file contents';
        });
        return;
      }

      final fileName = xfile.name;
      debugPrint(
        '[LoadDesign] Loading design from: $fileName '
        '(${bytes.length} bytes)',
      );

      final jsonString = utf8.decode(bytes);
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;

      // Dispose old data source (loopback or in-process)
      if (_dataSource is StaticJsonTreeDataSource ||
          _dataSource is InProcessTreeDataSource) {
        await _dataSource?.dispose();
      }
      _shutdownInProcessExample();
      unawaited(_inProcessWaveformDataSource?.dispose());
      _inProcessWaveformDataSource = null;

      // Create a static tree data source from the loaded JSON
      _dataSource = StaticJsonTreeDataSource(jsonMap, name: fileName);

      // Clear waveform data (will need to load a VCD separately)
      // Keep the current _waveformApi so the wave viewer has something;
      // it will be replaced when a waveform file is loaded.

      // Mark that we have a loaded design
      setState(() {
        _hasLoadedDesign = true;
        _loadedDesignName = fileName;
        _savedMonitoredSignalPaths = [];
        _error = null;
      });

      // Bump connection generation so wave viewer recreates
      _connectionGeneration++;

      await _loadModuleTree();

      debugPrint('[LoadDesign] Design loaded successfully: $fileName');
    } on FormatException catch (e) {
      setState(() {
        _error = 'Invalid JSON format: $e';
      });
    } on Exception catch (e) {
      setState(() {
        _error = 'Error loading design: $e';
      });
    }
  }

  /// Load a waveform file (VCD/FST/GHW) from the user's file system.
  ///
  /// This replaces the current waveform data while preserving the loaded
  /// design hierarchy. Can be called multiple times to reload waveforms.
  ///
  /// Uses file_selector (same as the wave viewer) for consistent native
  /// file dialog behavior on Linux, macOS, and Windows.
  Future<void> _loadWaveformFromFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Waveform files',
        extensions: <String>['vcd', 'fst', 'ghw'],
      );
      final xfile = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (xfile == null) {
        return; // User cancelled
      }

      final bytes = await xfile.readAsBytes();
      if (bytes.isEmpty) {
        setState(() {
          _error = 'Could not read file contents';
        });
        return;
      }

      final fileName = xfile.name;
      debugPrint(
        '[LoadWaveform] Loading waveform from: $fileName '
        '(${bytes.length} bytes)',
      );

      // Parse the VCD/FST/GHW via Wellen (like WaveDumper writes VCD)
      final wellenApi = WellenSignalWaveformApi();
      await wellenApi.loadBytes(bytes.toList(), fileName: fileName);

      // Get the design hierarchy if one has been loaded — this provides
      // richer signal metadata (port directions, types) than VCD alone.
      HierarchyService? designHierarchy;
      final hierarchyState = _hierarchyCubit.state;
      if (hierarchyState is HierarchyLoaded) {
        designHierarchy = hierarchyState.hierarchyService;
      }

      // Create a WaveformDataSource that serves Wellen data through the
      // same interface as ROHD's WaveformService. This parallels what
      // WaveDumper does on the sim side: VCD → in-process repository.
      final wellenDataSource = WellenBackedWaveformDataSource(
        wellenApi: wellenApi,
        designHierarchy: designHierarchy,
        name: fileName,
      );

      // Dispose old in-process waveform data source
      unawaited(_inProcessWaveformDataSource?.dispose());
      _inProcessWaveformDataSource = null;
      _shutdownInProcessExample();

      // Wrap with LoopbackSignalWaveformApi — the same adapter used by
      // the in-process examples and by the VM service path.  This gives
      // us signal dictionary, compact transport, and snapshot cascade
      // for free, hiding the transport layer.
      _waveformApi = LoopbackSignalWaveformApi(wellenDataSource)
        ..evalCache = _evalCache;
      _connectionGeneration++;
      _savedMonitoredSignalPaths = [];

      setState(() {
        _error = null;
      });

      debugPrint('[LoadWaveform] Waveform loaded successfully: $fileName');
    } on Exception catch (e) {
      setState(() {
        _error = 'Error loading waveform: $e';
      });
    }
  }

  Widget _buildBody(BuildContext context) {
    // Show error banner if there's an error but we have data
    Widget? errorBanner;
    if (_error != null) {
      errorBanner = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        color: Colors.orange.withValues(alpha: 0.2),
        child: Row(
          children: [
            platformIcon(
              Icons.warning,
              '⚠️',
              color: Colors.orange,
              size: 16,
              hasColorEmoji: _hasColorEmoji,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
            IconButton(
              icon: platformIcon(
                Icons.close,
                '✖️',
                size: 16,
                hasColorEmoji: _hasColorEmoji,
              ),
              onPressed: () => setState(() => _error = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (errorBanner != null) errorBanner,
        Expanded(child: _buildTreeStructurePage(context)),
      ],
    );
  }

  Widget _buildTreeStructurePage(BuildContext context) =>
      BlocBuilder<DevToolsHierarchyCubit, DevToolsHierarchyState>(
        builder: (context, hierarchyState) {
          final hierarchyService = hierarchyState is HierarchyLoaded
              ? hierarchyState.hierarchyService
              : null;

          return DevToolsSplitLayout(
            moduleTreeConfig: ModuleTreePanelConfig(
              icon: platformIcon(
                Icons.account_tree,
                '🌳',
                hasColorEmoji: _hasColorEmoji,
              ),
              refreshIcon: platformIcon(
                Icons.refresh,
                '🔃',
                size: 24,
                hasColorEmoji: _hasColorEmoji,
              ),
              onRefresh: _fullRefresh,
              treeContent: _buildTreeContent(context),
              verticalController: _verticalController,
              horizontalController: _horizontalController,
              hierarchyService: hierarchyService,
              bottomContent: RohdDesignShell(
                targetProvider: _shellTarget,
                formatForPath: (path) => SignalValueFormatRegistry.formatForAny(
                  [hierarchyService?.pathnameToAddress(path)],
                ),
                onSendSignals: (paths) {
                  _shellXp.send(paths, source: 'rohd-shell');
                },
                headerActions: [
                  RohdShellHelpButton(
                    isDark: context.watch<DevToolsThemeCubit>().state ==
                        DevToolsThemeMode.dark,
                    hasColorEmoji: _hasColorEmoji,
                  ),
                ],
              ),
            ),
            detailsConfig: DetailsPanelConfig(
              content: SourceFramePointerTracker(
                child: DetailsPanelContent(
                  waveformConfig: WaveformTabConfig(
                    waveformViewer: WaveformViewerWrapper(
                      // Force recreation on example change or full reconnect
                      key: ValueKey(
                        '$_selectedExampleIndex:$_connectionGeneration',
                      ),
                      signalWaveformApi: _waveformApi,
                      crossProbeService: _waveformXp,
                      canSnapshot:
                          (_isVmConnected && !_isVmDead) || _isLoopbackMode,
                      canSnapshotNotifier: _canSnapshotNotifier,
                      initialMonitoredSignalPaths:
                          _savedMonitoredSignalPaths.isNotEmpty
                              ? _savedMonitoredSignalPaths
                              : null,
                      onRefresh: () {
                        setState(() {});
                      },
                      onGoToSource: _sourceNavService != null
                          ? (format, paths) => _goToSource(paths, format)
                          : null,
                      extensionClient: _extensionClient,
                    ),
                  ),
                  schematicConfig: SchematicTabConfig(
                    assetPath: 'rohd_schematic.json',
                    customWidgetBuilder: ({required isVisible}) =>
                        _buildStandaloneSchematicViewer(
                      context,
                      isVisible: isVisible,
                    ),
                  ),
                  hasColorEmoji: _hasColorEmoji,
                  signalValueFallback: _evaluateForDetailsPane,
                  onExpandModule: _expandModuleForDetailsPane,
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
          );
        },
      );

  /// Build tree content driven by the hierarchy cubit.
  ///
  /// Only the tree panel rebuilds on refresh — the rest of the app
  /// (waveform, schematic, AppBar) is untouched.
  Widget _buildTreeContent(BuildContext context) =>
      BlocBuilder<DevToolsHierarchyCubit, DevToolsHierarchyState>(
        bloc: _hierarchyCubit,
        builder: (context, state) {
          if (state is HierarchyLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is HierarchyLoaded) {
            return ModuleTreeCard(futureModuleTree: state.root);
          }

          // HierarchyNotLoaded, HierarchyError, or null tree
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
                  if (state is HierarchyError) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _loadModuleTree,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
      );

  /// Builds the schematic viewer with theme and hierarchy integration.
  Widget _buildStandaloneSchematicViewer(
    BuildContext context, {
    required bool isVisible,
  }) =>
      BlocBuilder<DevToolsHierarchyCubit, DevToolsHierarchyState>(
        builder: (context, hierarchyState) {
          final hierarchyService = hierarchyState is HierarchyLoaded
              ? hierarchyState.hierarchyService
              : null;

          // Show loading message if hierarchy hasn't loaded yet
          if (hierarchyService == null && hierarchyState is! HierarchyLoaded) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading module hierarchy...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          final selectedModule = hierarchyState is HierarchyLoaded
              ? hierarchyState.selectedModule
              : null;
          // Use the selected module's path, or fall back to the root
          // module's path so that even top-level lookups are scoped.
          final lookupModulePath = selectedModule?.path() ??
              (hierarchyState is HierarchyLoaded
                  ? hierarchyState.root.path()
                  : null);
          return BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
            builder: (context, themeMode) {
              final schematicThemeMode = themeMode == DevToolsThemeMode.dark
                  ? SchematicThemeMode.dark
                  : SchematicThemeMode.light;
              // Rebuild when snapshot state changes so that
              // signalValueLookupFn picks up new snapshot data
              // (e.g. after returning from a snapshot).
              return BlocBuilder<SnapshotCubit, SnapshotState>(
                builder: (context, _) => EmbeddedSchematicViewer(
                  // Don't pass assetPath - use externalHierarchy instead
                  initialThemeMode: schematicThemeMode,
                  externalHierarchy: hierarchyService,
                  netlistJsonMap: _schematicJson,
                  selectedModule: selectedModule,
                  isVisible: isVisible,
                  signalValueLookupFn: _buildSignalValueLookup(
                    modulePath: lookupModulePath,
                  ),
                  fetchModuleNetlist: _dataSource?.fetchModuleSchematic,
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

  /// Refresh module info via DTD's `rohd.queryModule` which performs
  /// file-existence checks on the VS Code extension host side.
  /// Returns the fresh [RohdModuleInfo], or `null` if DTD is unavailable.
  Future<RohdModuleInfo?> _refreshModuleInfoViaDtd(String module) async {
    final dtd = persistentDtd;
    final flcService = _currentFlcService;
    if (dtd == null || dtd.isClosed || flcService == null) {
      debugPrint(
        '[CrossProbe] DTD refresh unavailable '
        '(dtd=${dtd != null}, flcService=${flcService != null})',
      );
      return null;
    }

    final flcPath = await flcService.getFlcPath();
    if (flcPath == null) {
      debugPrint(
        '[CrossProbe] DTD refresh: no FLC path available; '
        'using in-memory FLC data',
      );
      final info = await _refreshModuleInfoLocally(
        module,
        dtdStatusMessage: 'No written FLC sidecar path is available; '
            'using in-memory FLC data without VS Code file-existence checks.',
      );
      return info;
    }

    debugPrint(
      '[CrossProbe] DTD rohd.queryModule: '
      'module=$module, flcPath=$flcPath',
    );

    try {
      final response = await dtd.call(
        'rohd',
        'queryModule',
        params: {'flcPath': flcPath, 'module': module},
      ).timeout(const Duration(seconds: 3));
      final result = Map<String, dynamic>.from(response.result);
      debugPrint('[CrossProbe] DTD queryModule result: $result');

      // A successful live query is the strongest health signal for cross-probe.
      final status = (result['status'] as String?)?.toLowerCase();
      final querySucceeded = status == null || status == 'ok';
      if (querySucceeded) {
        result['dtdHealthy'] = true;
        result['dtdRegistrationConflict'] = false;
        result['dtdStatusMessage'] =
            'DTD service rohd responded successfully to queryModule.';
      }

      return RohdModuleInfo.fromJson(result);
    } on Exception catch (e) {
      debugPrint('[CrossProbe] DTD queryModule failed: $e');
      final dtdHealth = await _inspectRohdDtdService(dtd);
      debugPrint('[CrossProbe] DTD health: $dtdHealth');
      return RohdModuleInfo(
        extensionAvailable: false,
        module: module,
        error: e.toString(),
        dtdHealthy: false,
        dtdRegistrationConflict:
            dtdHealth['dtdRegistrationConflict'] as bool? ?? false,
        dtdStatusMessage: dtdHealth['dtdStatusMessage'] as String? ??
            'DTD rohd.queryModule failed: $e',
      );
    }
  }

  /// Refresh module info using the local in-memory FLC client.
  ///
  /// This is the fallback when DTD cannot perform host-side file checks, for
  /// example when the running ROHD app has not written an FLC sidecar file.
  Future<RohdModuleInfo?> _refreshModuleInfoLocally(
    String module, {
    String? dtdStatusMessage,
  }) async {
    final client = _extensionClient;
    if (client == null) {
      return null;
    }

    List<String>? instancePath;
    final hierarchyState = _hierarchyCubit.state;
    if (hierarchyState is HierarchyLoaded) {
      final selectedModule =
          hierarchyState.selectedModule ?? hierarchyState.root;
      instancePath = selectedModule.path().split('/');
    }

    final localInfo = await client.queryModule(
      module,
      instancePath: instancePath,
    );
    return RohdModuleInfo(
      extensionAvailable: localInfo.extensionAvailable,
      module: localInfo.module,
      formats: localInfo.formats,
      error: localInfo.error,
      dtdHealthy: true,
      dtdStatusMessage: dtdStatusMessage,
      fstLoading: localInfo.fstLoading,
    );
  }

  static const Set<String> _requiredRohdDtdMethods = {
    'goToSource',
    'resolveFrames',
    'queryModule',
    'lookupSignal',
  };

  static const String _rohdDtdBridgeCapabilityKey = 'rohdDtdBridge';
  static const int _rohdDtdBridgeCapabilityVersion = 1;

  /// Inspect live DTD service registration state without claiming ownership.
  ///
  /// This detects the common stale-window failure mode where `rohd` is already
  /// registered by another client.  New bridge owners advertise a capability
  /// marker; an owner without it is treated as suspect so the UI can warn while
  /// the failing DTD state is still live.
  Future<Map<String, dynamic>> _inspectRohdDtdService(
    DartToolingDaemon dtd,
  ) async {
    try {
      debugPrint('[CrossProbe] Inspecting DTD rohd service registration');
      final services = await dtd.getRegisteredServices().timeout(
            const Duration(milliseconds: 900),
          );
      final rohdServices = services.clientServices.where(
        (service) => service.name == 'rohd',
      );
      if (rohdServices.isEmpty) {
        return const {
          'dtdHealthy': false,
          'dtdStatusMessage': 'DTD service rohd is not registered.',
        };
      }

      final service = rohdServices.first;
      final methods = service.methods;
      final missingMethods = _requiredRohdDtdMethods
          .where((method) => !methods.containsKey(method))
          .toList();
      final ownerHasBridgeCapability = methods.values.any((method) {
        final capabilities = method.capabilities;
        return capabilities != null &&
            capabilities[_rohdDtdBridgeCapabilityKey] ==
                _rohdDtdBridgeCapabilityVersion;
      });

      if (missingMethods.isNotEmpty) {
        return {
          'dtdHealthy': false,
          'dtdRegistrationConflict': !ownerHasBridgeCapability,
          'dtdStatusMessage': 'DTD service rohd is missing method(s): '
              '${missingMethods.join(', ')}.',
        };
      }

      if (!ownerHasBridgeCapability) {
        // All required methods are present, but the owner does not advertise
        // the bridge capability marker. Older/legacy ROHD extensions register
        // the service without the marker, so treat this as a healthy (legacy)
        // owner rather than a conflict. The capability marker is a positive
        // confirmation signal, not a hard requirement — gating on it produced
        // false "registration conflict" reports during normal DTD churn.
        return const {
          'dtdHealthy': true,
          'dtdRegistrationConflict': false,
          'dtdStatusMessage':
              'DTD service rohd is registered by a ROHD bridge (legacy owner '
                  'without capability marker).',
        };
      }

      return const {
        'dtdHealthy': true,
        'dtdRegistrationConflict': false,
        'dtdStatusMessage':
            'DTD service rohd is registered by the ROHD bridge.',
      };
    } on Exception catch (e) {
      final rohdKnownRegistered = isServiceAvailable('rohd');
      debugPrint(
        '[CrossProbe] DTD service inspection failed: $e '
        '(cached rohd=$rohdKnownRegistered)',
      );
      return {
        'dtdHealthy': false,
        if (rohdKnownRegistered) 'dtdRegistrationConflict': true,
        'dtdStatusMessage': rohdKnownRegistered
            ? 'DTD service rohd is registered, but this DevTools app could '
                'not inspect its owner. This often indicates a stale or '
                'mismatched DTD service owner.'
            : 'Could not inspect DTD services: $e',
      };
    }
  }

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
    // For output languages (SystemVerilog, SystemC) the FLC lists each
    // signal's frames declaration-first followed by every assignment/driver
    // in source order.  Present them last-driver-first so the most recent
    // assignment is at the top of the picker and the declaration is last.
    // ROHD (Dart) frames keep their outermost-first ordering.
    final isOutputLanguage =
        format == RohdSourceFormat.sv || format == RohdSourceFormat.sc;
    final ordered = isOutputLanguage ? filtered.reversed.toList() : filtered;

    final selectedIndex = await showSourceFramePicker(context, ordered);
    if (selectedIndex == null) {
      return;
    }
    await nav.navigateToFormat(ordered, selectedIndex, format);
  }

  /// Eagerly expand a module's connectivity (slim → full JSON) so that
  /// [_evaluateForDetailsPane] can compute internal signal values.
  ///
  /// Called from [SignalDetailsCard] when the internals toggle is activated.
  /// Expands both the selected module and all of its immediate child modules
  /// (whose cell definitions may still be slim), since internal signals are
  /// often ports routed through child instances.
  Future<void> _expandModuleForDetailsPane(String moduleInstancePath) async {
    final api = _waveformApi;
    Future<bool> Function(String)? expandFn;
    if (api is VmServiceSignalWaveformApi && api.fetchModuleSchematic != null) {
      expandFn = api.ensureFullModules;
    } else if (api is LoopbackSignalWaveformApi &&
        api.fetchModuleSchematic != null) {
      expandFn = api.ensureFullModules;
    }
    if (expandFn == null) {
      return;
    }

    var anyExpanded = false;

    // 1. Expand the selected module itself.
    final syntheticSignalPath = '$moduleInstancePath/_dummy';
    if (await expandFn(syntheticSignalPath)) {
      anyExpanded = true;
    }

    // 2. Expand all immediate child module definitions.
    //    Walk the cells of the selected module's definition to find child
    //    types that are still slim, then expand each one.
    final modules = _schematicJson?['modules'] as Map<String, dynamic>?;
    if (modules != null) {
      final childPaths = _childInstancePaths(moduleInstancePath, modules);
      for (final childPath in childPaths) {
        final childSynthetic = '$childPath/_dummy';
        if (await expandFn(childSynthetic)) {
          anyExpanded = true;
        }
      }
    }

    if (anyExpanded && mounted) {
      _sharedEvaluator = null;
      _evalCache.reset(); // full reset — discard stale module indices too
      setState(() {});
    }
  }

  /// Return instance paths for all immediate children of [moduleInstancePath]
  /// whose module definitions are still slim.
  List<String> _childInstancePaths(
    String moduleInstancePath,
    Map<String, dynamic> modules,
  ) {
    // Resolve the module definition key for [moduleInstancePath].
    final parts = moduleInstancePath.split('/');
    String? topKey;
    for (final e in modules.entries) {
      final attrs = (e.value as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>?;
      if (attrs?['top'] == 1) {
        topKey = e.key;
        break;
      }
    }
    topKey ??= modules.keys.isNotEmpty ? modules.keys.first : null;
    if (topKey == null) {
      return const [];
    }

    // Walk path to find the target module's definition.
    var defName = topKey;
    for (var i = 1; i < parts.length; i++) {
      final cellName = parts[i];
      final modData = modules[defName] as Map<String, dynamic>?;
      if (modData == null) {
        return const [];
      }
      final cells = modData['cells'] as Map<String, dynamic>? ?? {};
      final cell = cells[cellName] as Map<String, dynamic>?;
      final nextType = cell?['type'] as String?;
      if (nextType == null || !modules.containsKey(nextType)) {
        return const [];
      }
      defName = nextType;
    }

    // Now enumerate the children of [defName].
    final modData = modules[defName] as Map<String, dynamic>?;
    if (modData == null) {
      return const [];
    }
    final cells = modData['cells'] as Map<String, dynamic>? ?? {};
    final result = <String>[];
    for (final entry in cells.entries) {
      final cell = entry.value as Map<String, dynamic>;
      final childType = cell['type'] as String?;
      if (childType == null) {
        continue;
      }
      final childDef = modules[childType] as Map<String, dynamic>?;
      if (childDef != null && BaseSignalWaveformApi.isSlimModule(childDef)) {
        result.add('$moduleInstancePath/${entry.key}');
      }
    }
    return result;
  }

  /// Fallback value evaluator for the details-pane signal table.
  ///
  /// Follows the same protocol as [_buildSignalValueLookup] (schematic hover):
  ///  1. Try the snapshot (direct match, then leaf-name match).  If the
  ///     signal is present its value is authoritative — even 'x' (which
  ///     is a valid simulation value meaning unknown / don't-care).
  ///  2. Evaluate on-demand via the client-side Yosys netlist for signals
  ///     absent from the snapshot (untracked / computed gate outputs).
  ///  3. If the module is slim, schedule async expansion.
  ({String value, bool computed})? _evaluateForDetailsPane(String signalPath) {
    final snapshotState = _snapshotCubit.state;
    if (snapshotState is! SnapshotLoaded) {
      return null;
    }

    // Clear resolved-value cache when the snapshot time changes.
    final snapTime = snapshotState.time;
    if (snapTime != _evalCacheSnapshotTime) {
      _evalCache.clear();
      _evalCacheSnapshotTime = snapTime;
    }

    // Derive the selected module's instance path so we can re-root
    // definition-based signal paths to instance-based snapshot keys
    // (mirrors hover steps 2 & 3 in [_buildSignalValueLookup]).
    final hierState = _hierarchyCubit.state;
    final modulePath = hierState is HierarchyLoaded
        ? (hierState.selectedModule?.path() ?? hierState.root.path())
        : null;

    // ── 1. Snapshot lookup (mirrors hover steps 1–4) ──
    // Presence in the snapshot means the value is authoritative.
    final exact = snapshotState.getSignal(signalPath);
    if (exact != null) {
      return (value: exact.value, computed: exact.computed);
    }

    // 1b. Re-root: replace the first segment (definition/type name) with
    //     the instance path so the key matches the snapshot.
    //     Skip when signalPath is already an absolute instance path
    //     (starts with the hierarchy root's ID), otherwise re-rooting
    //     duplicates segments (e.g. root/adder0/sig → root/adder0/adder0/sig).
    String? rerooted;
    final rootId = hierState is HierarchyLoaded ? hierState.root.path() : null;
    final alreadyAbsolute = rootId != null && signalPath.startsWith('$rootId/');
    if (modulePath != null && signalPath.contains('/') && !alreadyAbsolute) {
      final slash = signalPath.indexOf('/');
      final rest = signalPath.substring(slash); // includes leading '/'
      rerooted = '$modulePath$rest';
      final byReroot = snapshotState.getSignal(rerooted);
      if (byReroot != null) {
        return (value: byReroot.value, computed: byReroot.computed);
      }
    }

    // 1c. Bare leaf name → prepend modulePath.
    if (modulePath != null && !signalPath.contains('/')) {
      final qualified = '$modulePath/$signalPath';
      final byQualified = snapshotState.getSignal(qualified);
      if (byQualified != null) {
        return (value: byQualified.value, computed: byQualified.computed);
      }
    }

    // 1d. Leaf-name match (last resort for snapshot).
    final leafName = signalPath.contains('/')
        ? signalPath.substring(signalPath.lastIndexOf('/') + 1)
        : signalPath;
    final byName = snapshotState.getSignalByName(leafName);
    if (byName != null) {
      return (value: byName.value, computed: byName.computed);
    }

    // ── 2. On-demand evaluation via client-side Yosys netlist ──
    // Signal is absent from the snapshot (untracked).  Evaluate locally.
    // Use the re-rooted path when available so the evaluator resolves
    // against instance-keyed module data.
    final evalPath = rerooted ?? signalPath;

    String? Function(String) snapshotLookup(SnapshotLoaded snap) =>
        (fullPath) => snap.getSignal(fullPath)?.value;

    final eval = _getSharedEvaluator();
    if (eval != null) {
      final r = eval.evaluate(evalPath, snapshotLookup(snapshotState));
      if (r != null) {
        return (value: r.value, computed: true);
      }
    }

    // ── 3. Module may be slim — schedule async expansion ──
    _maybeExpandModuleForSignal(evalPath);
    return null;
  }

  /// Fire-and-forget expansion of the module(s) along [signalPath].
  ///
  /// Deduplicates by the module instance path (signal path minus the
  /// last segment) so that multiple signals in the same module produce
  /// only one expansion request.
  void _maybeExpandModuleForSignal(String signalPath) {
    // Extract the module instance path (everything before the signal name).
    final lastSlash = signalPath.lastIndexOf('/');
    final moduleKey =
        lastSlash > 0 ? signalPath.substring(0, lastSlash) : signalPath;
    if (_pendingModuleExpansions.contains(moduleKey)) {
      return;
    }

    final api = _waveformApi;
    Future<bool> Function(String)? expandFn;
    if (api is VmServiceSignalWaveformApi && api.fetchModuleSchematic != null) {
      expandFn = api.ensureFullModules;
    } else if (api is LoopbackSignalWaveformApi &&
        api.fetchModuleSchematic != null) {
      expandFn = api.ensureFullModules;
    }
    if (expandFn == null) {
      return;
    }

    _pendingModuleExpansions.add(moduleKey);
    unawaited(
      expandFn(signalPath).then((expanded) {
        _pendingModuleExpansions.remove(moduleKey);
        if (expanded && mounted) {
          // Modules were enriched in-place — invalidate the evaluator
          // so it re-walks the now-full module data, then rebuild.
          _sharedEvaluator = null;
          _evalCache.clear();
          debugPrint(
            '[DetailsPane] Module expanded for "$signalPath" — '
            'rebuilding',
          );
          setState(() {});
        }
      }).catchError((Object e) {
        _pendingModuleExpansions.remove(moduleKey);
        debugPrint(
          '[DetailsPane] Module expansion failed for '
          '"$signalPath": $e',
        );
      }),
    );
  }

  /// Build a signal value lookup callback from the current snapshot state.
  ///
  /// The schematic canvas now resolves wire / port names to fully-qualified
  /// hierarchy paths (e.g. `"top/adder0/sum"`) using scope metadata from the
  /// ELK layout.  The lookup therefore tries, in order:
  ///
  ///  1. Direct signal-ID match — the canvas already built the full path.
  ///  2. `modulePath/wireName` — fallback for the JS-first rendering path
  ///     or when the ELK metadata is absent.
  ///  3. Leaf-name match — last resort when neither of the above hits.
  ///
  /// Returns `null` when no snapshot is available.
  ({String value, bool computed, String signalId})? Function(String wireName)?
      _buildSignalValueLookup({String? modulePath}) {
    final snapshotState = _snapshotCubit.state;
    if (snapshotState is! SnapshotLoaded) {
      return null;
    }

    // ── Diagnostic: log snapshot summary once per lookup batch ──
    var dumpedKeys = false;

    ({String value, bool computed, String signalId}) hit(SignalSnapshot s) =>
        (value: s.value, computed: s.computed, signalId: s.signalId);

    return (String wireName) {
      if (!dumpedKeys) {
        dumpedKeys = true;
        var withValue = 0;
        var withX = 0;
        var computed = 0;
        for (final sig in snapshotState.signals.values) {
          if (sig.computed) {
            computed++;
          }
          if (sig.value == 'x' || sig.value.isEmpty) {
            withX++;
          } else {
            withValue++;
          }
        }
        debugPrint(
          '[SignalLookup] modulePath=$modulePath, '
          '${snapshotState.signals.length} signals '
          '($withValue valued, $withX x/empty, $computed computed)',
        );
      }

      // 1. Direct signal-ID match — works when the ELK hierarchy paths
      //    already use instance paths (matching snapshot keys exactly).
      final exact = snapshotState.getSignal(wireName);
      if (exact != null) {
        return hit(exact);
      }

      // 2. Re-root: the canvas sends paths rooted at the Yosys **type
      //    name** (e.g. "FloatingPointAdderDualPath_E8M23/sub/sum"),
      //    but snapshot keys use **instance paths**
      //    (e.g. "top/adder0/sub/sum").
      //    Replace the first segment with `modulePath`.
      if (modulePath != null && wireName.contains('/')) {
        final slash = wireName.indexOf('/');
        final rest = wireName.substring(slash); // includes leading '/'
        final rerooted = '$modulePath$rest';
        final byId = snapshotState.getSignal(rerooted);
        if (byId != null) {
          return hit(byId);
        }
      }

      // 3. Bare leaf name → prepend modulePath.
      if (modulePath != null && !wireName.contains('/')) {
        final qualifiedId = '$modulePath/$wireName';
        final byId = snapshotState.getSignal(qualifiedId);
        if (byId != null) {
          return hit(byId);
        }
      }

      // 4. Fall back to leaf-name match (works for top-level or when the
      //    qualified path doesn't match, e.g. hyperedge aliases).
      final leafName = wireName.contains('/')
          ? wireName.substring(wireName.lastIndexOf('/') + 1)
          : wireName;
      final byName = snapshotState.getSignalByName(leafName);
      if (byName != null) {
        return hit(byName);
      }

      // 5. On-demand evaluation via client-side Yosys netlist.
      //    The snapshot only contains tracked (recorded) signals.
      //    Computed signals (gate outputs) can be derived from the
      //    expanded netlist JSON that is already on the client.

      // Build a re-rooted path the evaluator understands.
      String? evalPath;
      if (modulePath != null && wireName.contains('/')) {
        final slash = wireName.indexOf('/');
        evalPath = '$modulePath${wireName.substring(slash)}';
      } else if (modulePath != null) {
        evalPath = '$modulePath/$wireName';
      }

      if (evalPath != null) {
        String? Function(String) snapLookup(SnapshotLoaded snap) =>
            (fullPath) => snap.getSignal(fullPath)?.value;

        // Try the shared evaluator (full cross-module resolution).
        final eval = _getSharedEvaluator();
        if (eval != null) {
          final r = eval.evaluate(evalPath, snapLookup(snapshotState));
          if (r != null) {
            return (value: r.value, computed: true, signalId: evalPath);
          }
        }

        // Evaluation failed — module may be slim.  Schedule expansion.
        _maybeExpandModuleForSignal(evalPath);
      }

      return null;
    };
  }
}

// Pre-defined colors to avoid recreating on each build
const _connectedColor = Color(0x3300FF00); // green with alpha
const _loopbackColor = Color(0x332196F3); // blue with alpha
const _disconnectedColor = Color(0x33FF0000); // red with alpha
const _connectingColor = Color(0x33FFB74D); // amber with alpha
const _pausedColor = Color(0x33FF9800); // orange with alpha
const _connectedTextColor = Color(0xFF81C784); // Colors.green.shade300
const _loopbackTextColor = Color(0xFF64B5F6); // Colors.blue.shade300
const _disconnectedTextColor = Color(0xFFE57373); // Colors.red.shade300
const _connectingTextColor = Color(0xFFFFB74D); // Colors.amber.shade300
const _pausedTextColor = Color(0xFFFFB74D); // Colors.amber.shade300

/// Separate AppBar widget to isolate hover effects from body rebuilds.
class _StandaloneAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final bool isLoopbackMode;
  final bool isVmConnected;
  final bool isConnecting;
  final bool isVmDead;
  final bool isPaused;
  final int selectedExampleIndex;
  final List<DropdownMenuItem<int>> exampleDropdownItems;
  final ValueChanged<int?> onExampleChanged;
  final VoidCallback onDisconnect;
  final VoidCallback onConnect;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRefresh;
  final VoidCallback onLicenses;
  final VoidCallback onLoadDesign;
  final VoidCallback onLoadWaveform;
  final bool hasLoadedDesign;
  final String? loadedDesignName;
  final bool canConnect;
  final bool hasColorEmoji;
  final RohdExtensionClient? _extensionClient;
  final DevToolsHierarchyCubit? _hierarchyCubit;

  /// Optional callback to refresh module info with file-existence checks
  /// via DTD.  Called when the crossprobe icon is clicked.
  final Future<RohdModuleInfo?> Function(String module)? _onRefreshModuleInfo;

  const _StandaloneAppBar({
    required this.title,
    required this.isLoopbackMode,
    required this.isVmConnected,
    required this.isConnecting,
    required this.isVmDead,
    required this.isPaused,
    required this.selectedExampleIndex,
    required this.exampleDropdownItems,
    required this.onExampleChanged,
    required this.onDisconnect,
    required this.onConnect,
    required this.onPause,
    required this.onResume,
    required this.onRefresh,
    required this.onLicenses,
    required this.onLoadDesign,
    required this.onLoadWaveform,
    required this.hasLoadedDesign,
    required this.canConnect,
    required this.hasColorEmoji,
    this.loadedDesignName,
    RohdExtensionClient? extensionClient,
    DevToolsHierarchyCubit? hierarchyCubit,
    Future<RohdModuleInfo?> Function(String module)? onRefreshModuleInfo,
  })  : _extensionClient = extensionClient,
        _hierarchyCubit = hierarchyCubit,
        _onRefreshModuleInfo = onRefreshModuleInfo;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('title', title))
      ..add(
        FlagProperty(
          'isLoopbackMode',
          value: isLoopbackMode,
          ifFalse: 'VM connected',
        ),
      )
      ..add(
        FlagProperty(
          'isVmConnected',
          value: isVmConnected,
          ifFalse: 'loopback mode',
        ),
      )
      ..add(
        FlagProperty('isConnecting', value: isConnecting, ifTrue: 'connecting'),
      )
      ..add(FlagProperty('isVmDead', value: isVmDead, ifTrue: 'VM dead'))
      ..add(FlagProperty('isPaused', value: isPaused, ifTrue: 'paused'))
      ..add(IntProperty('selectedExampleIndex', selectedExampleIndex))
      ..add(
        IterableProperty<DropdownMenuItem<int>>(
          'exampleDropdownItems',
          exampleDropdownItems,
        ),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<int?>>(
          'onExampleChanged',
          onExampleChanged,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onDisconnect',
          onDisconnect,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onConnect',
          onConnect,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onPause',
          onPause,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onResume',
          onResume,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onRefresh',
          onRefresh,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onLicenses',
          onLicenses,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onLoadDesign',
          onLoadDesign,
          ifNull: 'disabled',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback>(
          'onLoadWaveform',
          onLoadWaveform,
          ifNull: 'disabled',
        ),
      )
      ..add(
        FlagProperty(
          'hasLoadedDesign',
          value: hasLoadedDesign,
          ifTrue: 'design loaded',
        ),
      )
      ..add(StringProperty('loadedDesignName', loadedDesignName))
      ..add(
        FlagProperty(
          'canConnect',
          value: canConnect,
          ifFalse: 'cannot connect',
        ),
      )
      ..add(
        FlagProperty(
          'hasColorEmoji',
          value: hasColorEmoji,
          ifFalse: 'fallback emojis',
        ),
      );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<_StandaloneAppBar> createState() => _StandaloneAppBarState();
}

class _StandaloneAppBarState extends State<_StandaloneAppBar> {
  // Cache background color to avoid Theme.of(context) on every build
  Color? _backgroundColor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _backgroundColor = Theme.of(context).colorScheme.onPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      backgroundColor: _backgroundColor,
      title: Text(widget.title),
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'assets/rohd_icon.png',
          width: 28,
          height: 28,
          fit: BoxFit.contain,
        ),
      ),
      actions: [
        // Example selector
        if (widget.isLoopbackMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButton<int>(
              value: widget.selectedExampleIndex,
              underline: const SizedBox(),
              dropdownColor: isDark ? const Color(0xFF3C3C3C) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
              items: widget.exampleDropdownItems,
              onChanged: widget.onExampleChanged,
            ),
          ),
        // Load Design button (loopback mode only)
        if (widget.isLoopbackMode)
          Tooltip(
            message: 'Load design JSON file',
            child: TextButton.icon(
              onPressed: widget.onLoadDesign,
              icon: platformIcon(
                Icons.folder_open,
                '📂',
                size: 18,
                hasColorEmoji: widget.hasColorEmoji,
              ),
              label: Text(
                'Load Design',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
        // Load Waveform button (loopback mode, only after design is loaded)
        if (widget.isLoopbackMode && widget.hasLoadedDesign)
          Tooltip(
            message: 'Load VCD/FST/GHW waveform file',
            child: TextButton.icon(
              onPressed: widget.onLoadWaveform,
              icon: platformIcon(
                Icons.show_chart,
                '📊',
                size: 18,
                hasColorEmoji: widget.hasColorEmoji,
              ),
              label: Text(
                'Load Waveform',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
        // Connection status badge — reflects actual connection state
        if (widget.isVmDead)
          _ConnectionStatusBadge(
            color: _disconnectedColor,
            icon: Icons.cancel,
            emoji: '❌',
            iconColor: Colors.red,
            label: 'VM Ended',
            textColor: _disconnectedTextColor,
            hasColorEmoji: widget.hasColorEmoji,
          )
        else if (widget.isConnecting)
          _ConnectionStatusBadge(
            color: _connectingColor,
            icon: Icons.sync,
            emoji: '⏳',
            iconColor: Colors.amber,
            label: 'Connecting…',
            textColor: _connectingTextColor,
            hasColorEmoji: widget.hasColorEmoji,
          )
        else if (widget.isPaused)
          _ConnectionStatusBadge(
            color: _pausedColor,
            icon: Icons.pause_circle,
            emoji: '⏸️',
            iconColor: Colors.orange,
            label: 'Paused',
            textColor: _pausedTextColor,
            hasColorEmoji: widget.hasColorEmoji,
          )
        else if (widget.isVmConnected)
          _ConnectionStatusBadge(
            color: _connectedColor,
            icon: Icons.check_circle,
            emoji: '✅',
            iconColor: Colors.green,
            label: 'Connected',
            textColor: _connectedTextColor,
            hasColorEmoji: widget.hasColorEmoji,
          )
        else
          _ConnectionStatusBadge(
            color: _loopbackColor,
            icon: Icons.developer_mode,
            emoji: '🔄',
            iconColor: Colors.blue,
            label: widget.hasLoadedDesign && widget.loadedDesignName != null
                ? 'Loopback: ${widget.loadedDesignName}'
                : 'Loopback Mode',
            textColor: _loopbackTextColor,
            hasColorEmoji: widget.hasColorEmoji,
          ),
        // Connect button is always available so users can force reconnect.
        if (widget.canConnect)
          IconButton(
            icon: platformIcon(
              Icons.link,
              '🔗',
              size: 24,
              hasColorEmoji: widget.hasColorEmoji,
            ),
            onPressed: widget.onConnect,
            tooltip: widget.isVmConnected
                ? 'Reconnect / switch VM connection'
                : 'Connect to VM',
          ),

        // Pause / Resume waveform updates (shown only when connection is live
        // or currently paused).
        if (widget.canConnect &&
            ((widget.isVmConnected && !widget.isVmDead) || widget.isPaused))
          IconButton(
            icon: platformIcon(
              widget.isPaused ? Icons.play_arrow : Icons.pause,
              widget.isPaused ? '▶️' : '⏸️',
              size: 24,
              hasColorEmoji: widget.hasColorEmoji,
            ),
            onPressed: widget.isPaused ? widget.onResume : widget.onPause,
            tooltip: widget.isPaused
                ? 'Resume waveform updates'
                : 'Pause waveform updates (keeps connection alive)',
          ),
        IconButton(
          icon: platformIcon(
            Icons.refresh,
            '🔃',
            size: 24,
            hasColorEmoji: widget.hasColorEmoji,
          ),
          onPressed: widget.onRefresh,
          tooltip: 'Refresh',
        ),
        // Help button
        DevToolsHelpButton(isDark: isDark),
        // Licenses button
        TextButton(
          onPressed: widget.onLicenses,
          child: Text(
            'Licenses',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
        ),
        // Cross-probe status icon: lit when extension is reachable,
        // click shows available source formats for the current module.
        if (widget._extensionClient != null)
          _CrossProbeStatusButton(
            extensionClient: widget._extensionClient!,
            hierarchyCubit: widget._hierarchyCubit,
            onRefreshModuleInfo: widget._onRefreshModuleInfo,
          ),
        // Theme toggle button
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
                  hasColorEmoji: widget.hasColorEmoji,
                ),
                onPressed: () {
                  context.read<DevToolsThemeCubit>().toggleTheme();
                },
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// Const-constructible connection status badge.
class _ConnectionStatusBadge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String emoji;
  final Color iconColor;
  final String label;
  final Color textColor;
  final bool hasColorEmoji;

  const _ConnectionStatusBadge({
    required this.color,
    required this.icon,
    required this.emoji,
    required this.iconColor,
    required this.label,
    required this.textColor,
    required this.hasColorEmoji,
  });

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(DiagnosticsProperty<IconData>('icon', icon))
      ..add(ColorProperty('iconColor', iconColor))
      ..add(StringProperty('emoji', emoji))
      ..add(StringProperty('label', label))
      ..add(ColorProperty('textColor', textColor))
      ..add(
        FlagProperty(
          'hasColorEmoji',
          value: hasColorEmoji,
          ifFalse: 'fallback emojis',
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            platformIcon(
              icon,
              emoji,
              color: iconColor,
              size: 16,
              hasColorEmoji: hasColorEmoji,
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12, color: textColor)),
          ],
        ),
      );
}

/// App bar button that shows cross-probe availability.
///
/// The icon is lit (full opacity) when the extension client reports available
/// true, and dim otherwise.  Tapping it opens a small popup menu listing the
/// source formats available for the currently-selected module.
class _CrossProbeStatusButton extends StatefulWidget {
  final RohdExtensionClient _extensionClient;
  final DevToolsHierarchyCubit? _hierarchyCubit;

  /// Optional callback to refresh module info with file-existence checks
  /// (e.g. via DTD).  When provided, clicking the icon triggers a fresh
  /// sanity check before showing the popup.
  final Future<RohdModuleInfo?> Function(String module)? _onRefreshModuleInfo;

  const _CrossProbeStatusButton({
    required RohdExtensionClient extensionClient,
    DevToolsHierarchyCubit? hierarchyCubit,
    Future<RohdModuleInfo?> Function(String module)? onRefreshModuleInfo,
  })  : _extensionClient = extensionClient,
        _hierarchyCubit = hierarchyCubit,
        _onRefreshModuleInfo = onRefreshModuleInfo;

  @override
  State<_CrossProbeStatusButton> createState() =>
      _CrossProbeStatusButtonState();
}

class _CrossProbeStatusButtonState extends State<_CrossProbeStatusButton> {
  bool _isAvailable = false;
  RohdModuleInfo? _moduleInfo;
  String? _treeModuleName;
  StreamSubscription<DevToolsHierarchyState>? _cubitsub;

  @override
  void initState() {
    super.initState();
    _isAvailable = widget._extensionClient.isAvailable.value;
    _moduleInfo = widget._extensionClient.currentModuleInfo.value;
    widget._extensionClient.isAvailable.addListener(_onAvailableChanged);
    widget._extensionClient.currentModuleInfo.addListener(_onModuleInfoChanged);
    _cubitsub = widget._hierarchyCubit?.stream.listen(_onCubitState);
    // Seed from current cubit state.
    final cur = widget._hierarchyCubit?.state;
    if (cur is HierarchyLoaded) {
      final mod = cur.selectedModule ?? cur.root;
      _treeModuleName = mod.definition ?? mod.name;
    }
  }

  @override
  void didUpdateWidget(_CrossProbeStatusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._extensionClient != widget._extensionClient) {
      oldWidget._extensionClient.isAvailable.removeListener(
        _onAvailableChanged,
      );
      oldWidget._extensionClient.currentModuleInfo.removeListener(
        _onModuleInfoChanged,
      );
      widget._extensionClient.isAvailable.addListener(_onAvailableChanged);
      widget._extensionClient.currentModuleInfo.addListener(
        _onModuleInfoChanged,
      );
      _isAvailable = widget._extensionClient.isAvailable.value;
      _moduleInfo = widget._extensionClient.currentModuleInfo.value;
    }
  }

  @override
  void dispose() {
    widget._extensionClient.isAvailable.removeListener(_onAvailableChanged);
    widget._extensionClient.currentModuleInfo.removeListener(
      _onModuleInfoChanged,
    );
    unawaited(_cubitsub?.cancel());
    super.dispose();
  }

  void _onCubitState(DevToolsHierarchyState state) {
    if (!mounted) {
      return;
    }
    if (state is HierarchyLoaded) {
      final mod = state.selectedModule ?? state.root;
      final name = mod.definition ?? mod.name;
      if (name != _treeModuleName) {
        setState(() => _treeModuleName = name);
      }
    } else {
      if (_treeModuleName != null) {
        setState(() => _treeModuleName = null);
      }
    }
  }

  void _onAvailableChanged() {
    if (mounted) {
      setState(() => _isAvailable = widget._extensionClient.isAvailable.value);
    }
  }

  void _onModuleInfoChanged() {
    if (mounted) {
      setState(
        () => _moduleInfo = widget._extensionClient.currentModuleInfo.value,
      );
    }
  }

  static const _formatLabel = {
    RohdSourceFormat.rohd: ('ROHD Dart Source', Icons.code),
    RohdSourceFormat.sv: ('SystemVerilog', Icons.developer_board),
    RohdSourceFormat.sc: ('SystemC', Icons.memory),
    RohdSourceFormat.fst: ('FST Waveform', Icons.show_chart),
  };

  Future<void> _showFormatsMenu(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderBox.localToGlobal(Offset.zero, ancestor: overlay),
        renderBox.localToGlobal(
          renderBox.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    // If a refresh callback is available and we have a module name,
    // do a fresh DTD query with file-existence checks before showing
    // the menu.
    final module = _treeModuleName ?? _moduleInfo?.module;
    var info = _moduleInfo;
    if (module != null && widget._onRefreshModuleInfo != null) {
      debugPrint('[CrossProbe] Refreshing module info for "$module" via DTD');
      try {
        final freshInfo = await widget._onRefreshModuleInfo!(module);
        if (freshInfo != null && mounted) {
          info = freshInfo;
          setState(() => _moduleInfo = freshInfo);
          // Also update the extension client's notifier so other
          // consumers see the refreshed data.
          widget._extensionClient.currentModuleInfo.value = freshInfo;
        }
      } on Exception catch (e) {
        debugPrint('[CrossProbe] DTD refresh failed: $e');
        // Fall through — show whatever we have cached.
      }
    }

    if (!mounted) {
      return;
    }

    final items = <PopupMenuEntry<String>>[];
    final dtdWarning = info?.dtdHealthy == false;

    if (!_isAvailable) {
      items.add(
        const PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            'Extension not reachable',
            style: TextStyle(fontSize: 13, color: Colors.red),
          ),
        ),
      );
    } else if (_treeModuleName == null && info == null) {
      items.add(
        const PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text('No module selected', style: TextStyle(fontSize: 13)),
        ),
      );
    } else {
      if (dtdWarning) {
        final message = info?.dtdStatusMessage ?? 'DTD service health unknown';
        items
          ..add(
            PopupMenuItem<String>(
              enabled: false,
              height: 40,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          )
          ..add(const PopupMenuDivider(height: 6));
      }

      // Show the tree-selected module name (preferred) or schematic-selected.
      final displayName = _treeModuleName ?? info?.module;
      if (displayName != null) {
        items
          ..add(
            PopupMenuItem<String>(
              enabled: false,
              height: 28,
              child: Text(
                'Module: $displayName',
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          )
          ..add(const PopupMenuDivider(height: 6));
      }

      final availableFormats = RohdSourceFormat.values
          .where((f) => info?.formats[f]?.available ?? false)
          .toList();

      if (availableFormats.isEmpty) {
        items.add(
          const PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text(
              'No source formats available',
              style: TextStyle(fontSize: 13),
            ),
          ),
        );
      } else {
        for (final fmt in availableFormats) {
          final (label, _) =
              _formatLabel[fmt] ?? (fmt.name.toUpperCase(), Icons.description);
          final fmtInfo = info?.formats[fmt];
          final fileFound = fmtInfo?.fileFound ?? true;
          final filePath = fmtInfo?.path;

          // Show a short path: last 2 segments (e.g. "build/Foo.sv").
          String? shortPath;
          if (filePath != null) {
            final segments = filePath.split('/');
            shortPath = segments.length > 2
                ? '…/${segments.sublist(segments.length - 2).join('/')}'
                : filePath;
          }

          items.add(
            PopupMenuItem<String>(
              enabled: false,
              height: 32,
              child: Tooltip(
                message: filePath ?? '',
                waitDuration: const Duration(milliseconds: 300),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: fileFound ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(label, style: const TextStyle(fontSize: 13)),
                    if (!fileFound) ...[
                      const SizedBox(width: 4),
                      const Text(
                        '(missing)',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ],
                    if (shortPath != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          shortPath,
                          style: TextStyle(
                            fontSize: 10,
                            color: fileFound
                                ? Colors.grey
                                : Colors.orange.shade300,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        if (info?.error != null) {
          items
            ..add(const PopupMenuDivider(height: 6))
            ..add(
              PopupMenuItem<String>(
                enabled: false,
                height: 32,
                child: Text(
                  'Error: ${info!.error}',
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
        }
      }
    }

    if (!mounted) {
      return;
    }

    unawaited(
      showMenu<String>(
        // The method checks [mounted] immediately before opening this menu.
        // ignore: use_build_context_synchronously
        context: context,
        position: position,
        items: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableColor = isDark ? Colors.lightBlueAccent : Colors.blue;
    final warningColor = isDark ? Colors.orangeAccent : Colors.deepOrange;
    final unavailableColor = isDark ? Colors.white24 : Colors.black26;
    final dtdWarning = _moduleInfo?.dtdHealthy == false;

    return Tooltip(
      message: dtdWarning
          ? 'Source cross-probe: DTD service conflict detected'
          : _isAvailable
              ? 'Source cross-probe: available — click to see formats'
              : 'Source cross-probe: extension not reachable',
      child: Opacity(
        opacity: _isAvailable || dtdWarning ? 1.0 : 0.35,
        child: IconButton(
          icon: Icon(
            dtdWarning ? Icons.warning_amber : Icons.swap_horiz,
            color: dtdWarning
                ? warningColor
                : _isAvailable
                    ? availableColor
                    : unavailableColor,
          ),
          onPressed: () => _showFormatsMenu(context),
          iconSize: 24,
        ),
      ),
    );
  }
}
