// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// connection_state_machine.dart
// State machine for managing the lifecycle of VM/DTD connections and
// the associated data (hierarchy, schematic, waveforms).
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

// ---------------------------------------------------------------------------
// Connection phases
// ---------------------------------------------------------------------------

/// The coarse-grained connection phase.
///
/// ```text
///   disconnected ──connect──▶ connecting ──success──▶ connected
///        ▲                                                │
///        │                                           vm dies / user
///        │                                           disconnects
///        └────────────────────────────────────────────────┘
///
///   connected ──pause──▶ paused ──resume──▶ connected
///                                                │
///   connected ──vm dies──▶ vmDead ──reconnect──▶ connected
/// ```
enum ConnectionPhase {
  /// No VM connection — user is on the connection page.
  disconnected,

  /// WebSocket handshake + isolate discovery in progress.
  connecting,

  /// VM connection is live.  Sub-state tracked by [DataLoadState].
  connected,

  /// User deliberately paused the connection (data preserved in UI).
  paused,

  /// VM was detected as dead (polling or DTD event).
  vmDead,
}

// ---------------------------------------------------------------------------
// Data load states
// ---------------------------------------------------------------------------

/// What data has been successfully loaded from the VM.
///
/// These flags are orthogonal — hierarchy and waveforms load independently.
/// The state machine uses them to decide what still needs loading when a
/// debug pause event arrives.
class DataLoadState {
  /// Whether the module tree hierarchy has been loaded.
  bool hierarchyLoaded;

  /// Whether schematic JSON has been loaded.
  bool schematicLoaded;

  /// Whether initial waveform data has been fetched.
  bool waveformDataLoaded;

  /// Whether we've attempted hierarchy loading and it returned null
  /// (the ROHD app may not have finished building ModuleTree yet).
  bool hierarchyAttempted;

  /// Creates a data-load snapshot.
  DataLoadState({
    this.hierarchyLoaded = false,
    this.schematicLoaded = false,
    this.waveformDataLoaded = false,
    this.hierarchyAttempted = false,
  });

  /// True when all essential data is present.
  bool get isFullyLoaded => hierarchyLoaded;

  /// True when no data has been loaded yet.
  bool get isEmpty =>
      !hierarchyLoaded && !schematicLoaded && !waveformDataLoaded;

  /// Reset all flags (e.g. on full reconnect to a new VM process).
  /// Resets all data-load flags.
  void reset() {
    hierarchyLoaded = false;
    schematicLoaded = false;
    waveformDataLoaded = false;
    hierarchyAttempted = false;
  }

  /// Copy constructor for snapshotting state.
  /// Creates a copy of this data-load snapshot.
  DataLoadState copy() => DataLoadState(
        hierarchyLoaded: hierarchyLoaded,
        schematicLoaded: schematicLoaded,
        waveformDataLoaded: waveformDataLoaded,
        hierarchyAttempted: hierarchyAttempted,
      );

  @override

  /// Returns a debug string summarizing the current data-load state.
  String toString() => 'DataLoadState('
      'hierarchy=${hierarchyLoaded ? "✓" : hierarchyAttempted ? "✗" : "–"}, '
      'schematic=${schematicLoaded ? "✓" : "–"}, '
      'wfData=${waveformDataLoaded ? "✓" : "–"})';
}

// ---------------------------------------------------------------------------
// Connection identity
// ---------------------------------------------------------------------------

/// Identity of a VM connection for detecting same-process reconnects.
class VmIdentity {
  /// The VM service URI.
  final String uri;

  /// The isolate ID (unique per VM process).
  final String isolateId;

  /// Human-readable VM name (from DTD discovery).
  final String? vmName;

  /// Creates a VM identity.
  const VmIdentity({required this.uri, required this.isolateId, this.vmName});

  /// Whether [other] represents the same running VM process.
  ///
  /// The Dart VM assigns a new isolate ID for every process, so matching
  /// IDs prove the same process is still alive.
  /// Returns whether [other] refers to the same VM process.
  bool isSameProcess(VmIdentity other) => isolateId == other.isolateId;

