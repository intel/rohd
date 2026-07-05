// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// prefix_query.dart
// Prefix-substring query implementation for hierarchy search.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd_hierarchy/src/hierarchy_query.dart';

/// Prefix-substring query: segments are matched via `startsWith` (signals)
/// or `contains` (occurrences) at successive hierarchy depths.
class PrefixQuery extends HierarchyQuery {
  /// Non-empty segments parsed from the raw query.
  late final List<String> segments;

  /// Create a prefix query from [rawQuery].
  PrefixQuery(
    super.rawQuery, {
    super.target = SearchTarget.signals,
  }) : super(crossesBoundaries: false) {
    segments = rawQuery
        .replaceAll('.', '/')
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  int get segmentCount => segments.length;

  @override
  Set<int> matchOccurrence(String occurrenceName, int stateIndex) {
    if (stateIndex >= segments.length) {
      return {stateIndex};
    }
    final name = occurrenceName;
    if (name.contains(segments[stateIndex])) {
      return {stateIndex + 1};
    }
    return const {};
  }

  @override
  bool matchSignal(String signalName, int stateIndex) {
    if (stateIndex >= segments.length) {
      return true;
    }
    // Only the last segment can match a signal name.
    if (stateIndex != segments.length - 1) {
      return false;
    }
    return signalName.startsWith(segments[stateIndex]);
  }

  @override
  bool isComplete(int stateIndex) => stateIndex >= segments.length;
}
