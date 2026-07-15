// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_waveform.dart
// An abstract class that defines the API for module structure.
//
// 2024 January 29
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:rohd_waveform/rohd_waveform.dart';

/// An abstract class that defines the API for module structure.
/// An abstract class that defines the API for waveform data retrieval.
///
/// Module structure (hierarchy, signals) is provided separately through
/// the rohd_hierarchy path.  This API handles only waveform *values*.
abstract class SignalWaveformApi {
  /// Creates a new instance of [SignalWaveformApi].
  const SignalWaveformApi();

  /// Whether the underlying waveform source is ready for data access.
  ///
  /// Implementations that have an asynchronous load phase override this.
  /// The default assumes the API is ready immediately.
  bool get isLoaded => true;

  /// Retrieves waveform data for specific signals.
  ///
  /// [signalIds] is a list of signal IDs for which to retrieve data.
  /// [startTime] and [endTime] optionally specify a time range for the data.
  ///
  /// Returns a [Future] that completes with a list of [WaveformData] objects.
  Future<List<WaveformData>> getWaveformData({
    required List<String> signalIds,
    int? startTime,
    int? endTime,
  }) async {
    // Base implementation: must be overridden by concrete implementations
    // Port no longer contains data - implementations must fetch from
    // their source.
    throw UnimplementedError(
      'getWaveformData must be implemented by subclasses',
    );
  }

  /// Streams waveform data incrementally for specific signals.
  ///
  /// [signalIds] is a list of signal IDs for which to stream data.
  /// [startTime] optionally specifies the starting time for the data stream.
  ///
  /// Returns a [Stream] of [WaveformData] objects that can be used to
  /// incrementally update the waveform display.
  Stream<WaveformData> streamWaveformData({
    required List<String> signalIds,
    int? startTime,
  }) async* {
    // Default implementation: get all data at once and yield
    final waveformDataList = await getWaveformData(
      signalIds: signalIds,
      startTime: startTime,
    );
    for (final waveformData in waveformDataList) {
      yield waveformData;
    }
  }

  /// Retrieves the current time of the active ROHD application.
  ///
  /// This method polls the current simulation time, which is useful for
  /// dynamically updating the waveform display end time as a simulation
  /// progresses.
  ///
  /// Returns a [Future] that completes with the current time as an integer,
  /// or null if the time cannot be determined.
  Future<int?> getCurrentTime() async {
    // Default implementation: must be overridden by concrete implementations
    throw UnimplementedError(
      'getCurrentTime must be implemented by subclasses',
    );
  }

  /// Retrieves a snapshot of all signal values at the given [time].
  ///
  /// Returns a map of signal ID to a map containing:
  /// - `value`: the signal value at that time (String)
  /// - `name`: signal display name
  /// - `width`: signal bit width
  /// - `direction`: signal direction (if port)
  ///
  /// Returns null if the snapshot could not be retrieved.
  Future<Map<String, Map<String, dynamic>>?> getSnapshot(int time) async {
    throw UnimplementedError('getSnapshot must be implemented by subclasses');
  }

  /// Proactively expand all slim module definitions so the client-side
  /// evaluator can compute internal signals immediately.
  ///
  /// Called when the user enables "internal signals" in the wave viewer.
  /// Default implementation is a no-op; overridden by implementations
  /// that support client-side synthesis.
  Future<void> expandAllSlimModules() async {}
}
