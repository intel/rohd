// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_service_signal_rohd_waveform.dart
// VM service adapter — thin subclass of BaseSignalWaveformApi.
//
// All shared algorithm (snapshot expansion, evaluator, synthesis, module
// expansion) lives in BaseSignalWaveformApi.  This subclass adds only
// VM-specific behavior: signal tracking, address-lookup pushdown to
// transport, DFS load future, and parent↔child diagnostic logging.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/base_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_transport.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

/// VM service adapter that wraps [VmServiceTransport] via
/// [BaseSignalWaveformApi].
///
/// All shared algorithm lives in the base class.  This subclass adds:
/// - SignalOccurrence tracking (registers signals with transport for breakpoint
///   auto-fetch)
/// - Address-lookup pushdown to transport on hierarchy load
/// - Parent↔child port diagnostic logging
/// - `rootName` setter for evaluator invalidation
class VmServiceSignalWaveformApi extends BaseSignalWaveformApi {
  /// The underlying VM service transport.
  final VmServiceTransport vmTransport;

  /// Deduplicating future for dictionary + gate netlist loading.
  Future<bool>? _dfsLoadFuture;

  /// Creates a new adapter for the given VM service transport.
  VmServiceSignalWaveformApi(this.vmTransport) : super(vmTransport);

  /// Root instance name hint.
  ///
  /// Setting this invalidates the cached evaluator so that the next
  /// evaluation picks up any structural changes.
  // ignore: avoid_setters_without_getters
  set rootName(String? value) {}

  // ─────────────────────────────────────────────────────────────────────────
  // Overrides from BaseSignalWaveformApi
  // ─────────────────────────────────────────────────────────────────────────

  /// Sets the module structure and pushes address lookups to the transport.
  @override
  Future<void> setExternalStructure(ModuleStructure structure) async {
    _dfsLoadFuture = null;
    await super.setExternalStructure(structure);
    await _ensureAddressLookups();
  }

  /// Ensure the DFS dictionary is loaded and address lookups are pushed
  /// to the transport for breakpoint-triggered compact fetches.
  Future<bool> _ensureAddressLookups() =>
      _dfsLoadFuture ??= _doEnsureAddressLookups();

  Future<bool> _doEnsureAddressLookups() async {
    final hs = hierarchyService;
    if (hs != null) {
      vmTransport.setAddressLookups(
        signalIdToAddress: (id) => hs.pathnameToAddress(id)?.toDotString(),
        addressToSignalId: (addr) => hs.addressToPathname(
          OccurrenceAddress.fromDotString(addr),
          asSignal: true,
        ),
      );
      debugPrint('[VmSignalApi] Address lookups pushed to transport');
    }

    // Force a major GC after loading the design structure.
    unawaited(vmTransport.requestGarbageCollection());
    return true;
  }

  /// Register tracked signals with the transport for breakpoint auto-fetch.
  @override
  void onTrackSignals(List<String> signalIds) {
    signalIds.forEach(vmTransport.trackSignal);
  }

  /// VM-specific post-expansion diagnostic: log parent↔child port
  /// value mismatches.
  @override
  void onSnapshotExpanded(
    Map<String, dynamic> compact,
    Map<String, Map<String, dynamic>> result,
  ) {
    _logClientPortDiagnostics(compact, result);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VM-specific methods
  // ─────────────────────────────────────────────────────────────────────────

  /// Refresh waveform data from the VM service.
  Future<void> refresh() async {
    clearCache();
  }

  /// Clear all cached data (delegates to base + resets DFS future).
  @override
  void clearCache() {
    _dfsLoadFuture = null;
    super.clearCache();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Diagnostics
  // ─────────────────────────────────────────────────────────────────────────

  /// Diagnostic: log parent↔child port value mismatches after expansion.
  void _logClientPortDiagnostics(
    Map<String, dynamic> compact,
    Map<String, Map<String, dynamic>> result,
  ) {
    final time = compact['time'];
    final rawValues = compact['v'] as Map<String, dynamic>? ?? {};
    final hs = hierarchyService;

    for (final signalId in result.keys) {
      final parts = signalId.split('/');
      if (parts.length < 3) {
        continue;
      }
      final leafName = parts.last;
      if (leafName.contains('_') && !leafName.startsWith('_')) {
        continue;
      }
      final parentScope = parts.sublist(0, parts.length - 2).join('/');
      final parentId = '$parentScope/$leafName';
      final parentEntry = result[parentId];
      if (parentEntry == null) {
        continue;
      }

      final childVal = result[signalId]!['value'] as String;
      final parentVal = parentEntry['value'] as String;
      if (childVal == parentVal) {
        continue;
      }

      final childAddr = hs != null
          ? OccurrenceAddress.tryFromPathname(signalId, hs.root)?.toDotString()
          : '?';
      final parentAddr = hs != null
          ? OccurrenceAddress.tryFromPathname(parentId, hs.root)?.toDotString()
          : '?';

      debugPrint('[ClientDiag] MISMATCH at t=$time:');
      debugPrint(
        '  child:  $signalId (addr=$childAddr) = $childVal '
        '(raw=${rawValues[childAddr]})',
      );
      debugPrint(
        '  parent: $parentId (addr=$parentAddr) = $parentVal '
        '(raw=${rawValues[parentAddr]})',
      );
    }
  }
}
