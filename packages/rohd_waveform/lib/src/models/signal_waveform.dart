// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_waveform.dart
// Waveform data for a signal, indexed by signal ID.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/rohd_hierarchy.dart';

import 'package:rohd_waveform/src/models/data.dart';
import 'package:rohd_waveform/src/models/waveform_data.dart';

/// Function type for looking up signal metadata by ID.
typedef SignalLookup = SignalOccurrence? Function(String signalId);

/// Waveform data for a signal.
///
/// This class holds the time-series waveform data for a signal and provides
/// efficient lookup methods. The signal's structural metadata (name, type,
/// width, etc.) is stored in `rohd_hierarchy.SignalOccurrence` and can be
/// accessed via the `signal` property if a lookup function is registered.
///
/// Pattern: Similar to SchematicPortData in vscode-schematic-viewer, this
/// class maintains waveform data with a backpointer (`signalId`) to the
/// corresponding metadata in the hierarchy.
///
/// Usage:
/// ```dart
/// // Register the signal lookup function (typically done once by repository)
/// SignalWaveform.signalLookup = (id) => repository.getSignalById(id);
///
/// // Now all SignalWaveform instances can access their metadata
/// final waveform = SignalWaveform(signalId: 'clk');
/// print(waveform.name);  // Uses lookup to get SignalOccurrence.name
/// ```
class SignalWaveform {
  /// The ID of the signal this waveform data belongs to.
  /// Use this to look up SignalOccurrence metadata from the hierarchy.
  final String signalId;

  /// The waveform data points (time, value pairs).
  final List<Data> data;

  /// Static signal lookup function for resolving signal metadata.
  /// Set this via [signalLookup] before accessing metadata properties.
  static SignalLookup? signalLookup;

  /// Clears the signal lookup function.
  static void clearSignalLookup() {
    signalLookup = null;
  }

  /// Whether this waveform was computed/synthesized (e.g. gate evaluation)
  /// rather than directly fetched from the VM service.
  bool isComputed;

  /// Override width for computed sub-field waveforms whose signal metadata
  /// is not available via the hierarchy lookup.
  int? overrideWidth;

  /// Override display name for computed sub-field waveforms.
  String? overrideName;

  /// Creates a new SignalWaveform.
  SignalWaveform({
    required this.signalId,
    List<Data>? data,
    this.isComputed = false,
    this.overrideWidth,
    this.overrideName,
  }) : data = data ?? [];

  /// Creates an empty SignalWaveform for a signal.
  factory SignalWaveform.empty(String signalId) =>
      SignalWaveform(signalId: signalId);

  /// Creates a SignalWaveform from WaveformData.
  factory SignalWaveform.fromWaveformData(WaveformData waveformData) =>
      SignalWaveform(
        signalId: waveformData.signalId,
        data: List.from(waveformData.data),
        isComputed: waveformData.isComputed,
      );

