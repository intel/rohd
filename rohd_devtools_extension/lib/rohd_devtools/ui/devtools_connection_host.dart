// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_connection_host.dart
// Abstract base class for DevTools app shells that manage VM/DTD connection
// lifecycle.  Subclasses provide app-specific data loading and UI.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/dtd_vm_service_info.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/ui.dart';
import 'package:vm_service/vm_service.dart' hide Stack;

/// Discover the VM services currently advertised by a DTD endpoint.
///
/// If [onRegisteredServices] is provided, it is invoked with the set of
/// currently registered DTD client service names before VM service discovery
/// completes.
Future<List<DiscoveredVmService>> discoverVmServicesViaDtd(
  String dtdUri, {
  void Function(Set<String> serviceNames)? onRegisteredServices,
}) async {
  debugPrint('[ConnectionHost] Connecting to DTD at: $dtdUri');
  final dtd = await DartToolingDaemon.connect(Uri.parse(dtdUri));

  try {
    if (onRegisteredServices != null) {
      try {
        final registered = await dtd.getRegisteredServices();
        final serviceNames = <String>{
          for (final svc in registered.clientServices) svc.name,
        };
        onRegisteredServices(serviceNames);
        debugPrint('[ConnectionHost] Registered services: $serviceNames');
      } on Exception catch (e) {
        debugPrint('[ConnectionHost] getRegisteredServices failed: $e');
      }
    }

    final response = await dtd.getVmServices();
    final services = response.vmServicesInfos;

    debugPrint('[ConnectionHost] Found ${services.length} VM service(s)');
    for (final svc in services) {
      debugPrint(
        '[ConnectionHost]   ${svc.name ?? "(unnamed)"}: '
        'uri=${svc.uri}, exposedUri=${svc.exposedUri}',
      );
    }

    return services
        .map(
          (svc) => DiscoveredVmService(
            name: svc.name,
            uri: svc.uri,
            exposedUri: svc.exposedUri,
          ),
        )
        .toList();
  } finally {
    await dtd.close();
  }
}

/// The resolved inputs for a user-driven connection attempt.
///
/// Carries the cleaned URI strings plus either the chosen VM service URI or
/// a user-facing validation error.
class VmConnectionAttemptResolution {
  /// The VM service URI to connect to, if resolution succeeded.
  final String? vmServiceUri;

  /// The cleaned VM service URI derived from the user's input.
  final String cleanedVmServiceUri;

  /// The cleaned DTD URI derived from the user's input.
  final String cleanedDtdUri;

  /// A user-facing validation or discovery error, when resolution fails.
  final String? error;

  /// Creates a resolved connection-attempt payload.
  const VmConnectionAttemptResolution({
    required this.vmServiceUri,
    required this.cleanedVmServiceUri,
    required this.cleanedDtdUri,
    this.error,
  });
}

/// Resolve a connection attempt from raw VM service and DTD URI inputs.
///
/// If the VM service URI is already valid, it is used directly. Otherwise the
/// DTD endpoint is queried via [discoverVmServices] and the first advertised VM
/// service is selected.
Future<VmConnectionAttemptResolution> resolveVmConnectionAttempt({
  required String rawVmServiceUri,
  required String rawDtdUri,
  required Future<List<DiscoveredVmService>> Function(String dtdUri)
      discoverVmServices,
}) async {
  final vmServiceUri = DevToolsConnectionHostState.cleanVmServiceUri(
    rawVmServiceUri,
  );
  var dtdUri = '';
  if (rawDtdUri.isNotEmpty) {
    dtdUri = DevToolsConnectionHostState.cleanDtdUri(rawDtdUri);
  }

  final hasVmUri = vmServiceUri.isNotEmpty &&
      vmServiceUri.startsWith('ws') &&
      !vmServiceUri.contains('xxxx');
  final hasDtdUri = dtdUri.isNotEmpty && dtdUri.startsWith('ws');

  if (!hasVmUri && !hasDtdUri) {
    return VmConnectionAttemptResolution(
      vmServiceUri: null,
      cleanedVmServiceUri: vmServiceUri,
      cleanedDtdUri: dtdUri,
      error: 'Please enter a VM Service URI or DTD URI',
    );
  }

  if (hasVmUri) {
    return VmConnectionAttemptResolution(
      vmServiceUri: vmServiceUri,
      cleanedVmServiceUri: vmServiceUri,
      cleanedDtdUri: dtdUri,
    );
  }

  final services = await discoverVmServices(dtdUri);
  if (services.isEmpty) {
    return VmConnectionAttemptResolution(
      vmServiceUri: null,
      cleanedVmServiceUri: vmServiceUri,
      cleanedDtdUri: dtdUri,
      error: 'No VM services found via DTD. Is your ROHD app running?',
    );
  }

  return VmConnectionAttemptResolution(
    vmServiceUri: services.first.connectionUri,
    cleanedVmServiceUri: vmServiceUri,
    cleanedDtdUri: dtdUri,
  );
}

/// Whether a DTD VM lifecycle event refers to the VM currently tracked by the
/// host.
///
/// Matches against either the direct URI or the exposed URI reported by DTD.
bool dtdEventMatchesTrackedVm({
  required String? trackedVmUri,
  required String? eventUri,
  required String? eventExposedUri,
}) {
  bool matchesCandidate(String? candidate) {
    if (candidate == null || candidate.isEmpty) {
      return false;
    }
    if (trackedVmUri == null || trackedVmUri.isEmpty) {
      return true;
    }
    return trackedVmUri.contains(candidate) || candidate.contains(trackedVmUri);
  }

  if (trackedVmUri == null || trackedVmUri.isEmpty) {
    return true;
  }

  return matchesCandidate(eventUri) || matchesCandidate(eventExposedUri);
}

