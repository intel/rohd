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
import 'package:rohd_waveform/rohd_waveform.dart'
    show SignalWaveformApi, WaveformUpdateEvent;

/// A wrapper widget that configures the embedded ROHD Wave Viewer.
///
/// It syncs the wave viewer's theme with the main app's DevToolsThemeCubit.
///
/// When `useSharedHierarchy` is true (default), the wrapper listens to
/// [DevToolsHierarchyCubit] and will use the shared hierarchy from DevTools
/// instead of loading its own. This enables synchronized selection across
/// the module tree, waveform viewer, and schematic viewer.
///
/// When `signalWaveformApi` is null, the viewer displays its empty state until
/// a waveform source becomes available.
class WaveformViewerWrapper extends StatefulWidget {
  /// If true, use hierarchy from DevToolsHierarchyCubit.
  /// If false, the wave viewer loads its own hierarchy from VCD data.
  final bool _useSharedHierarchy;

  /// Optional waveform API, such as [LoopbackSignalWaveformApi].
  final SignalWaveformApi? _signalWaveformApi;

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

  /// Callback when user wants to navigate to a signal's source for a chosen
  /// [RohdSourceFormat].
  final GoToSourceCallback? _onGoToSource;

  /// Optional cross-probe service for cross-probing between viewers.
  final CrossProbeService? _crossProbeService;

  /// Optional ROHD extension client for source-format handshaking.
  final FlcExtensionClient? _extensionClient;

  /// Creates a waveform viewer wrapper.
  const WaveformViewerWrapper({
    super.key,
    bool useSharedHierarchy = true,
    SignalWaveformApi? signalWaveformApi,
    ValueNotifier<bool>? canSnapshotNotifier,
    List<String>? initialMonitoredSignalPaths,
    ValueChanged<List<String>>? onMonitoredSignalsChanged,
    GoToSourceCallback? onGoToSource,
    CrossProbeService? crossProbeService,
    FlcExtensionClient? extensionClient,
  })  : _useSharedHierarchy = useSharedHierarchy,
        _signalWaveformApi = signalWaveformApi,
        _canSnapshotNotifier = canSnapshotNotifier,
        _initialMonitoredSignalPaths = initialMonitoredSignalPaths,
        _onMonitoredSignalsChanged = onMonitoredSignalsChanged,
        _onGoToSource = onGoToSource,
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
      );
  }

  @override
  State<WaveformViewerWrapper> createState() => _WaveformViewerWrapperState();
}

class _WaveformViewerWrapperState extends State<WaveformViewerWrapper> {
  SignalWaveformApi? get _api => widget._signalWaveformApi;

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

  SignalValueSource get _signalValueSource => WaveformSignalValueSource(
        api: _api ??
            (throw StateError(
                'Cannot capture a snapshot without waveform data.')),
        liveUpdates: _liveUpdatesStream,
      );

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
          child: EmbeddedWaveViewer(
            waveformApi: _api,
            themeMode: themeMode,
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
            onGoToSource: widget._onGoToSource,
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
