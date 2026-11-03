// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// design_session.dart
// Public, transport-independent ROHD design interaction contracts.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// A capability exposed by a [RohdDesignSession].
enum RohdDesignCapability {
  /// The session can inspect the synthesized design hierarchy.
  hierarchy,

  /// The session can traverse design connectivity.
  connectivity,

  /// The session can query waveform data.
  waveform,

  /// The session can select signals in connected clients.
  crossProbe,
}

/// Identifies one loaded design revision within a [RohdDesignSession].
///
/// Handles returned for an older epoch are invalid after a design reload.
@immutable
class RohdDesignEpoch {
  /// Creates a design epoch.
  const RohdDesignEpoch(this.value);

  /// Monotonically increasing design revision.
  final int value;

  @override
  bool operator ==(Object other) =>
      other is RohdDesignEpoch && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RohdDesignEpoch($value)';
}

/// Availability and metadata reported by a [RohdDesignSession].
class RohdDesignStatus {
  /// Creates a session status snapshot.
  RohdDesignStatus({
    required this.epoch,
    required Iterable<RohdDesignCapability> capabilities,
    this.designName,
    this.isReady = true,
  }) : capabilities = Set<RohdDesignCapability>.unmodifiable(capabilities);

  /// Revision that scopes all handles returned by this status.
  final RohdDesignEpoch epoch;

  /// Capabilities currently available from the design session.
  final Set<RohdDesignCapability> capabilities;

  /// Human-readable design name, when known.
  final String? designName;

  /// Whether a design is ready to serve queries.
  final bool isReady;

  /// Whether [capability] can currently be used.
  bool supports(RohdDesignCapability capability) =>
      capabilities.contains(capability);
}

/// Result page for bounded search and traversal requests.
class RohdPage<T> {
  /// Creates a response page.
  RohdPage({required Iterable<T> items, this.nextPageToken})
      : items = List<T>.unmodifiable(items);

  /// Values returned in this page.
  final List<T> items;

  /// Token to supply to the next equivalent request, if more values exist.
  final String? nextPageToken;
}

/// Options common to hierarchy searches and connectivity traversals.
class RohdQueryOptions {
  /// Creates query options.
  const RohdQueryOptions({this.pageSize = 100, this.pageToken});

  /// Maximum number of records to return.
  final int pageSize;

  /// Continuation token from a prior response.
  final String? pageToken;
}

/// A packed signal value sampled from waveform data.
class RohdSignalValue {
  /// Creates a waveform value for [signal] at [time].
  const RohdSignalValue({
    required this.signal,
    required this.time,
    required this.value,
    this.sampleTime,
  });

  /// Signal occurrence to which this value belongs.
  final SignalOccurrence signal;

  /// Simulation time requested for the lookup.
  final int time;

  /// Packed ROHD value at or immediately before [time].
  final String value;

  /// Simulation time of the matching recorded change, when available.
  final int? sampleTime;
}

/// Hierarchy operations offered by a [RohdDesignSession].
abstract interface class RohdHierarchySession {
  /// Canonical hierarchy whose occurrences are used as session handles.
  ///
  /// A session invalidates handles when its [RohdDesignStatus.epoch] changes.
  HierarchyService get hierarchy;

  /// Resolves a cell by absolute hierarchy path.
  Future<HierarchyOccurrence?> findCell(String path);

  /// Resolves a signal by absolute hierarchy path.
  Future<SignalOccurrence?> findSignal(String path);

  /// Resolves a port by absolute hierarchy path.
  Future<SignalOccurrence?> findPort(String path);

  /// Returns bounded cell-path completions for [prefix].
  Future<List<String>> completeCellPaths(String prefix, {int limit = 20});

  /// Returns bounded signal-path completions for [prefix].
  Future<List<String>> completeSignalPaths(String prefix, {int limit = 20});

  /// Returns bounded port-path completions for [prefix].
  Future<List<String>> completePortPaths(String prefix, {int limit = 20});

  /// Finds cells matching [pattern] under an optional [root].
  Future<RohdPage<HierarchyOccurrence>> findCells(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Finds signals matching [pattern] under an optional [root].
  Future<RohdPage<SignalOccurrence>> findSignals(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Finds port signals matching [pattern] under an optional [root].
  Future<RohdPage<SignalOccurrence>> findPorts(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });
}

/// Connectivity operations offered by a [RohdDesignSession].
abstract interface class RohdConnectivitySession {
  /// Returns signals that drive [signal].
  Future<RohdPage<SignalOccurrence>> fanin(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Returns signals consumed by [signal].
  Future<RohdPage<SignalOccurrence>> fanout(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });
}

/// Transport-independent entry point for inspecting a live ROHD design.
///
/// Implementations maintain a canonical [HierarchyService] and return its
/// occurrence objects as handles. DTD, MCP, and other transports serialize
/// occurrence addresses or paths at their boundary, then resolve them back to
/// handles owned by the receiving session. All handles are valid only while
/// [status] reports the same [RohdDesignStatus.epoch].
abstract interface class RohdDesignSession
    implements RohdHierarchySession, RohdConnectivitySession {
  /// Returns the current session status and capability set.
  Future<RohdDesignStatus> status();

  /// Gets [signal]'s value at or immediately before [time].
  ///
  /// When [time] is omitted, returns the latest recorded simulation value.
  Future<RohdSignalValue> getSignalValue(SignalOccurrence signal, {int? time});
}

/// Synchronous operations exposed by an in-process design session.
///
/// Debugger expression evaluation can invoke these operations while the
/// target isolate is paused. Transport clients should otherwise depend on
/// [RohdDesignSession]'s asynchronous contract.
abstract interface class RohdSynchronousDesignSession {
  /// Returns the current session status.
  RohdDesignStatus statusNow();

  /// Resolves a cell by absolute hierarchy path.
  HierarchyOccurrence? findCellNow(String path);

  /// Resolves a signal by absolute hierarchy path.
  SignalOccurrence? findSignalNow(String path);

  /// Resolves a port by absolute hierarchy path.
  SignalOccurrence? findPortNow(String path);

  /// Returns bounded cell-path completions for [prefix].
  List<String> completeCellPathsNow(String prefix, {int limit = 20});

  /// Returns bounded signal-path completions for [prefix].
  List<String> completeSignalPathsNow(String prefix, {int limit = 20});

  /// Returns bounded port-path completions for [prefix].
  List<String> completePortPathsNow(String prefix, {int limit = 20});

  /// Finds cells matching [pattern].
  RohdPage<HierarchyOccurrence> findCellsNow(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Finds signals matching [pattern].
  RohdPage<SignalOccurrence> findSignalsNow(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Finds port signals matching [pattern].
  RohdPage<SignalOccurrence> findPortsNow(
    String pattern, {
    HierarchyOccurrence? root,
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Returns signals that drive [signal].
  RohdPage<SignalOccurrence> faninNow(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Returns signals consumed by [signal].
  RohdPage<SignalOccurrence> fanoutNow(
    SignalOccurrence signal, {
    bool transparent = false,
    RohdQueryOptions options = const RohdQueryOptions(),
  });

  /// Gets [signal]'s value at or immediately before [time].
  ///
  /// When [time] is omitted, returns the latest recorded simulation value.
  RohdSignalValue getSignalValueNow(SignalOccurrence signal, {int? time});
}
