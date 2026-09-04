// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_viewer_wrapper.dart
// Wrapper widget that sets up the ROHD Wave Viewer with required providers.
// Supports both mock data and loopback waveform data sources.
//
// 2025 January 12
// Author: Copilot
// 2026 January - Added loopback waveform data source support
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/cubits.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/services.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show CrossProbeService, GoToSourceCallback, RohdSourceFormat;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_wave_viewer/rohd_wave_viewer.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// A wrapper widget that sets up the ROHD Wave Viewer with the required
/// SignalWaveformRepository and renders the App widget.
///
/// This widget initializes the repository with mock data suitable for
/// extension mode (waits for VCD to be loaded via postMessage).
/// It syncs the wave viewer's theme with the main app's DevToolsThemeCubit.
///
/// When `useSharedHierarchy` is true (default), the wrapper listens to
/// [DevToolsHierarchyCubit] and will use the shared hierarchy from DevTools
/// instead of loading its own. This enables synchronized selection across
/// the module tree, waveform viewer, and schematic viewer.
///
/// When `signalWaveformApi` is provided, it will be used instead of the
/// default MockSignalWaveformApi. This enables integration with loopback
/// waveform data sources for testing incremental waveform updates.
class WaveformViewerWrapper extends StatefulWidget {
  /// If true, use hierarchy from DevToolsHierarchyCubit.
  /// If false, the wave viewer loads its own hierarchy from VCD data.
  final bool _useSharedHierarchy;

  /// Optional custom waveform API (e.g., LoopbackSignalWaveformApi).
  /// If null, uses MockSignalWaveformApi.
  final SignalWaveformApi? _signalWaveformApi;

  /// Callback when user requests a refresh (e.g., for incremental updates).
  final VoidCallback? _onRefresh;

  /// Whether the snapshot button should be available.
  ///
  /// Set to false when the VM service is unavailable (dead or paused)
  /// since snapshots require a live VM to query all signal values.
  /// Previously-taken snapshot data in [SnapshotCubit] is unaffected.
  final bool _canSnapshot;

  /// Live notifier for snapshot availability.
  ///
  /// When provided, the wave viewer's snapshot button listens to this
  /// notifier via `ValueListenableBuilder` instead of deriving
  /// availability from `onSnapshotRequested` being non-null.
  /// This bypasses Navigator route caching that can prevent widget
  /// prop updates from reaching the snapshot button after pause/resume.
  final ValueNotifier<bool>? _canSnapshotNotifier;

  /// SignalOccurrence hierarchy paths to restore after the new hierarchy loads.
  ///
  /// Saved before a full reconnect so the SignalBloc can attempt to
  /// re-add each signal to the monitor list.  Null when there is
  /// nothing to restore.
  final List<String>? _initialMonitoredSignalPaths;

  /// Called whenever the monitored signal list changes.
  /// The parent uses this to track which signals are actively monitored.
  final ValueChanged<List<String>>? _onMonitoredSignalsChanged;

  /// Callback when user wants to send selected signals to other viewers.
  final void Function(List<String> signalPaths)? _onSendSignals;

  /// Callback when user wants to navigate to a signal's source for a chosen
  /// [RohdSourceFormat].
  final GoToSourceCallback? _onGoToSource;

  /// Notifier for incoming signal paths from other viewers (cross-probing).
  ///
  /// When the value changes, the wave viewer adds the signal paths to the
  /// monitor list.  The parent sets the value when the shared
  /// signal-selection bus fires a message from another viewer.
  final ValueNotifier<List<String>?>? _incomingSignalPaths;

  /// Optional cross-probe service for cross-probing between viewers.
  ///
  /// When provided, overrides the incoming-signal notifier and send callback.

  final CrossProbeService? _crossProbeService;

  /// Optional ROHD extension client for source-format handshaking.
  final FlcExtensionClient? _extensionClient;

