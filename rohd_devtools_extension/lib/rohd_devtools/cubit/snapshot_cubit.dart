// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// snapshot_cubit.dart
// Cubit for managing signal value snapshots at a point in time.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';

/// Operating mode for the snapshot system.
enum SignalTrackingMode {
  /// Camera mode — user manually takes a one-shot snapshot at the marker
  /// time by pressing the snapshot button.
  camera,

  /// Video mode — automatically tracks the latest signal values from the
  /// ROHD debugger. Each time a value update arrives, a snapshot is taken.
  video,
}

/// Represents a single signal's value at the snapshot time.
class SignalSnapshot extends Equatable {
  /// The signal ID or full path.
  final String signalId;

  /// The display name of the signal.
  final String name;

  /// The signal value at the snapshot time.
  final String value;

  /// The bit width of the signal.
  final int width;

  /// The direction of the signal (input/output/inout), null if internal.
  final String? direction;

  /// Whether this value was computed extension-side.
  final bool computed;

  /// Creates a [SignalSnapshot].
  const SignalSnapshot({
    required this.signalId,
    required this.name,
    required this.value,
    required this.width,
    this.direction,
    this.computed = false,
  });

  @override
  List<Object?> get props => [
        signalId,
        name,
        value,
        width,
        direction,
        computed,
      ];
}

/// State for the [SnapshotCubit].
sealed class SnapshotState extends Equatable {
  /// Creates a [SnapshotState].
  const SnapshotState();
}

/// No snapshot has been taken yet.
class SnapshotInitial extends SnapshotState {
  /// Creates a [SnapshotInitial].
  const SnapshotInitial();

  @override
  List<Object?> get props => [];
}

/// A snapshot is currently being fetched.
class SnapshotLoading extends SnapshotState {
  /// The time being queried.
  final int time;

  /// Creates a [SnapshotLoading].
  const SnapshotLoading(this.time);

  @override
  List<Object?> get props => [time];
}

/// A snapshot has been successfully fetched.
class SnapshotLoaded extends SnapshotState {
  /// The time at which the snapshot was taken, in source-provided units.
  final int time;

  /// Map of signal ID to [SignalSnapshot].
  final Map<String, SignalSnapshot> signals;

  /// Creates a [SnapshotLoaded].
  const SnapshotLoaded({required this.time, required this.signals});

  @override
  List<Object?> get props => [time, signals];

  /// Look up a signal's snapshot value by signal ID.
  SignalSnapshot? getSignal(String signalId) => signals[signalId];

  /// Look up a signal's snapshot value by signal name.
  SignalSnapshot? getSignalByName(String name) {
    for (final snapshot in signals.values) {
      if (snapshot.name == name) {
        return snapshot;
      }
    }
    return null;
  }
}

/// An error occurred while fetching the snapshot.
class SnapshotError extends SnapshotState {
  /// The error message.
  final String message;

  /// Creates a [SnapshotError].
  const SnapshotError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Cubit that manages signal value snapshots.
class SnapshotCubit extends Cubit<SnapshotState> {
  /// Creates a snapshot cubit.
  SnapshotCubit() : super(const SnapshotInitial());

  /// The current operating mode.
  SignalTrackingMode _mode = SignalTrackingMode.camera;

  /// The current operating mode.
  SignalTrackingMode get mode => _mode;

  StreamSubscription<SignalValueUpdateEvent>? _liveUpdatesSub;

  /// Switch between camera and video mode.
  void setMode(SignalTrackingMode mode) {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    if (mode == SignalTrackingMode.camera) {
      _stopVideoTracking();
    }
    debugPrint('[SnapshotCubit] Mode changed to ${mode.name}');
  }

  /// Start video-mode tracking from a shared value source.
  void startVideoTracking(SignalValueSource source) {
    _stopVideoTracking();
    final liveUpdates = source.updates;
    if (liveUpdates == null) {
      debugPrint('[SnapshotCubit] Video tracking unavailable for source');
      return;
    }
    _liveUpdatesSub = liveUpdates.listen(
      (event) {
        if (_mode == SignalTrackingMode.video &&
            event.upToTime > 0 &&
            event.hasData) {
          unawaited(takeSnapshot(source, event.upToTime));
        }
      },
      onError: (Object e) {
        debugPrint('[SnapshotCubit] Video tracking error: $e');
      },
    );
  }

  void _stopVideoTracking() {
    unawaited(_liveUpdatesSub?.cancel());
    _liveUpdatesSub = null;
  }

  /// Take a snapshot of all signal values at the given [time].
  Future<void> takeSnapshot(SignalValueSource source, int time) async {
    emit(SnapshotLoading(time));

    try {
      final rawData = await source.getSnapshot(time);

      if (rawData == null) {
        emit(const SnapshotError('No snapshot data returned'));
        return;
      }

      final signals = <String, SignalSnapshot>{};
      for (final entry in rawData.entries) {
        final signalId = entry.key;
        final data = entry.value;
        signals[signalId] = SignalSnapshot(
          signalId: signalId,
          name: (data['name'] as String?) ?? signalId,
          value: (data['value'] as String?) ?? '?',
          width: (data['width'] as int?) ?? 1,
          direction: data['direction'] as String?,
          computed: data['computed'] as bool? ?? false,
        );
      }

      emit(SnapshotLoaded(time: time, signals: signals));
    } on Object catch (e) {
      debugPrint('[SnapshotCubit] Error taking snapshot: $e');
      emit(SnapshotError('Failed to take snapshot: $e'));
    }
  }

  /// Clear the current snapshot, reset mode, and stop video tracking.
  void clear() {
    _stopVideoTracking();
    _mode = SignalTrackingMode.camera;
    emit(const SnapshotInitial());
  }

  @override
  Future<void> close() {
    _stopVideoTracking();
    return super.close();
  }
}