/// Return the preferred VM service URI carried by a DTD lifecycle event.
///
/// Prefers the externally connectable exposed URI when present, otherwise
/// falls back to the raw URI field.
String? preferredVmServiceUriFromDtdEvent(DTDEvent event) {
  final eventUri = event.data[DtdParameters.uri]?.toString();
  final eventExposedUri = event.data[DtdParameters.exposedUri]?.toString();
  if (eventExposedUri != null && eventExposedUri.isNotEmpty) {
    return eventExposedUri;
  }
  if (eventUri != null && eventUri.isNotEmpty) {
    return eventUri;
  }
  return null;
}

// ---------------------------------------------------------------------------
// VM Connection Strategy
// ---------------------------------------------------------------------------

/// Abstract base for VM connection strategies.
/// Linux uses vm_service_io, Web uses package:web WebSocket.
abstract class VmConnectionStrategy {
  /// Connect to VM service at the given URI.
  /// Returns the VmService and isolateId for the main isolate.
  Future<VmConnectionResult> connect(String uri);

  /// Normalize URI to websocket format.
  Uri? normalizeUri(String value) {
    try {
      var uri = Uri.parse(value.trim());

      if (uri.scheme == 'http') {
        uri = uri.replace(scheme: 'ws');
      } else if (uri.scheme == 'https') {
        uri = uri.replace(scheme: 'wss');
      }

      if (!uri.path.endsWith('/ws')) {
        uri = uri.replace(path: '${uri.path}ws');
      }

      return uri;
    } on Exception {
      return null;
    }
  }
}

/// Result of a VM connection attempt.
class VmConnectionResult {
  /// The connected VM service.
  final VmService vmService;

  /// The isolate ID of the main isolate.
  final String isolateId;

  /// Constructor for [VmConnectionResult].
  VmConnectionResult({required this.vmService, required this.isolateId});
}

/// Describes whether an attach is brand-new, a same-VM restart, or a
/// teardown for disconnect.
enum VmConnectionTransitionKind {
  /// A brand-new VM attachment with no preserved prior app state.
  freshAttach,

  /// A reconnect to the same logical VM after a restart.
  sameVmRestart,

  /// A teardown transition driven by explicit disconnect.
  disconnect,
}

/// Carries the previous VM identity into reconnect hooks so subclasses can
/// preserve app state only for same-VM restarts.
class VmConnectionTransition {
  /// The host-classified reconnect kind for this attach.
  final VmConnectionTransitionKind kind;

  /// The VM service URI that was attached before this transition.
  final String? previousUri;

  /// The isolate ID that was attached before this transition.
  final String? previousIsolateId;

  /// The last tracked VM name, when known.
  final String? previousVmName;

  /// Creates a transition with the given classification and prior identity.
  const VmConnectionTransition({
    required this.kind,
    this.previousUri,
    this.previousIsolateId,
    this.previousVmName,
  });

  /// Creates a fresh attach transition.
  const VmConnectionTransition.fresh()
      : this(kind: VmConnectionTransitionKind.freshAttach);

  /// Creates a same-VM restart transition.
  const VmConnectionTransition.sameVmRestart()
      : this(kind: VmConnectionTransitionKind.sameVmRestart);

  /// Creates a disconnect transition.
  const VmConnectionTransition.disconnect()
      : this(kind: VmConnectionTransitionKind.disconnect);

  /// Whether the app should preserve widget state through this transition.
  bool get preservesAppState =>
      kind == VmConnectionTransitionKind.sameVmRestart;

  /// Whether the old and new attachments represent the same logical VM.
  bool get isSameLogicalVm => kind == VmConnectionTransitionKind.sameVmRestart;

  /// Returns a copy populated with the previous VM identity captured by the
  /// host at reconnect time.
  VmConnectionTransition withPrevious({
    String? previousUri,
    String? previousIsolateId,
    String? previousVmName,
  }) =>
      VmConnectionTransition(
        kind: kind,
        previousUri: previousUri ?? this.previousUri,
        previousIsolateId: previousIsolateId ?? this.previousIsolateId,
        previousVmName: previousVmName ?? this.previousVmName,
      );
}

class _ReconnectState {
  final String? connectedVmName;
  final bool autoReconnect;

  const _ReconnectState({
    required this.connectedVmName,
    required this.autoReconnect,
  });
}

// ---------------------------------------------------------------------------
// DevToolsConnectionHost base class
// ---------------------------------------------------------------------------