  /// Creates a copy of an existing SignalWaveform.
  ///
  /// This is needed when the same signal is added to the monitor list multiple
  /// times (e.g., for performance studies or side-by-side comparison). Each
  /// monitor entry must have its own SignalWaveform instance to avoid sharing
  /// state between rows in the waveform panel.
  factory SignalWaveform.copyFrom(SignalWaveform other) => SignalWaveform(
        signalId: other.signalId,
        data: List.from(other.data),
        isComputed: other.isComputed,
        overrideWidth: other.overrideWidth,
        overrideName: other.overrideName,
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Metadata accessors (via backpointer lookup)
  // ─────────────────────────────────────────────────────────────────────────

  /// The corresponding SignalOccurrence metadata, if available.
  /// Returns null if no lookup function is registered or signal not found.
  SignalOccurrence? get signal => signalLookup?.call(signalId);

  /// Alias for signalId for convenience.
  String get id => signalId;

  /// The canonical hierarchical path for waveform lookup. Delegates to
  /// [SignalOccurrence.path] when available, falls back to [signalId].
  String get hierarchyPath => signal?.path() ?? signalId;

  /// The signal name (from metadata). Returns overrideName or signalId if
  /// lookup fails.
  String get name => signal?.name ?? overrideName ?? signalId;

  /// The signal type for VCD rendering. Always 'wire' in post-synthesis.
  String get type => 'wire';

  /// The signal width in bits (from metadata). Returns overrideWidth or 1 if
  /// lookup fails.
  int get width => signal?.width ?? overrideWidth ?? 1;

  /// The signal direction (from metadata). Returns null for internal signals.
  String? get direction => signal?.direction;

  /// The full hierarchical path (from metadata).
  String? get fullPath => signal?.path();

  /// Whether this signal is a port (has direction).
  bool get isPort => signal?.isPort ?? false;

  // ─────────────────────────────────────────────────────────────────────────
  // Waveform data properties
  // ─────────────────────────────────────────────────────────────────────────

  /// Whether this waveform has any data points.
  bool get isEmpty => data.isEmpty;

  /// Whether this waveform has data points.
  bool get isNotEmpty => data.isNotEmpty;

  /// The number of data points in this waveform.
  int get length => data.length;

  /// Appends waveform data points.
  ///
  /// If [sortByTime] is true, the data will be sorted by time after appending.
  void appendData(List<Data> newData, {bool sortByTime = false}) {
    data.addAll(newData);
    if (sortByTime) {
      data.sort((a, b) => a.time.compareTo(b.time));
      if (data.length > 1) {
        // Keep the last value for duplicate timestamps to reflect most recent
        // updates when overlapping windows are appended.
        final deduped = <Data>[];
        for (final point in data) {
          if (deduped.isNotEmpty && deduped.last.time == point.time) {
            deduped[deduped.length - 1] = point;
          } else {
            deduped.add(point);
          }
        }
        data
          ..clear()
          ..addAll(deduped);
      }
    }
  }

  /// Appends waveform data from a [WaveformData] object.
  void appendWaveformData(
    WaveformData waveformData, {
    bool sortByTime = false,
  }) {
    appendData(waveformData.data, sortByTime: sortByTime);
    if (waveformData.isComputed) {
      isComputed = true;
    }
  }

  /// Clears all waveform data.
  void clearData() {
    data.clear();
  }

  /// Gets the value at a specific time using binary search.
  ///
  /// Returns the value of the last data point at or before the given time.
  /// If no data point exists at or before the time, returns the first value.
  String getValueByTime(int time) {
    if (data.isEmpty) {
      return '';
    }

    var low = 0;
    var high = data.length - 1;
    var res = -1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      if (data[mid].time <= time) {
        res = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (res != -1) {
      return data[res].value;
    } else {
      return data.first.value;
    }
  }

  /// Finds the index of the data point at or after the given time.
  /// Returns -1 if no data point is at or after the given time.
  /// O(log n) complexity.
  int getNextDataPointIndexAfter(int time) {
    if (data.isEmpty) {
      return -1;
    }

    var low = 0;
    var high = data.length - 1;
    var resultIndex = -1;

    while (low <= high) {
      final mid = low + (high - low) ~/ 2;
      final midData = data[mid];

      if (midData.time >= time) {
        resultIndex = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    return resultIndex;
  }

  /// Finds the index of the data point at or before the given time.
  /// Returns -1 if no data point is at or before the given time.
  /// O(log n) complexity.
  int getPreviousDataPointIndexBefore(int time) {
    if (data.isEmpty) {
      return -1;
    }

    var low = 0;
    var high = data.length - 1;
    var resultIndex = -1;

    while (low <= high) {
      final mid = low + (high - low) ~/ 2;
      final midData = data[mid];

      if (midData.time <= time) {
        resultIndex = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return resultIndex;
  }

  /// Gets the next data point index from the current time.
  /// If there is a data point at exactly the current time, returns the index
  /// of the first data point at a strictly later time.
  /// Handles duplicate timestamps correctly.
  /// Returns -1 if there is no next data point.
  int getNextDataPointIndex(int currentTime) {
    var idx = getNextDataPointIndexAfter(currentTime);
    if (idx == -1) {
      return -1;
    }
    // Skip past all entries at currentTime to find a strictly later one.
    while (idx < data.length && data[idx].time == currentTime) {
      idx++;
    }
    return idx < data.length ? idx : -1;
  }

  /// Gets the previous data point index from the current time.
  /// If there is a data point at exactly the current time, returns the index
  /// of the last data point at a strictly earlier time.
  /// Handles duplicate timestamps correctly.
  /// Returns -1 if there is no previous data point.
  int getPreviousDataPointIndex(int currentTime) {
    var idx = getPreviousDataPointIndexBefore(currentTime);
    if (idx == -1) {
      return -1;
    }
    // Skip back past all entries at currentTime to find a strictly earlier one.
    while (idx >= 0 && data[idx].time == currentTime) {
      idx--;
    }
    return idx >= 0 ? idx : -1;
  }

  @override
  String toString() => 'SignalWaveform($signalId, ${data.length} points)';

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'signalId': signalId,
        'data': data.map((e) => e.toJson()).toList(),
      };

  /// Creates from JSON.
  factory SignalWaveform.fromJson(Map<String, dynamic> json) => SignalWaveform(
        signalId: json['signalId'] as String,
        data: (json['data'] as List?)
                ?.map((e) => Data.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
