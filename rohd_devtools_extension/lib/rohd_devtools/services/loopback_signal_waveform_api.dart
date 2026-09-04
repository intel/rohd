// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// loopback_signal_rohd_waveform.dart
// Loopback adapter — thin subclass of BaseSignalWaveformApi.
//
// All shared algorithm (snapshot expansion, evaluator, synthesis, module
// expansion) lives in BaseSignalWaveformApi.  This subclass adds only
// loopback-specific behavior: refresh with incremental fetch, dispose,
// and stream merging for live updates.
//
// Used for in-process (loopback) and file-backed (VCD/GHW) modes.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_devtools_extension/rohd_devtools/services/base_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/rohd_service_transport.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Loopback adapter that wraps any [RohdServiceTransport] via
/// [BaseSignalWaveformApi].
///
/// Used for in-process (loopback) and file-backed (VCD/GHW) modes.
/// Module structure is injected via [setExternalStructure] from the
/// hierarchy path — the waveform API only handles signal *values*.
///
/// All shared algorithm lives in the base class.  This subclass adds:
/// - `refresh()` for incremental data fetch
/// - `dispose()` for resource cleanup
class LoopbackSignalWaveformApi extends BaseSignalWaveformApi {
  /// Creates a new loopback adapter for the given transport.
  LoopbackSignalWaveformApi(super.transport);

  /// Last fetched time (delegates to transport).
  int get lastFetchedTime => transport.lastFetchedTime;

  /// Advance simulation time and get new waveform data.
  ///
  /// Returns the incremental waveform data for all cached signals.
  Future<List<WaveformData>> refresh([int? timeIncrement]) async {
    final signalIds = cachedSignalIds.toList();
    if (signalIds.isEmpty) {
      return const [];
    }

    // Get fresh data for all cached signals.
    final newData = await getWaveformData(signalIds: signalIds);
    return newData;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await transport.dispose();
    clearCache();
  }
}
