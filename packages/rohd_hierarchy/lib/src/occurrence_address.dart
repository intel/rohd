// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// occurrence_address.dart
// Efficient hierarchical address using indices instead of strings.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:rohd_hierarchy/src/hierarchy_occurrence.dart';

/// Efficient hierarchical address using indices instead of strings.
///
/// Format: [index0, index1, ...] or [] for root.
/// Example: [0, 2, 4] means root's 0th child, then 2nd child of that, then
/// the 4th child (occurrence) or 4th signal, depending on context.
///
/// Advantages:
/// - O(1) address creation (just append index)
/// - O(depth) tree navigation (direct array indexing)
/// - Deterministic serialization (no parsing needed)
/// - Natural alignment with waveform dictionary (integer indices)
/// - Supports hierarchical queries (ancestor matching, batching by prefix)
///
/// This replaces string-based path lookups with typed, semantic addressing.
@immutable
class OccurrenceAddress {
  /// Path through tree as indices stored as immutable list.
  /// Empty list represents the root occurrence.
  /// Non-empty list: indices navigate through the hierarchy. The last index
  /// refers to either a child occurrence or a signal, depending on context.
  final List<int> path;

  /// Create a hierarchy address from a path list.
  const OccurrenceAddress(this.path);

  /// Root address (empty path).
  static const OccurrenceAddress root = OccurrenceAddress(<int>[]);

  /// Create a child address by appending an occurrence index.
  /// Use this when navigating to a child occurrence.
  OccurrenceAddress child(int childIndex) =>
      OccurrenceAddress([...path, childIndex]);

  /// Create a signal address by appending signal index.
  /// Use this when addressing a signal within current occurrence.
  OccurrenceAddress signal(int signalIndex) =>
      OccurrenceAddress([...path, signalIndex]);

  /// Serialize to a dot-separated string suitable for use as a JSON key.
  ///
  /// Examples: `""` (root), `"0"`, `"0.2.4"`.
  /// Round-trips with [OccurrenceAddress.fromDotString].
  String toDotString() => path.join('.');

  /// Deserialize from a dot-separated string produced by [toDotString].
  ///
  /// An empty string returns [root].
  factory OccurrenceAddress.fromDotString(String s) {
    if (s.isEmpty) {
      return root;
    }
    return OccurrenceAddress(s.split('.').map(int.parse).toList());
  }

  @override
  String toString() {
    if (path.isEmpty) {
      return '[ROOT]';
    }
    return '[${path.join(".")}]';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OccurrenceAddress &&
          const ListEquality<int>().equals(path, other.path);

  @override
  int get hashCode => Object.hashAll(path);

  /// Resolve a pathname string (e.g. `"Top/counter/clk"` or
  /// `"Top.counter.clk"`) to a [OccurrenceAddress] by walking [root].
  ///
  /// Supports both `/` and `.` as separators.  If the first segment
  /// matches [root]'s name, it is skipped — the root
  /// occurrence is always at the empty address.
  ///
  /// The last segment is first tried as a **signal** name within the
  /// current occurrence; if that fails it is tried as a **child**
  /// occurrence name.
  /// This mirrors the pathname convention where a signal path has one more
  /// segment than its parent module path.
  ///
  /// Returns `null` if any segment cannot be resolved.
  ///
  /// ```dart
  /// final addr = OccurrenceAddress.tryFromPathname('Top/cpu/clk', root);
  /// if (addr != null) {
  ///   final signal = service.signalByAddress(addr);
  /// }
  /// ```
  static OccurrenceAddress? tryFromPathname(
    String pathname,
    HierarchyOccurrence root,
  ) {
    final rootAddr = root.address ?? OccurrenceAddress.root;
    final parts = pathname
        .replaceAll('.', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    // Skip leading segment that matches the root name.
    final segments =
        parts.isNotEmpty && parts.first == root.name ? parts.skip(1) : parts;

    ({HierarchyOccurrence node, OccurrenceAddress addr})? step(
      ({HierarchyOccurrence node, OccurrenceAddress addr})? cur,
      String segment,
    ) {
      if (cur == null) {
        return null;
      }
      final si = cur.node.signalIndexByName(segment);
      if (identical(segment, segments.last) && si >= 0) {
        return (node: cur.node, addr: cur.addr.signal(si));
      }
      final ci = cur.node.childIndexByName(segment);
      return ci >= 0
          ? (node: cur.node.children[ci], addr: cur.addr.child(ci))
          : null;
    }

    return segments.fold<({HierarchyOccurrence node, OccurrenceAddress addr})?>(
        (node: root, addr: rootAddr), step)?.addr;
  }
}