  @override

  /// Returns a debug string describing this VM identity.
  String toString() => 'VmIdentity(uri=$uri, isolate=$isolateId, '
      'name=$vmName)';
}

// ---------------------------------------------------------------------------
// Events / transitions
// ---------------------------------------------------------------------------

/// Events that drive the state machine.
///
/// Each event carries any data needed for the transition.
sealed class ConnectionEvent {
  const ConnectionEvent();
}

/// User initiated a connection to a VM service URI.
class ConnectRequested extends ConnectionEvent {
  /// The URI requested by the user.
  final String uri;

  /// Creates a connect-request event.
  const ConnectRequested(this.uri);
}

/// VM connection succeeded.
class ConnectionEstablished extends ConnectionEvent {
  /// The connected VM service.
  final VmService vmService;

  /// Identity of the connected VM.
  final VmIdentity identity;

  /// Creates a connection-established event.
  const ConnectionEstablished(this.vmService, this.identity);
}

/// VM connection or data loading failed.
class ConnectionFailed extends ConnectionEvent {
  /// Error message describing the failure.
  final String error;

  /// Creates a connection-failed event.
  const ConnectionFailed(this.error);
}

/// User deliberately disconnected.
class DisconnectRequested extends ConnectionEvent {
  /// Creates a disconnect-request event.
  const DisconnectRequested();
}

/// User paused the VM connection (data preserved).
class PauseRequested extends ConnectionEvent {
  /// Creates a pause-request event.
  const PauseRequested();
}

/// User resumed a paused VM connection.
class ResumeRequested extends ConnectionEvent {
  /// Creates a resume-request event.
  const ResumeRequested();
}

/// VM was detected as dead (via polling or DTD event).
class VmDied extends ConnectionEvent {
  /// Creates a VM-died event.
  const VmDied();
}

/// VM came back to life (liveness check recovered).
class VmRecovered extends ConnectionEvent {
  /// Creates a VM-recovered event.
  const VmRecovered();
}

/// A debug pause event was received from the VM (breakpoint, exception, etc).
class DebugPauseReceived extends ConnectionEvent {
  /// Kind of debug pause event.
  final String kind;

  /// Creates a debug-pause event.
  const DebugPauseReceived(this.kind);
}

/// Hierarchy data was loaded (or attempted and returned null).
class HierarchyLoadResult extends ConnectionEvent {
  /// Whether the hierarchy load succeeded.
  final bool success;

  /// Creates a hierarchy-load result event.
  const HierarchyLoadResult({required this.success});
}

/// A DTD event signalled that a new VM registered.
class DtdVmRegistered extends ConnectionEvent {
  /// VM service URI reported by DTD.
  final String uri;

  /// Optional human-readable name.
  final String? name;

  /// Creates a DTD VM registered event.
  const DtdVmRegistered(this.uri, {this.name});
}

/// A DTD event signalled that a VM was unregistered.
class DtdVmUnregistered extends ConnectionEvent {
  /// Creates a DTD VM unregistered event.
  const DtdVmUnregistered();
}

/// User entered demo/loopback mode.
class DemoModeEntered extends ConnectionEvent {
  /// Creates a demo-mode event.
  const DemoModeEntered();
}

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

/// Callback signature for when the state machine wants the shell to load
/// hierarchy data.
typedef LoadHierarchyCallback = Future<void> Function();

/// Callback signature for notifying the shell of state changes.
typedef StateChangeCallback = void Function(
    ConnectionPhase phase, DataLoadState dataState);

