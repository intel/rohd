// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_data_service.dart
// Abstraction layer for fetching signal waveform data.
//
// This service decouples the wave display layer from the data source
// (repository, debugger, simulator, etc.) while respecting shared models.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Abstraction for fetching signal waveform data by signal occurrence.
///
/// Signals come from the shared module hierarchy and are never modified.
/// This service fetches waveform data for a given signal without knowing the
/// data source (VCD file, debugger, simulator, etc.).
///
/// Usage:
/// ```dart
/// final service = RepositorySignalDataService(repository);
/// final port = hierarchy.modules[0].signals[0];
/// final waveData = await service.getSignalData(port);
/// print('SignalOccurrence: ${waveData.signalName}, Points:
///       ${waveData.data.length}');
/// ```
abstract class SignalDataService {
  /// Fetch waveform data for a signal occurrence.
  ///
  /// [port] is the signal definition from the loaded module structure.
  /// Returns `WaveData` combining that shared model with its waveform data.
  ///
  /// This method can be implemented differently in each app:
  /// - Wave Viewer: Fetch from cached VCD waveform data
  /// - Debugger: Fetch from live debugger state
  /// - Simulator: Fetch from running simulation
  Future<WaveData> getSignalData(SignalOccurrence port);

  /// Get all signals for a module.
  ///
  /// [module] is a HierarchyOccurrence from ModuleStructure
  /// Returns the module's signals.
  /// This method allows for caching/optimization per app.
  ///
  /// Default implementation returns module.signals directly.
  List<SignalOccurrence> getSignalsForModule(HierarchyOccurrence module) =>
      module.signals;

  /// Get all ports (signals with direction) for a module.
  ///
  /// [module] is a HierarchyOccurrence from ModuleStructure
  /// Returns only ports from the module's signals.
  ///
  /// Default implementation filters signals by isPort.
  List<SignalOccurrence> getPortsForModule(HierarchyOccurrence module) =>
      module.signals.where((s) => s.isPort).toList();
}

/// Combined data model: signal definition + waveform data.
///
/// This is app-specific (not shared across apps). Each app wraps
/// the shared signal occurrence with its own `WaveData` representation.
///
/// The signal occurrence is immutable, while data points are fetched
/// from the app's data source.
class WaveData {
  /// The signal definition from the shared module structure.
  /// This SignalOccurrence is never modified by the service.
  final SignalOccurrence port;

  /// The waveform data points [time, value] pairs.
  /// Data type and structure depends on the source (VCD, debugger, etc.).
  final List<Data> data;

  /// Optional metadata specific to this waveform.
  /// Can include timing info, source hints, flags, etc.
  final Map<String, dynamic>? metadata;

  /// Creates a combined signal definition and waveform payload.
  WaveData({required this.port, required this.data, this.metadata});

  /// Get signal name from the shared signal model.
  String get signalName => port.name;

  /// Get signal direction from the shared signal model.
  String get signalDirection => port.direction ?? 'inout';

  /// Get signal width from the shared signal model.
  int get signalWidth => port.width;

  /// Get signal type for VCD rendering. Defaults to 'wire'.
  String get signalType => 'wire';

  /// Check if waveform has any data points.
  bool get hasData => data.isNotEmpty;

  /// Get number of data points.
  int get dataPointCount => data.length;
}