/// Abstract base State that manages VM/DTD connection lifecycle.
///
/// Subclasses (e.g. the ROHD DevTools page) extend this to get:
///  - VM connect / disconnect / pause / resume / lightweight reconnect
///  - Persistent DTD connection with VmServiceRegistered/Unregistered events
///  - DTD Service stream for extension availability (e.g. 'rohd' service)
///  - VM liveness polling with auto-reconnect by name
///  - ConnectionStateMachine integration
///  - Connection dialog management
///
/// The subclass implements abstract hooks to react to these lifecycle events
/// and perform app-specific work (loading hierarchy, waveforms, etc.).
abstract class DevToolsConnectionHostState<T extends StatefulWidget>
    extends State<T> {
  // ══════════════════════════════════════════════════════════════════════════
  // Configuration — override in subclass
  // ══════════════════════════════════════════════════════════════════════════

  /// The connection strategy (platform-specific VM service connection).
  /// Return null if VM connection is not supported on this platform.
  VmConnectionStrategy? get connectionStrategy;

  // ══════════════════════════════════════════════════════════════════════════
  // Connection state
  // ══════════════════════════════════════════════════════════════════════════

  /// Whether connected to a VM (true after successful handshake).
  bool get isConnected => _isConnected;

  /// Sets whether the host is connected to a VM.
  @protected
  set isConnected(bool value) => _isConnected = value;
  bool _isConnected = false;

  /// True while a VM connection handshake is in progress.
  bool get isConnecting => _isConnecting;

  /// Sets whether a VM connection handshake is in progress.
  @protected
  set isConnecting(bool value) => _isConnecting = value;
  bool _isConnecting = false;

  /// True when the VM service has been detected as dead.
  bool get isVmDead => _isVmDead;

  /// Sets whether the host believes the VM is dead.
  @protected
  set isVmDead(bool value) => _isVmDead = value;
  bool _isVmDead = false;

  /// True when the user deliberately paused the VM connection.
  bool get isPaused => _isPaused;

  /// Sets whether the user deliberately paused the VM connection.
  @protected
  set isPaused(bool value) => _isPaused = value;
  bool _isPaused = false;

  /// The active VM service instance (null when disconnected).
  VmService? get vmService => _vmService;

  /// Sets the active VM service instance.
  @protected
  set vmService(VmService? value) => _vmService = value;
  VmService? _vmService;

  /// URI of the last/current VM service connection.
  String? get lastVmServiceUri => _lastVmServiceUri;

  /// Sets the URI of the last/current VM service connection.
  @protected
  set lastVmServiceUri(String? value) => _lastVmServiceUri = value;
  String? _lastVmServiceUri;

  /// Isolate ID from the last successful connection.
  String? get lastIsolateId => _lastIsolateId;

  /// Sets the last known isolate ID.
  @protected
  set lastIsolateId(String? value) => _lastIsolateId = value;
  String? _lastIsolateId;

  /// Name of the connected VM (from DTD discovery).
  String? get connectedVmName => _connectedVmName;

  /// Sets the name of the connected VM.
  @protected
  set connectedVmName(String? value) => _connectedVmName = value;
  String? _connectedVmName;

  /// Whether auto-reconnect by name is enabled.
  bool get autoReconnect => _autoReconnect;

  /// Sets whether auto-reconnect by name is enabled.
  @protected
  set autoReconnect(bool value) => _autoReconnect = value;
  bool _autoReconnect = false;

  /// Whether a VM service is currently connected (shorthand).
  bool get isVmConnected => _vmService != null;

  /// Monotonically increasing counter bumped on every full reconnect.
  /// Used for widget keys so Flutter recreates stateful widgets.
  int get connectionGeneration => _connectionGeneration;
  int _connectionGeneration = 0;

  /// The connection state machine.
  ConnectionStateMachine get connectionStateMachine => _csm;
  final ConnectionStateMachine _csm = ConnectionStateMachine();

  /// The persistent DTD connection (for VM lifecycle events + RPC).
  DartToolingDaemon? get persistentDtd => _persistentDtd;
  DartToolingDaemon? _persistentDtd;

  /// Remembered VM services across reconnects.
  List<DtdVmServiceInfo>? get rememberedServices => _rememberedServices;

  /// Sets the remembered VM services list.
  @protected
  set rememberedServices(List<DtdVmServiceInfo>? value) =>
      _rememberedServices = value;
  List<DtdVmServiceInfo>? _rememberedServices;

  /// Services currently registered on DTD (populated by Service stream).
  final Set<String> _availableServices = {};

  // ── Private connection state ──

  bool _autoReconnectInProgress = false;
  int _vmLivenessFailCount = 0;
  static const _vmDeadThreshold = 3;
  Timer? _vmLivenessTimer;
  StreamSubscription<DTDEvent>? _dtdEventSubscription;
  StreamSubscription<DTDEvent>? _serviceStreamSubscription;

  // ── URI controllers (for connection dialog) ──

  /// Controller for the VM service URI field.
  final TextEditingController vmServiceUriController = TextEditingController(
    text: 'ws://127.0.0.1:8181/xxxx=/ws',
  );

  /// Controller for the DTD URI field.
  final TextEditingController dtdUriController = TextEditingController();

  /// Most recent connection error shown in the UI.
  String? connectionError;

  // ══════════════════════════════════════════════════════════════════════════
  // Abstract hooks — subclass must implement
  // ══════════════════════════════════════════════════════════════════════════

  /// Called after a successful VM connection.
  ///
  /// [onBeforeVmConnected] runs first, while the previous VM identity is still
  /// available for app-specific state preservation decisions.
  ///
  /// The subclass should create its data sources (tree, waveform, etc.)
  /// using the provided [result] and [uri].  The VM service, isolate ID,
  /// CSM, liveness timer, and DTD listener are already set up.
  Future<void> onVmConnected(VmConnectionResult result, String uri);

  /// Called after a new VM connection is established but before the host
  /// updates its own connection identity.
  ///
  /// [transition] tells the subclass whether this is a fresh attach or a
  /// same-VM restart, so app state can be preserved only when appropriate.
  Future<void> onBeforeVmConnected(
    VmConnectionResult result,
    String uri, {
    required VmConnectionTransition transition,
  }) async {}

  /// Tear down all state from a previous VM connection.
  ///
  /// Called during disconnect and before reconnect.  The subclass should
  /// dispose data sources, clear caches, reset cubits, etc.
  /// Must be resilient (each step individually guarded).
  Future<void> tearDownOldConnection({
    required VmConnectionTransition transition,
  });

  /// Called when a full disconnect completes (before showing dialog).
  ///
  /// The subclass should clear any UI state and references that are
  /// specific to the old connection.
  void onVmDisconnected();

  /// Called when the VM is detected as dead.
  void onVmDead() {}

  /// Called when a dead VM recovers (liveness check succeeds).
  void onVmRecovered() {}

  /// Called when the host pauses app-specific data fetching.
  ///
  /// Subclasses can pause waveform or polling work while keeping the VM
  /// connection itself alive.
  Future<void> onVmPaused() async {}

  /// Called when the host resumes app-specific data fetching.
  ///
  /// Subclasses can resume waveform or polling work and backfill any
  /// missed data while the VM connection remains alive.
  Future<void> onVmResumed() async {}

  /// Verify whether a lightweight reconnect is valid.
  ///
  /// Called with the new [result] after connecting to the same URI.
  /// Return true if the isolate matches (same process) and a lightweight
  /// swap is appropriate; return false to trigger a full reconnect.
  bool onLightweightReconnectCheck(VmConnectionResult result) =>
      result.isolateId == _lastIsolateId;

  /// Called after a successful lightweight reconnect.
  ///
  /// The subclass should swap the VM service in existing transports
  /// without tearing down tree/schematic/waveform state.
  Future<void> onLightweightReconnectSuccess(
    VmConnectionResult result,
    String uri,
  );

  /// Called when a DTD service becomes available.
  ///
  /// For example, when the 'rohd' extension service registers on DTD,
  /// the subclass can enable source navigation.
  void onServiceAvailable(String serviceName) {}

  /// Called when a DTD service becomes unavailable.
  void onServiceUnavailable(String serviceName) {}

  @override

  /// Adds the host's public connection state to the diagnostics tree.
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(FlagProperty('isConnected', value: isConnected))
      ..add(FlagProperty('isConnecting', value: isConnecting))
      ..add(FlagProperty('isVmDead', value: isVmDead))
      ..add(FlagProperty('isPaused', value: isPaused))
      ..add(DiagnosticsProperty<VmService?>('vmService', vmService))
      ..add(StringProperty('lastVmServiceUri', lastVmServiceUri))
      ..add(StringProperty('lastIsolateId', lastIsolateId))
      ..add(StringProperty('connectedVmName', connectedVmName))
      ..add(FlagProperty('autoReconnect', value: autoReconnect))
      ..add(FlagProperty('isVmConnected', value: isVmConnected))
      ..add(IntProperty('connectionGeneration', connectionGeneration))
      ..add(
        DiagnosticsProperty<VmConnectionStrategy?>(
          'connectionStrategy',
          connectionStrategy,
        ),
      )
      ..add(
        DiagnosticsProperty<ConnectionStateMachine>(
          'connectionStateMachine',
          connectionStateMachine,
        ),
      )
      ..add(
        DiagnosticsProperty<DartToolingDaemon?>('persistentDtd', persistentDtd),
      )
      ..add(
        DiagnosticsProperty<List<DtdVmServiceInfo>?>(
          'rememberedServices',
          rememberedServices,
        ),
      )
      ..add(
        DiagnosticsProperty<TextEditingController>(
          'vmServiceUriController',
          vmServiceUriController,
        ),
      )
      ..add(
        DiagnosticsProperty<TextEditingController>(
          'dtdUriController',
          dtdUriController,
        ),
      )
      ..add(StringProperty('connectionError', connectionError));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    _csm.onLoadHierarchy = onCsmLoadHierarchy;
    _csm.onStateChange = _onCsmStateChange;
  }

  @override
  @mustCallSuper
  void dispose() {
    _vmLivenessTimer?.cancel();
    stopDtdListener();
    unawaited(_csm.dispose());
    vmServiceUriController.dispose();
    dtdUriController.dispose();
    unawaited(_vmService?.dispose());
    super.dispose();
  }

  /// Override in subclass if the CSM's loadHierarchy callback should
  /// trigger app-specific loading.  Default is a no-op.
  Future<void> onCsmLoadHierarchy() async {}

  /// Called by the CSM on state changes.  Override for additional behavior.
  @protected
  void _onCsmStateChange(ConnectionPhase phase, DataLoadState dataState) {
    debugPrint('[ConnectionHost] CSM: ${phase.name}  $dataState');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // URI Cleaning Utilities
  // ══════════════════════════════════════════════════════════════════════════

  /// Clean a VM service URI by extracting the valid portion.
  /// VM URIs start with 'ws:' and end with '=/ws'.
  static String cleanVmServiceUri(String input) {
    final trimmed = input.trim();
    var startIndex = trimmed.indexOf('ws:');
    if (startIndex < 0) {
      startIndex = trimmed.indexOf('wss:');
    }
    if (startIndex < 0) {
      return trimmed;
    }

    const endMarker = '=/ws';
    final endIndex = trimmed.indexOf(endMarker, startIndex);
    if (endIndex < 0) {
      return trimmed.substring(startIndex);
    }

    return trimmed.substring(startIndex, endIndex + endMarker.length);
  }

  /// Clean a DTD URI by extracting the valid portion.
  /// DTD URIs start with 'ws:' and end with '='.
  static String cleanDtdUri(String input) {
    final trimmed = input.trim();
    var startIndex = trimmed.indexOf('ws:');
    if (startIndex < 0) {
      startIndex = trimmed.indexOf('wss:');
    }
    if (startIndex < 0) {
      return trimmed;
    }

    var searchFrom = startIndex;
    while (true) {
      final eqIndex = trimmed.indexOf('=', searchFrom);
      if (eqIndex < 0) {
        return trimmed.substring(startIndex);
      }

      if (eqIndex + 3 < trimmed.length &&
          trimmed.substring(eqIndex, eqIndex + 4) == '=/ws') {
        searchFrom = eqIndex + 1;
        continue;
      }

      return trimmed.substring(startIndex, eqIndex + 1);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Connection Actions (public API for subclass and UI)
  // ══════════════════════════════════════════════════════════════════════════

  /// Connect to a VM service at the given URI.
  ///
  /// Tears down any previous connection, establishes a new one, starts
  /// liveness polling and DTD listener, then calls [onVmConnected].
  Future<void> connectToVmService(
    String vmServiceUri, {
    VmConnectionTransition transition = const VmConnectionTransition.fresh(),
  }) async {
    debugPrint('[ConnectionHost] Starting connection to: $vmServiceUri');
    final strategy = connectionStrategy;
    if (strategy == null) {
      throw Exception('No connection strategy available');
    }
    final previousUri = _lastVmServiceUri;
    final previousIsolateId = _lastIsolateId;
    final effectiveTransition = transition.withPrevious(
      previousUri: previousUri,
      previousIsolateId: previousIsolateId,
      previousVmName: _connectedVmName,
    );

    _csm.handleEvent(ConnectRequested(vmServiceUri));

    try {
      await tearDownOldConnection(transition: effectiveTransition);
    } on Exception catch (e) {
      debugPrint(
        '[ConnectionHost] tearDownOldConnection failed (non-fatal): $e',
      );
      _connectionGeneration++;
    }

    debugPrint('[ConnectionHost] Calling strategy.connect...');
    final result = await strategy.connect(vmServiceUri);
    debugPrint('[ConnectionHost] Connected! isolateId: ${result.isolateId}');

    await onBeforeVmConnected(
      result,
      vmServiceUri,
      transition: effectiveTransition,
    );

    // Notify the state machine.
    final identity = VmIdentity(
      uri: vmServiceUri,
      isolateId: result.isolateId,
      vmName: _connectedVmName,
    );
    _csm.handleEvent(ConnectionEstablished(result.vmService, identity));

    setState(() {
      _vmService = result.vmService;
      _isConnected = true;
      _isConnecting = false;
      _isVmDead = false;
      _isPaused = false;
      _vmLivenessFailCount = 0;
      _lastVmServiceUri = vmServiceUri;
      _lastIsolateId = result.isolateId;
    });

    // Let the subclass set up its data sources.  This is the path that
    // calls ServiceManager.vmServiceOpened, which owns streamListen for
    // the Debug/Isolate/etc streams.  Subscribe to debug events only
    // AFTER this has run so we never race ServiceManager.
    await onVmConnected(result, vmServiceUri);
    unawaited(_csm.subscribeToDebugEvents(result.vmService));

    // Start VM liveness polling.
    _vmLivenessTimer?.cancel();
    _vmLivenessTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_checkVmLiveness()),
    );
    debugPrint('[ConnectionHost] Started VM liveness polling (10 s)');

    // Start persistent DTD listener.
    unawaited(startDtdListener());
  }

  /// Disconnect from the current VM service.
  ///
  /// Tears down the connection, resets state, and calls [onVmDisconnected].
  Future<void> disconnect() async {
    _csm.handleEvent(const DisconnectRequested());
    _vmLivenessTimer?.cancel();
    _vmLivenessTimer = null;
    stopDtdListener();
    await tearDownOldConnection(
      transition: const VmConnectionTransition.disconnect().withPrevious(
        previousUri: _lastVmServiceUri,
        previousIsolateId: _lastIsolateId,
        previousVmName: _connectedVmName,
      ),
    );

    setState(() {
      _vmService = null;
      _isConnected = false;
      _isConnecting = false;
      _isVmDead = false;
      _isPaused = false;
      _vmLivenessFailCount = 0;
      connectionError = null;
      _lastVmServiceUri = null;
      _lastIsolateId = null;
      _connectedVmName = null;
      _autoReconnect = false;
    });

    onVmDisconnected();
  }

  /// Pause waveform data fetches while keeping VM connection alive.
  Future<void> pauseVm() async {
    if (!isVmConnected) {
      return;
    }
    debugPrint('[ConnectionHost] Pausing (connection stays alive)');
    _csm.handleEvent(const PauseRequested());
    await onVmPaused();
    setState(() {
      _isPaused = true;
    });
  }

  /// Resume after a pause.
  Future<void> resumeVm() async {
    if (!isVmConnected) {
      debugPrint('[ConnectionHost] VM not connected — nothing to resume');
      return;
    }
    debugPrint('[ConnectionHost] Resuming');
    _csm.handleEvent(const ResumeRequested());
    setState(() {
      _isPaused = false;
    });
    await onVmResumed();
  }

  /// Attempt a lightweight reconnect to the same VM process.
  ///
  /// Returns true if successful (state preserved), false if the caller
  /// should fall through to a full reconnect.
  Future<bool> lightweightReconnect(String uri) async {
    debugPrint('[ConnectionHost] Attempting lightweight reconnect to: $uri');
    final strategy = connectionStrategy;
    if (strategy == null) {
      return false;
    }

    try {
      final result = await strategy.connect(uri);

      if (!onLightweightReconnectCheck(result)) {
        debugPrint(
          '[ConnectionHost] Lightweight check failed — '
          'need full reconnect',
        );
        unawaited(result.vmService.dispose());
        return false;
      }

      debugPrint(
        '[ConnectionHost] Same process — swapping VM service in-place',
      );

      // Notify the state machine.
      final identity = VmIdentity(
        uri: uri,
        isolateId: result.isolateId,
        vmName: _connectedVmName,
      );
      _csm.handleEvent(ConnectionEstablished(result.vmService, identity));

      // Let the subclass swap the transport (this re-runs vmServiceOpened
      // on the local ServiceManager, which owns streamListen).  Subscribe
      // to debug events only AFTER that to avoid racing ServiceManager.
      await onLightweightReconnectSuccess(result, uri);
      unawaited(_csm.subscribeToDebugEvents(result.vmService));

      setState(() {
        _vmService = result.vmService;
        _isConnecting = false;
        _isPaused = false;
        _isVmDead = false;
        _vmLivenessFailCount = 0;
        _lastIsolateId = result.isolateId;
      });

      // Restart liveness timer.
      _vmLivenessTimer?.cancel();
      _vmLivenessTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_checkVmLiveness()),
      );

      // Restart DTD listener.
      unawaited(startDtdListener());

      debugPrint('[ConnectionHost] Lightweight reconnect succeeded');
      return true;
    } on Exception catch (e) {
      debugPrint('[ConnectionHost] Lightweight reconnect failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Connection Dialog
  // ══════════════════════════════════════════════════════════════════════════

  /// Show the VM connection dialog.
  ///
  /// Subclasses can override [buildConnectionDialogContent] to customize.
  Future<void> showConnectionDialog() async {
    final strategy = connectionStrategy;
    if (strategy == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('VM connection not available on this platform'),
          ),
        );
      }
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect to VM Service'),
        content: SizedBox(
          width: 400,
          child: buildConnectionDialogContent(dialogContext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Build the connection dialog content.
  ///
  /// Override in subclass to add demo-mode buttons, emoji detection, etc.
  @protected
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
        cleanVmServiceUri: cleanVmServiceUri,
        cleanDtdUri: cleanDtdUri,
        discoverVmServices: discoverVmServices,
        initialDiscoveredServices: _rememberedServices
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
          _rememberedServices = services
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

  /// Called when demo mode is selected from the connection dialog.
  /// Override in subclass.
  @protected
  void onDemoModeRequested() {}

  /// Attempt connection using the current URI controller values.
  ///
  /// If only DTD URI is provided, discovers VMs and picks the first one.
  Future<void> attemptConnection() async {
    final strategy = connectionStrategy;
    if (strategy == null) {
      setState(() {
        connectionError = 'VM connection not available on this platform';
      });
      return;
    }

    try {
      final resolution = await resolveVmConnectionAttempt(
        rawVmServiceUri: vmServiceUriController.text,
        rawDtdUri: dtdUriController.text,
        discoverVmServices: discoverVmServices,
      );

      if (resolution.cleanedVmServiceUri != vmServiceUriController.text &&
          resolution.cleanedVmServiceUri.isNotEmpty) {
        vmServiceUriController.text = resolution.cleanedVmServiceUri;
      }
      if (resolution.cleanedDtdUri != dtdUriController.text &&
          resolution.cleanedDtdUri.isNotEmpty) {
        dtdUriController.text = resolution.cleanedDtdUri;
      }
      if (resolution.error != null) {
        setState(() {
          connectionError = resolution.error;
        });
        return;
      }
      final vmServiceUri = resolution.vmServiceUri!;

      setState(() {
        connectionError = null;
      });

      setState(() {
        _isConnecting = true;
      });

      // Capture VM name and auto-reconnect from discovery list.
      final matchedService =
          _rememberedServices?.cast<DtdVmServiceInfo?>().firstWhere(
                (s) => s!.connectionUri == vmServiceUri,
                orElse: () => null,
              );
      _connectedVmName = matchedService?.name;
      _autoReconnect = matchedService?.autoReconnect ?? false;

      await connectToVmService(vmServiceUri);
    } on Exception catch (e) {
      debugPrint(
        '[ConnectionHost] attemptConnection failed: '
        '${e.runtimeType}: $e',
      );
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          connectionError = 'Connection failed: $e';
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DTD Discovery
  // ══════════════════════════════════════════════════════════════════════════

  /// Discover VM services from a DTD URI.
  ///
  /// Connects to DTD, calls getVmServices(), returns the list.
  /// Also probes for registered services (new DTD 4.0 API).
  Future<List<DiscoveredVmService>> discoverVmServices(String dtdUri) async =>
      discoverVmServicesViaDtd(
        dtdUri,
        onRegisteredServices: (serviceNames) {
          _availableServices
            ..clear()
            ..addAll(serviceNames);
        },
      );

  /// Check whether a named service is currently available on DTD.
  bool isServiceAvailable(String serviceName) =>
      _availableServices.contains(serviceName);

  // ══════════════════════════════════════════════════════════════════════════
  // DTD Persistent Listener
  // ══════════════════════════════════════════════════════════════════════════

  /// Start the persistent DTD connection for VM lifecycle events.
  @protected
  Future<void> startDtdListener() async {
    final raw = dtdUriController.text;
    if (raw.isEmpty) {
      return;
    }

    // Don't restart if already listening.
    if (_persistentDtd != null && !_persistentDtd!.isClosed) {
      return;
    }

    try {
      final dtd = await DartToolingDaemon.connect(Uri.parse(raw));
      _persistentDtd = dtd;

      // Notify subclass that DTD is available.
      onDtdConnected(dtd);

      // Listen for VM service register/unregister events.
      _dtdEventSubscription = dtd.onVmServiceUpdate().listen(
        handleDtdVmEvent,
        onError: (Object e) {
          debugPrint('[ConnectionHost] DTD event stream error: $e');
        },
        onDone: () {
          debugPrint('[ConnectionHost] DTD event stream closed');
          _persistentDtd = null;
          _dtdEventSubscription = null;
          onDtdDisconnected();
        },
      );

      await dtd.streamListen(ConnectedAppServiceConstants.serviceName);
      debugPrint('[ConnectionHost] Listening for VM lifecycle events');

      // Subscribe to Service stream for extension availability.
      try {
        _serviceStreamSubscription = dtd
            .onEvent(CoreDtdServiceConstants.servicesStreamId)
            .listen(_handleServiceStreamEvent);
        await dtd.streamListen(CoreDtdServiceConstants.servicesStreamId);
        debugPrint('[ConnectionHost] Listening for Service stream events');
      } on Exception catch (e) {
        debugPrint('[ConnectionHost] Service stream subscription failed: $e');
      }

      // Probe registered services on initial connect.
      try {
        final registered = await dtd.getRegisteredServices();
        _availableServices.clear();
        for (final svc in registered.clientServices) {
          _availableServices.add(svc.name);
          onServiceAvailable(svc.name);
        }
      } on Exception catch (e) {
        debugPrint('[ConnectionHost] getRegisteredServices failed: $e');
      }

      // Use dtd.done as a backup death detector.
      unawaited(
        dtd.done.then((_) {
          if (_persistentDtd == dtd) {
            debugPrint('[ConnectionHost] dtd.done fired — DTD connection lost');
            _persistentDtd = null;
            unawaited(_dtdEventSubscription?.cancel());
            _dtdEventSubscription = null;
            unawaited(_serviceStreamSubscription?.cancel());
            _serviceStreamSubscription = null;
            onDtdDisconnected();
          }
        }),
      );
    } on Exception catch (e) {
      debugPrint('[ConnectionHost] Could not start DTD listener: $e');
    }
  }

  /// Stop the persistent DTD listener.
  @protected
  void stopDtdListener() {
    unawaited(_dtdEventSubscription?.cancel());
    _dtdEventSubscription = null;
    unawaited(_serviceStreamSubscription?.cancel());
    _serviceStreamSubscription = null;
    if (_persistentDtd != null && !_persistentDtd!.isClosed) {
      unawaited(_persistentDtd!.close());
    }
    _persistentDtd = null;
    onDtdDisconnected();
  }

  /// Called when the persistent DTD connection is established.
  /// Override to wire DTD to source navigation, etc.
  void onDtdConnected(DartToolingDaemon dtd) {}

  /// Called when the persistent DTD connection is lost.
  @protected
  void onDtdDisconnected() {}

  /// Handle Service stream events (extension registered/unregistered).
  void _handleServiceStreamEvent(DTDEvent event) {
    final kind = event.kind;
    // The service name is in event.data under 'service' or 'method'.
    final serviceName = event.data['service']?.toString();
    if (serviceName == null || serviceName.isEmpty) {
      return;
    }

    if (kind == CoreDtdServiceConstants.serviceRegisteredKind) {
      if (_availableServices.add(serviceName)) {
        debugPrint('[ConnectionHost] Service available: $serviceName');
        onServiceAvailable(serviceName);
      }
    } else if (kind == CoreDtdServiceConstants.serviceUnregisteredKind) {
      if (_availableServices.remove(serviceName)) {
        debugPrint('[ConnectionHost] Service unavailable: $serviceName');
        onServiceUnavailable(serviceName);
      }
    }
  }

  /// Handle DTD VM lifecycle events.
  ///
  /// When a VM service is unregistered, marks the connection as dead.
  /// When a new VM with our name registers, triggers auto-reconnect.
  @protected
  Future<void> handleDtdVmEvent(DTDEvent event) async {
    debugPrint('[ConnectionHost] DTD event: ${event.kind} — ${event.data}');

    // Ignore events while manually paused (except vmServiceRegistered).
    if (_isPaused &&
        event.kind != ConnectedAppServiceConstants.vmServiceRegistered) {
      debugPrint('[ConnectionHost] Ignoring event — VM is manually paused');
      return;
    }

    // Ignore events while a connection is in progress.
    if (_isConnecting) {
      debugPrint('[ConnectionHost] Ignoring event — connection in progress');
      return;
    }

    if (event.kind == ConnectedAppServiceConstants.vmServiceUnregistered) {
      final eventUri = event.data[DtdParameters.uri]?.toString();
      final eventExposedUri = event.data[DtdParameters.exposedUri]?.toString();
      final ourUri = _lastVmServiceUri;

      if (!dtdEventMatchesTrackedVm(
        trackedVmUri: ourUri,
        eventUri: eventUri,
        eventExposedUri: eventExposedUri,
      )) {
        debugPrint(
          '[ConnectionHost] Ignoring unregister for different VM: '
          'uri=$eventUri, exposedUri=$eventExposedUri (ours: $ourUri)',
        );
        return;
      }

      debugPrint(
        '[ConnectionHost] Our VM service was unregistered — marking dead',
      );
      _csm.handleEvent(const DtdVmUnregistered());
      _vmLivenessTimer?.cancel();
      _vmLivenessTimer = null;

      if (mounted) {
        setState(() {
          _isVmDead = true;
        });
        onVmDead();
      }
    } else if (event.kind == ConnectedAppServiceConstants.vmServiceRegistered) {
      if (!_autoReconnect || !mounted) {
        return;
      }

      final eventName = event.data[DtdParameters.name]?.toString();

      if (eventName == null ||
          eventName.isEmpty ||
          eventName != _connectedVmName) {
        debugPrint(
          '[ConnectionHost] vmServiceRegistered for "$eventName" — '
          'not our target "$_connectedVmName", ignoring',
        );
        return;
      }

      final newUri = preferredVmServiceUriFromDtdEvent(event);
      if (newUri == null || newUri.isEmpty) {
        debugPrint(
          '[ConnectionHost] vmServiceRegistered — no URI in event data',
        );
        return;
      }

      if (_isVmDead || _isPaused) {
        _csm.handleEvent(DtdVmRegistered(newUri, name: eventName));
        debugPrint(
          '[ConnectionHost] vmServiceRegistered for "$eventName" at '
          '$newUri — auto-reconnecting',
        );
        unawaited(reconnectFromDtdEvent(newUri));
      } else if (_isConnected) {
        debugPrint(
          '[ConnectionHost] vmServiceRegistered for "$eventName" at '
          '$newUri — reconnecting (sameUri=${newUri == _lastVmServiceUri})',
        );
        setState(() {
          _isVmDead = true;
        });
        _csm.handleEvent(DtdVmRegistered(newUri, name: eventName));
        unawaited(reconnectFromDtdEvent(newUri));
      }
    }
  }

  /// Reconnect driven by a DTD vmServiceRegistered event.
  @protected
  Future<void> reconnectFromDtdEvent(String newUri) async {
    if (_autoReconnectInProgress) {
      debugPrint('[ConnectionHost] Already reconnecting — skipping');
      return;
    }
    _autoReconnectInProgress = true;

    final wasPaused = _isPaused;
    if (wasPaused) {
      debugPrint('[ConnectionHost] Clearing stale pause state');
    }

    try {
      final sameUri = newUri == _lastVmServiceUri;

      if (sameUri) {
        debugPrint('[ConnectionHost] Same URI — trying lightweight reconnect');
        stopDtdListener();
        final success = await lightweightReconnect(newUri);
        if (success) {
          debugPrint('[ConnectionHost] Lightweight reconnect succeeded');
          _autoReconnectInProgress = false;
          return;
        }
        debugPrint('[ConnectionHost] Lightweight failed — full reconnect');
      }

      await performFullReconnect(newUri);
    } on Exception catch (e) {
      debugPrint('[ConnectionHost] DTD reconnect failed: $e');
      if (_autoReconnect && _isVmDead && mounted) {
        unawaited(attemptAutoReconnect());
      }
    } finally {
      _autoReconnectInProgress = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VM Liveness Polling
  // ══════════════════════════════════════════════════════════════════════════

  /// Check if the VM service is alive (getVersion with timeout).
  Future<bool> isVmServiceAlive() async {
    final vm = _vmService;
    if (vm == null) {
      return false;
    }
    try {
      await vm.getVersion().timeout(const Duration(seconds: 5));
      return true;
    } on Exception {
      return false;
    }
  }

  /// Periodic liveness probe.
  Future<void> _checkVmLiveness() async {
    if (!isVmConnected || !mounted || _isPaused || _isConnecting) {
      return;
    }
    final alive = await isVmServiceAlive();

    if (!mounted || _isPaused || _isConnecting || !isVmConnected) {
      return;
    }

    if (alive) {
      _vmLivenessFailCount = 0;
      if (_isVmDead && mounted) {
        debugPrint('[ConnectionHost] VM recovered — clearing dead flag');
        _csm.handleEvent(const VmRecovered());
        setState(() {
          _isVmDead = false;
        });
        onVmRecovered();
      }
    } else {
      _vmLivenessFailCount++;
      debugPrint(
        '[ConnectionHost] VM check failed '
        '($_vmLivenessFailCount/$_vmDeadThreshold)',
      );
      if (_vmLivenessFailCount >= _vmDeadThreshold && !_isVmDead && mounted) {
        debugPrint('[ConnectionHost] VM is dead');
        _csm.handleEvent(const VmDied());
        setState(() {
          _isVmDead = true;
        });
        onVmDead();
        if (_autoReconnect) {
          unawaited(attemptAutoReconnect());
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Auto-Reconnect
  // ══════════════════════════════════════════════════════════════════════════

  /// Attempt to reconnect to a VM with the same name (exponential backoff).
  Future<void> attemptAutoReconnect() async {
    if (_autoReconnectInProgress) {
      debugPrint('[ConnectionHost] Already reconnecting — skipping');
      return;
    }
    _autoReconnectInProgress = true;

    final targetName = _connectedVmName;
    final dtdUri = dtdUriController.text;
    if (targetName == null || targetName.isEmpty || dtdUri.isEmpty) {
      debugPrint('[ConnectionHost] No VM name or DTD URI — skipping');
      _autoReconnectInProgress = false;
      return;
    }

    debugPrint('[ConnectionHost] Will try to reconnect to "$targetName"');

    const maxAttempts = 5;
    var delay = const Duration(seconds: 2);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      await Future<void>.delayed(delay);
      if (!mounted || !_isVmDead || !_autoReconnect) {
        _autoReconnectInProgress = false;
        return;
      }

      debugPrint(
        '[ConnectionHost] Auto-reconnect attempt '
        '$attempt/$maxAttempts',
      );
      try {
        final cleaned = cleanDtdUri(dtdUri);
        final services = await discoverVmServices(cleaned);
        final match = services.cast<DiscoveredVmService?>().firstWhere(
              (s) => s!.name == targetName,
              orElse: () => null,
            );

        if (match != null) {
          final sameUri = match.connectionUri == _lastVmServiceUri;
          debugPrint(
            '[ConnectionHost] Found "$targetName" at '
            '${match.connectionUri} '
            '(${sameUri ? "same" : "different"} URI)',
          );

          _rememberedServices = services
              .map(
                (s) => DtdVmServiceInfo.fromFields(
                  name: s.name,
                  uri: s.uri,
                  exposedUri: s.exposedUri,
                  autoReconnect: s.connectionUri == match.connectionUri,
                ),
              )
              .toList();

          if (sameUri) {
            stopDtdListener();
            final success = await lightweightReconnect(match.connectionUri);
            if (success) {
              debugPrint(
                '[ConnectionHost] Auto lightweight reconnect succeeded',
              );
              _autoReconnectInProgress = false;
              return;
            }
          }

          await performFullReconnect(match.connectionUri);

          if (isVmConnected && !_isVmDead) {
            debugPrint('[ConnectionHost] Auto-reconnected to "$targetName"');
            _autoReconnectInProgress = false;
            return;
          }
        } else {
          debugPrint('[ConnectionHost] "$targetName" not found — will retry');
        }
      } on Exception catch (e) {
        debugPrint('[ConnectionHost] Attempt $attempt failed: $e');
      }

      delay *= 2;
    }

    debugPrint('[ConnectionHost] Gave up after $maxAttempts attempts');
    _autoReconnectInProgress = false;
  }

  /// Perform a full reconnect to [newUri], preserving same-VM restart
  /// semantics for subclass hooks.
  @protected
  Future<void> performFullReconnect(String newUri) async {
    final reconnectState = _prepareForFullReconnect(newUri);

    await connectToVmService(
      newUri,
      transition: const VmConnectionTransition.sameVmRestart(),
    );
    if (mounted) {
      setState(() {});
    }

    _restoreReconnectPreferences(reconnectState);
  }

  _ReconnectState _prepareForFullReconnect(String newUri) {
    _vmLivenessTimer?.cancel();
    _vmLivenessTimer = null;

    vmServiceUriController.text = newUri;

    final reconnectState = _ReconnectState(
      connectedVmName: _connectedVmName,
      autoReconnect: _autoReconnect,
    );

    stopDtdListener();
    setState(() {
      _isVmDead = false;
      _isPaused = false;
      _vmLivenessFailCount = 0;
    });

    return reconnectState;
  }

  void _restoreReconnectPreferences(_ReconnectState reconnectState) {
    _connectedVmName = reconnectState.connectedVmName;
    _autoReconnect = reconnectState.autoReconnect;
  }

  /// Increment the connection generation (triggers widget recreation).
  @protected
  void bumpConnectionGeneration() {
    _connectionGeneration++;
  }
}