/// The connection state machine.
///
/// Tracks the current [ConnectionPhase], [DataLoadState], and [VmIdentity].
/// Emits [StateChangeCallback] whenever the state transitions so the UI
/// can update.
///
/// ## Key design decisions
///
/// 1. **No spinning on connect**: when the initial hierarchy load returns
///    null, we record `hierarchyAttempted = true` but do NOT retry in a
///    loop.  Instead, when a [DebugPauseReceived] event arrives and
///    hierarchy is not yet loaded, we try again (exactly once per pause).
///
/// 2. **Reconnect identity matching**: on reconnect, if the [VmIdentity]
///    has the same `isolateId` as before, we skip hierarchy/schematic
///    reload (the data is still valid).  Only waveform data gets an
///    incremental pull.
///
/// 3. **DTD events are authoritative**: when DTD says a VM died, we trust
///    it immediately (no additional liveness check).
class ConnectionStateMachine {
  ConnectionPhase _phase = ConnectionPhase.disconnected;
  final DataLoadState _dataState = DataLoadState();
  VmIdentity? _currentIdentity;
  VmIdentity? _lastIdentity;

  /// Subscription to VM debug events for hierarchy-on-pause.
  StreamSubscription<Event>? _debugEventSubscription;

  /// Debounce timer for debug pause events.
  Timer? _pauseDebounceTimer;
  static const _pauseDebounceDuration = Duration(milliseconds: 200);

  /// Whether a hierarchy load is currently in progress (prevents
  /// concurrent loads from rapid breakpoints).
  bool _hierarchyLoadInProgress = false;

  /// Callback invoked when the state machine needs hierarchy data loaded.
  LoadHierarchyCallback? onLoadHierarchy;

  /// Callback invoked on every state transition.
  StateChangeCallback? onStateChange;

  // ── Public getters ──

  /// Current connection phase.
  ConnectionPhase get phase => _phase;

  /// Current data-load snapshot.
  DataLoadState get dataState => _dataState;

  /// Identity of the currently connected VM, if any.
  VmIdentity? get currentIdentity => _currentIdentity;

  /// Identity from the last successful connection, if any.
  VmIdentity? get lastIdentity => _lastIdentity;

  /// Whether we're in a state where data loading makes sense.
  bool get canLoadData =>
      _phase == ConnectionPhase.connected && _currentIdentity != null;

  /// Whether we should attempt hierarchy load on the next debug pause.
  bool get shouldLoadHierarchyOnPause =>
      canLoadData && !_dataState.hierarchyLoaded;

  // ── State transitions ──

  /// Process an event and transition state accordingly.
  void handleEvent(ConnectionEvent event) {
    final oldPhase = _phase;
    final oldDataSnapshot = _dataState.copy();

    switch (event) {
      case ConnectRequested():
        _onConnectRequested(event);
      case ConnectionEstablished():
        _onConnectionEstablished(event);
      case ConnectionFailed():
        _onConnectionFailed(event);
      case DisconnectRequested():
        _onDisconnectRequested();
      case PauseRequested():
        _onPauseRequested();
      case ResumeRequested():
        _onResumeRequested();
      case VmDied():
        _onVmDied();
      case VmRecovered():
        _onVmRecovered();
      case DebugPauseReceived():
        _onDebugPause(event);
      case HierarchyLoadResult():
        _onHierarchyLoadResult(event);
      case DtdVmRegistered():
        _onDtdVmRegistered(event);
      case DtdVmUnregistered():
        _onDtdVmUnregistered();
      case DemoModeEntered():
        _onDemoMode();
    }

    // Notify if anything changed
    if (_phase != oldPhase ||
        _dataState.toString() != oldDataSnapshot.toString()) {
      debugPrint('[CSM] ${oldPhase.name} → ${_phase.name}  $_dataState');
      onStateChange?.call(_phase, _dataState);
    }
  }

  // ── Per-event handlers ──

  /// Handles a connect-request event.
  void _onConnectRequested(ConnectRequested event) {
    _phase = ConnectionPhase.connecting;
  }

