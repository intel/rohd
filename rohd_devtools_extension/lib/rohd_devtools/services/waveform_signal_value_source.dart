// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// waveform_signal_value_source.dart
// Waveform-backed adapter for the shared signal value source interface.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Adapter exposing a [SignalWaveformApi] through [SignalValueSource].
class WaveformSignalValueSource implements SignalValueSource {
  /// The wrapped waveform API.
  final SignalWaveformApi api;

  final Stream<SignalValueUpdateEvent>? _updates;

  /// Creates an adapter around [api].
  WaveformSignalValueSource({
    required this.api,
    Stream<WaveformUpdateEvent>? liveUpdates,
  }) : _updates = liveUpdates?.map(_mapWaveformUpdateEvent);

  @override
  Stream<SignalValueUpdateEvent>? get updates => _updates;

  @override
  Future<int?> getCurrentTime() => api.getCurrentTime();

  @override
  Future<SignalSnapshotData?> getSnapshot(int time) => api.getSnapshot(time);

  static SignalValueUpdateEvent _mapWaveformUpdateEvent(
    WaveformUpdateEvent event,
  ) =>
      SignalValueUpdateEvent(
        upToTime: event.upToTime,
        hasData: event.hasData,
        reason: event.reason.name,
      );
}
