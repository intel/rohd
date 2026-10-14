// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_data_service_impl.dart
// Concrete implementation of SignalDataService using the repository.
//
// This implementation fetches signal waveform data from the cached
// SignalWaveform objects in the SignalWaveformRepository, wrapping them with
// Port (shared model)
// to create WaveData objects.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// Concrete implementation of SignalDataService using
/// SignalWaveformRepository.
///
/// The repository caches SignalOccurrence metadata and SignalWaveform objects
/// (with waveform data).
/// This implementation:
/// 1. Takes a Port (shared model) as input
/// 2. Uses Port.id to look up the cached SignalWaveform
/// 3. Wraps SignalWaveform.data with the Port to create WaveData
///
/// This decouples the wave display from the repository by providing a
/// clean service interface that takes shared models as input.
class RepositorySignalDataService implements SignalDataService {
  /// Reference to the repository containing cached signal waveform data.
  final SignalWaveformRepository _repository;

  /// Creates a new repository-backed signal data service.
  ///
  /// The repository should already have signal data loaded.
  RepositorySignalDataService(this._repository);

  /// Fetch waveform data for a Port using the repository cache.
  ///
  /// This method:
  /// 1. Takes a Port (shared model from ModuleStructure)
  /// 2. Uses signal.path() to look up the cached SignalWaveform
  /// 3. Wraps SignalWaveform.data with the Port in a WaveData object
  ///
  /// Returns WaveData with the Port and its cached waveform data.
  /// If the waveform is not found in cache, returns WaveData with empty data.
  @override
  Future<WaveData> getSignalData(SignalOccurrence port) async {
    // Look up the waveform in the repository's cache using the address.
    final addr = port.address;
    final waveform = addr != null ? _repository.getWaveform(addr) : null;
    final signal = addr != null ? _repository.getSignal(addr) : null;

    if (waveform == null) {
      // Waveform not cached - return empty WaveData
      return WaveData(
        port: port, // ◄─ Shared model, immutable
        data: [], // Empty data
        metadata: {'source': 'repository', 'cached': false},
      );
    }

    // Waveform found - wrap its data with the Port (shared model)
    return WaveData(
      port: port, // ◄─ Shared model, immutable
      data: waveform.data, // Waveform data from cached SignalWaveform
      metadata: {
        'source': 'repository',
        'cached': true,
        'path': signal?.path(),
      },
    );
  }

  /// Get all signals for a module.
  @override
  List<SignalOccurrence> getSignalsForModule(HierarchyOccurrence module) =>
      module.signals;

  /// Get all ports for a module.
  ///
  /// This implementation returns the module's ports (signals with direction).
  @override
  List<SignalOccurrence> getPortsForModule(HierarchyOccurrence module) =>
      module.signals.where((s) => s.isPort).toList();
}