  /// Handles a successful VM connection.
  void _onConnectionEstablished(ConnectionEstablished event) {
    final isReconnectSameProcess =
        _lastIdentity != null && _lastIdentity!.isSameProcess(event.identity);

    _currentIdentity = event.identity;
    _phase = ConnectionPhase.connected;

    if (isReconnectSameProcess) {
      // Same VM process — keep existing data, don't reload hierarchy.
      debugPrint(
        '[CSM] Reconnected to same process '
        '(${event.identity.isolateId}) — preserving data',
      );
    } else {
      // New process — reset data state so everything gets loaded fresh.
      _dataState
        ..reset()
        ..hierarchyLoaded = false
        ..schematicLoaded = false;
      _hierarchyLoadInProgress = false;
      _pauseDebounceTimer?.cancel();
      debugPrint(
        '[CSM] Connected to new process '
        '(${event.identity.isolateId}) — data reset',
      );
    }
  }

  /// Handles a failed connection attempt.
  void _onConnectionFailed(ConnectionFailed event) {
    debugPrint('[CSM] Connection failed: ${event.error}');
    _phase = ConnectionPhase.disconnected;
  }

  /// Handles a user-requested disconnect.
  void _onDisconnectRequested() {
    unawaited(_cancelDebugSubscription());
    _lastIdentity = _currentIdentity;
    _currentIdentity = null;
    _dataState.reset();
    _hierarchyLoadInProgress = false;
    _phase = ConnectionPhase.disconnected;
  }

  /// Handles a user-requested pause.
  void _onPauseRequested() {
    unawaited(_cancelDebugSubscription());
    _lastIdentity = _currentIdentity;
    _currentIdentity = null;
    // Data state is preserved — the UI keeps showing cached data.
    _phase = ConnectionPhase.paused;
  }

  /// Handles a user-requested resume.
  void _onResumeRequested() {
    // Phase transition happens when ConnectionEstablished arrives.
    _phase = ConnectionPhase.connecting;
  }

  /// Handles a VM death notification.
  void _onVmDied() {
    unawaited(_cancelDebugSubscription());
    _lastIdentity = _currentIdentity;
    _hierarchyLoadInProgress = false;
    // Data state preserved — UI stays.
    _phase = ConnectionPhase.vmDead;
  }

  /// Handles a VM recovery notification.
  void _onVmRecovered() {
    if (_phase == ConnectionPhase.vmDead) {
      _phase = ConnectionPhase.connected;
    }
  }

  /// Handles a debug pause event from the VM.
  void _onDebugPause(DebugPauseReceived event) {
    if (_phase != ConnectionPhase.connected) {
      debugPrint('[CSM] Debug pause ignored — phase is ${_phase.name}');
      return;
    }

    debugPrint(
      '[CSM] Debug pause (${event.kind}), data: $_dataState, '
      'shouldLoad=$shouldLoadHierarchyOnPause, '
      'inProgress=$_hierarchyLoadInProgress',
    );

    // If hierarchy hasn't been loaded yet, try now.
    // This is the key behavior: instead of spinning/polling after connect,
    // we wait for the first debug pause event and load then.
    if (shouldLoadHierarchyOnPause && !_hierarchyLoadInProgress) {
      _hierarchyLoadInProgress = true;
      debugPrint('[CSM] Hierarchy not loaded — requesting load on pause');
      _scheduleHierarchyLoad();
    }
  }

  /// Schedules a debounced hierarchy load.
  void _scheduleHierarchyLoad() {
    // Debounce: if multiple pause events fire rapidly, only the last
    // one triggers a load.
    _pauseDebounceTimer?.cancel();
    _pauseDebounceTimer = Timer(_pauseDebounceDuration, _doHierarchyLoad);
  }

  /// Performs the actual hierarchy load.
  Future<void> _doHierarchyLoad() async {
    if (onLoadHierarchy == null) {
      _hierarchyLoadInProgress = false;
      return;
    }
    try {
      await onLoadHierarchy!();
    } on Exception catch (e) {
      debugPrint('[CSM] Hierarchy load failed: $e');
    } finally {
      _hierarchyLoadInProgress = false;
    }
  }