  /// Creates a waveform viewer wrapper.
  const WaveformViewerWrapper({
    super.key,
    bool useSharedHierarchy = true,
    SignalWaveformApi? signalWaveformApi,
    VoidCallback? onRefresh,
    bool canSnapshot = true,
    ValueNotifier<bool>? canSnapshotNotifier,
    List<String>? initialMonitoredSignalPaths,
    ValueChanged<List<String>>? onMonitoredSignalsChanged,
    void Function(List<String> signalPaths)? onSendSignals,
    GoToSourceCallback? onGoToSource,
    ValueNotifier<List<String>?>? incomingSignalPaths,
    CrossProbeService? crossProbeService,
    FlcExtensionClient? extensionClient,
  })  : _useSharedHierarchy = useSharedHierarchy,
        _signalWaveformApi = signalWaveformApi,
        _onRefresh = onRefresh,
        _canSnapshot = canSnapshot,
        _canSnapshotNotifier = canSnapshotNotifier,
        _initialMonitoredSignalPaths = initialMonitoredSignalPaths,
        _onMonitoredSignalsChanged = onMonitoredSignalsChanged,
        _onSendSignals = onSendSignals,
        _onGoToSource = onGoToSource,
        _incomingSignalPaths = incomingSignalPaths,
        _crossProbeService = crossProbeService,
        _extensionClient = extensionClient;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        FlagProperty(
          'useSharedHierarchy',
          value: _useSharedHierarchy,
          ifFalse: 'loads own hierarchy',
        ),
      )
      ..add(
        ObjectFlagProperty<SignalWaveformApi?>(
          'signalWaveformApi',
          _signalWaveformApi,
          ifNull: 'uses default mock API',
        ),
      )
      ..add(
        ObjectFlagProperty<VoidCallback?>(
          'onRefresh',
          _onRefresh,
          ifNull: 'no refresh callback',
        ),
      )
      ..add(
        FlagProperty(
          'canSnapshot',
          value: _canSnapshot,
          ifFalse: 'snapshot disabled',
        ),
      );
  }

  @override
  State<WaveformViewerWrapper> createState() => _WaveformViewerWrapperState();
}

class _WaveformViewerWrapperState extends State<WaveformViewerWrapper> {
  late final SignalWaveformRepository _signalWaveformRepository;

  /// The currently active API.  Mutable so that [didUpdateWidget] can
  /// swap it when the parent hands down a replacement (e.g. after a full
  /// reconnect) — this keeps [_liveUpdatesStream] pointing at the right
  /// broadcast stream.
  late SignalWaveformApi _api;

  @override
  void initState() {
    super.initState();
    // Use provided API or default to mock
    _api = widget._signalWaveformApi ?? MockSignalWaveformApi();
    _signalWaveformRepository = SignalWaveformRepository(
      signalWaveformApi: _api,
    );
  }

  @override
  void didUpdateWidget(WaveformViewerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the API changed, update both the repository AND our local _api
    // reference so that _liveUpdatesStream returns the correct stream.
    if (widget._signalWaveformApi != oldWidget._signalWaveformApi &&
        widget._signalWaveformApi != null) {
      _api = widget._signalWaveformApi!;
      _signalWaveformRepository.setSignalWaveformApi(_api);
    }
  }

  /// Get the liveUpdates stream from the current API (if supported).
  Stream<WaveformUpdateEvent>? get _liveUpdatesStream {
    final api = _api;
    if (api is LoopbackSignalWaveformApi) {
      return api.liveUpdates;
    }
    if (api is VmServiceSignalWaveformApi) {
      return api.liveUpdates;
    }
    return null;
  }

  SignalValueSource get _signalValueSource =>
      WaveformSignalValueSource(api: _api, liveUpdates: _liveUpdatesStream);

  /// Toggle between camera and video snapshot modes.
  void _toggleSnapshotMode() {
    final cubit = context.read<SnapshotCubit>();
    if (cubit.mode == SignalTrackingMode.camera) {
      cubit.setMode(SignalTrackingMode.video);
      // Start auto-tracking if a live stream is available
      final source = _signalValueSource;
      if (source.updates != null) {
        cubit.startVideoTracking(source);
      }
      // Immediately snapshot at the current simulation time so the
      // Details pane updates without waiting for the next debug event.
      unawaited(
        source.getCurrentTime().then((time) {
          if (time != null && time > 0 && mounted) {
            unawaited(cubit.takeSnapshot(source, time));
          }
        }),
      );
    } else {
      cubit.setMode(SignalTrackingMode.camera);
      // Camera mode — cubit.setMode already stops video tracking
    }
    // Force rebuild so the button icon updates
    setState(() {});
  }