  /// Handles the result of a hierarchy load.
  void _onHierarchyLoadResult(HierarchyLoadResult event) {
    _dataState.hierarchyAttempted = true;
    _dataState.hierarchyLoaded = event.success;
    if (event.success) {
      debugPrint('[CSM] Hierarchy loaded successfully');
    } else {
      debugPrint(
        '[CSM] Hierarchy load returned null — will retry on next '
        'debug pause',
      );
    }
  }

  /// Handles a DTD VM registration event.
  void _onDtdVmRegistered(DtdVmRegistered event) {
    // Handled by the shell — the state machine just records the event
    // for logging.
    debugPrint(
      '[CSM] DTD: VM registered at ${event.uri} '
      '(name=${event.name})',
    );
  }

  /// Handles a DTD VM unregistration event.
  void _onDtdVmUnregistered() {
    debugPrint('[CSM] DTD: VM unregistered');
    _onVmDied();
  }

  /// Switches the state machine into demo mode.
  void _onDemoMode() {
    _currentIdentity = null;
    _lastIdentity = null;
    // Mark hierarchy as loaded since demo mode provides it synchronously.
    _dataState
      ..reset()
      ..hierarchyLoaded = true
      ..schematicLoaded = true;
    _phase = ConnectionPhase.connected;
  }

  // ── Debug event subscription management ──

  /// Subscribe to VM debug events on the given [vmService].
  ///
  /// When a pause event arrives, the state machine checks if hierarchy
  /// data is missing and triggers a load.  This replaces the old
  /// "retry loop with exponential backoff" approach.
  /// Subscribes to VM debug events.
  Future<void> subscribeToDebugEvents(VmService vmService) async {
    await _cancelDebugSubscription();
    // Note: we deliberately do NOT call vmService.streamListen(Debug) here.
    // The Debug stream is subscribed by ServiceManager.vmServiceOpened (the
    // owner of the connection's stream lifecycle).  Calling streamListen
    // here as well would race with ServiceManager and produce an
    // unhandled `Stream already subscribed (103)` error, because
    // ServiceManager issues its streamListen via `unawaited(...)` inside a
    // try/catch that only catches synchronous throws.
    _debugEventSubscription = vmService.onDebugEvent.listen((event) {
      final kind = event.kind;
      if (kind == EventKind.kPauseBreakpoint ||
          kind == EventKind.kPauseException ||
          kind == EventKind.kPauseInterrupted ||
          kind == EventKind.kPauseExit) {
        handleEvent(DebugPauseReceived(kind ?? 'unknown'));
      }
    });
    debugPrint('[CSM] Subscribed to debug events');
  }

  /// Cancels the current debug event subscription.
  Future<void> _cancelDebugSubscription() async {
    _pauseDebounceTimer?.cancel();
    await _debugEventSubscription?.cancel();
    _debugEventSubscription = null;
  }

  // ── Convenience queries ──

  /// Whether a reconnect to [identity] should skip hierarchy reload.
  ///
  /// Returns true when the last known VM has the same isolate ID,
  /// meaning the same process is still running and its data hasn't
  /// changed.
  /// Returns true when hierarchy reload can be skipped for [identity].
  bool shouldSkipHierarchyReload(VmIdentity identity) =>
      _lastIdentity != null &&
      _lastIdentity!.isSameProcess(identity) &&
      _dataState.hierarchyLoaded;

  /// Marks waveform data as loaded.
  void markWaveformDataLoaded() {
    _dataState.waveformDataLoaded = true;
    onStateChange?.call(_phase, _dataState);
  }

  /// Marks schematic data as loaded.
  void markSchematicLoaded() {
    _dataState.schematicLoaded = true;
    onStateChange?.call(_phase, _dataState);
  }

  /// Disposes timers and subscriptions used by the state machine.
  Future<void> dispose() async {
    await _cancelDebugSubscription();
    _pauseDebounceTimer?.cancel();
  }
}