  @override
  // Listen to DevToolsThemeCubit and DevToolsHierarchyCubit
  Widget build(BuildContext context) {
    final cubit = context.read<SnapshotCubit>();
    final isVideoMode = cubit.mode == SignalTrackingMode.video;

    // Build the wave viewer with theme and optional external hierarchy
    Widget buildWaveViewer(
      WaveViewerThemeMode themeMode,
      HierarchyService? externalHierarchy,
      HierarchyOccurrence? selectedModule,
      int? lastSnapshotTimePs,
    ) =>
        RepaintBoundary(
          child: App(
            signalWaveformRepository: _signalWaveformRepository,
            initialThemeMode: themeMode,
            externalHierarchy: externalHierarchy,
            selectedModule: selectedModule,
            title: 'ROHD DevTools',
            liveUpdates: _liveUpdatesStream,
            isExtensionMode: true,
            initialMonitoredSignalPaths: widget._initialMonitoredSignalPaths,
            onMonitoredSignalsChanged: widget._onMonitoredSignalsChanged,
            onSnapshotRequested: (time) {
              unawaited(
                context.read<SnapshotCubit>().takeSnapshot(
                      _signalValueSource,
                      time,
                    ),
              );
            },
            canSnapshotNotifier: widget._canSnapshotNotifier,
            lastSnapshotTimePs: lastSnapshotTimePs,
            isVideoMode: isVideoMode,
            onVideoModeToggled:
                _liveUpdatesStream != null && _api is! LoopbackSignalWaveformApi
                    ? _toggleSnapshotMode
                    : null,
            onSendSignals: widget._onSendSignals ??
                (widget._crossProbeService != null
                    ? (paths) => widget._crossProbeService!
                        .send(paths, source: 'waveform')
                    : null),
            onGoToSource: widget._onGoToSource,
            incomingSignalPaths: widget._incomingSignalPaths,
            crossProbeService: widget._crossProbeService,
            extensionClient: widget._extensionClient,
          ),
        );

    // Watch hierarchy cubit if using shared hierarchy
    if (widget._useSharedHierarchy) {
      return BlocBuilder<SnapshotCubit, SnapshotState>(
        buildWhen: (prev, curr) {
          // Only rebuild when the snapshot time changes
          final prevTime = prev is SnapshotLoaded ? prev.time : null;
          final currTime = curr is SnapshotLoaded ? curr.time : null;
          return prevTime != currTime;
        },
        builder: (context, snapshotState) {
          final lastSnapTime =
              snapshotState is SnapshotLoaded ? snapshotState.time : null;
          return BlocBuilder<DevToolsHierarchyCubit, DevToolsHierarchyState>(
            builder: (context, hierarchyState) {
              final sharedHierarchy = hierarchyState is HierarchyLoaded
                  ? hierarchyState.hierarchyService
                  : null;
              final selectedModule = hierarchyState is HierarchyLoaded
                  ? hierarchyState.selectedModule
                  : null;
              return BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
                builder: (context, themeMode) {
                  final waveViewerTheme = themeMode == DevToolsThemeMode.dark
                      ? WaveViewerThemeMode.dark
                      : WaveViewerThemeMode.light;
                  return buildWaveViewer(
                    waveViewerTheme,
                    sharedHierarchy,
                    selectedModule,
                    lastSnapTime,
                  );
                },
              );
            },
          );
        },
      );
    }

    // No shared hierarchy - just watch theme + snapshot
    return BlocBuilder<SnapshotCubit, SnapshotState>(
      buildWhen: (prev, curr) {
        final prevTime = prev is SnapshotLoaded ? prev.time : null;
        final currTime = curr is SnapshotLoaded ? curr.time : null;
        return prevTime != currTime;
      },
      builder: (context, snapshotState) {
        final lastSnapTime =
            snapshotState is SnapshotLoaded ? snapshotState.time : null;
        return BlocBuilder<DevToolsThemeCubit, DevToolsThemeMode>(
          builder: (context, themeMode) {
            final waveViewerTheme = themeMode == DevToolsThemeMode.dark
                ? WaveViewerThemeMode.dark
                : WaveViewerThemeMode.light;
            return buildWaveViewer(waveViewerTheme, null, null, lastSnapTime);
          },
        );
      },
    );
  }
}
