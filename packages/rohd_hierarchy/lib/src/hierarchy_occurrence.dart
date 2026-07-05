// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_occurrence.dart
// An occurrence of a module definition in the unfolded hierarchy tree.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd_hierarchy/src/occurrence_address.dart';
import 'package:rohd_hierarchy/src/signal_occurrence.dart';

/// An occurrence of a module definition in the unfolded hierarchy tree.
///
/// This is the core structural data model, independent of waveform data.
/// Path strings are computed on demand from parent references rather than
/// stored — call [path] with your desired separator.
class HierarchyOccurrence {
  /// Display name of this occurrence (instance name within its parent).
  final String name;

  /// Definition (module) name for this occurrence.
  final String? definition;

  /// Whether this occurrence is a primitive cell (gate, operator, register,
  /// etc.) whose internal structure is not useful for design navigation.
  ///
  /// Set by the parser/adapter that creates the occurrence.  The netlist
  /// adapter sets this for cells that lack a module definition in the JSON or
  /// whose definition starts with `$` (netlist built-in primitives).
  /// Tool-specific primitives (e.g. ROHD's FlipFlop → `$dff`) are handled by
  /// the synthesizer mapping them to `$`-prefixed definitions before the JSON
  /// is written.
  final bool isPrimitive;

  /// Signals within this occurrence (includes both internal signals and
  /// ports).  Empty for leaf occurrences.
  final List<SignalOccurrence> signals;

  /// Child occurrences. Populated from sub-modules in the hierarchy.
  final List<HierarchyOccurrence> children;

  /// Hierarchical address for this occurrence.
  /// Assigned by [buildAddresses] to enable efficient navigation.
  /// Format: [child0, child1, ..., childN] for nested occurrences.
  OccurrenceAddress? get address => _address;
  OccurrenceAddress? _address;

  /// Parent occurrence, or `null` for the root.
  /// Set by [buildAddresses].
  HierarchyOccurrence? get parent => _parent;
  HierarchyOccurrence? _parent;

  /// Creates a [HierarchyOccurrence] with the given properties.
  HierarchyOccurrence({
    required this.name,
    this.definition,
    this.isPrimitive = false,
    List<SignalOccurrence>? signals,
    List<HierarchyOccurrence>? children,
  })  : signals = signals ?? [],
        children = children ?? [];

  /// Compute the full hierarchical path by walking up the parent chain.
  ///
  /// Uses [separator] between path segments (default `/`).
  /// Returns just [name] for the root (no parent).
  String path({String separator = '/'}) {
    if (_parent == null) {
      return name;
    }
    final parts = <String>[];
    HierarchyOccurrence? cur = this;
    while (cur != null) {
      parts.add(cur.name);
      cur = cur._parent;
    }
    return parts.reversed.join(separator);
  }

  /// Returns only signals that are ports (have a direction).
  List<SignalOccurrence> get ports => signals.where((s) => s.isPort).toList();

  // ───────────────── Name → offset (index) lookups ─────────────────

  /// Lazily-built index: child name → offset in [children].
  Map<String, int>? _childNameIndex;

  /// Lazily-built index: signal name → offset in [signals].
  Map<String, int>? _signalNameIndex;

  /// Return the offset (index) of the child with [name] in [children],
  /// or -1 if not found.  Case-sensitive.
  /// O(1) after first call (lazily builds index).
  int childIndexByName(String name) {
    _childNameIndex ??= {
      for (var i = 0; i < children.length; i++) children[i].name: i,
    };
    return _childNameIndex![name] ?? -1;
  }

  /// Return the offset (index) of the signal with [name] in [signals],
  /// or -1 if not found.  Case-sensitive.
  /// O(1) after first call (lazily builds index).
  int signalIndexByName(String name) {
    _signalNameIndex ??= {
      for (var i = 0; i < signals.length; i++) signals[i].name: i,
    };
    return _signalNameIndex![name] ?? -1;
  }

  /// Whether [cellType] represents a netlist built-in primitive cell type.
  ///
  /// Returns `true` for `$`-prefixed types (`$mux`, `$dff`, `$and`, etc.)
  /// which are netlist built-in operators and primitives.
  ///
  /// Tool-specific primitive types (e.g. ROHD's `FlipFlop`) should be
  /// handled by the producer: the synthesizer should map them to
  /// `$`-prefixed cell types in the JSON output, or the adapter should
  /// set [isPrimitive] on the occurrence at construction time.
  ///
  /// Use this before a [HierarchyOccurrence] exists (e.g. when deciding
  /// whether to recurse into a netlist cell definition).  For an existing
  /// occurrence, use the getter [isPrimitiveCell] instead.
  static bool isPrimitiveType(String cellType) => cellType.startsWith(r'$');

  /// Whether this occurrence represents a primitive cell that should be hidden
  /// from the occurrence tree.
  ///
  /// Checks the [isPrimitive] field (set by the adapter at construction time)
  /// and falls back to [isPrimitiveType] on the occurrence's [definition].
  bool get isPrimitiveCell =>
      isPrimitive || (definition != null && isPrimitiveType(definition!));

  /// Returns only input signals.
  List<SignalOccurrence> get inputs =>
      signals.where((s) => s.direction == 'input').toList();

  /// Returns only output signals.
  List<SignalOccurrence> get outputs =>
      signals.where((s) => s.direction == 'output').toList();

  /// Number of port signals in this occurrence.
  int get portCount => signals.where((s) => s.isPort).length;

  /// Finds the sub-field [SignalOccurrence] entries for a struct/array signal.
  ///
  /// Given a `parentSignal` that has `logicType` metadata (struct fields or
  /// array dims), looks up the expected sub-field signal names in this
  /// occurrence's signal list using the Namer/Sanitizer naming convention:
  ///   `{parentSignalName}_{fieldName}`
  ///
  /// Returns a list of resolved sub-field signals in field order.
  /// Entries may be null if a particular sub-field signal wasn't found
  /// (e.g. the netlist didn't emit it, or it was optimized away).
  List<({SignalOccurrence? signal, String fieldLabel, int width, int startBit})>
      findSubFieldSignals(SignalOccurrence parentSignal) {
    final descriptors = parentSignal.subFieldDescriptors;
    if (descriptors.isEmpty) {
      return const [];
    }

    return descriptors.map((d) {
      final idx = signalIndexByName(d.expectedName);
      final sig = idx >= 0 ? signals[idx] : null;
      return (
        signal: sig,
        fieldLabel: d.fieldLabel,
        width: d.width,
        startBit: d.startBit,
      );
    }).toList();
  }

  /// Collect all signals under this occurrence in depth-first order.
  ///
  /// Visits this occurrence's [signals] first, then recurses into
  /// [children] in order.  Useful for flat iteration or counting, but
  /// signals should always be identified by their [OccurrenceAddress] or
  /// path — never by a positional index in this list.
  ///
  /// Production code should use [signalCount], [computedSignalCount], or
  /// a recursive visitor instead of materializing the full list.
  @visibleForTesting
  List<SignalOccurrence> depthFirstSignals() =>
      [...signals, ...children.expand((c) => c.depthFirstSignals())];

  /// Total number of signals in this subtree (O(n) recursive count).
  ///
  /// Equivalent to `depthFirstSignals().length` but avoids allocating the
  /// intermediate list.
  int get signalCount =>
      signals.length + children.fold<int>(0, (sum, c) => sum + c.signalCount);

  /// Number of computed signals in this subtree.
  ///
  /// Equivalent to
  /// `depthFirstSignals().where((s) => s.isComputed).length`
  /// but avoids allocating the intermediate list.
  int get computedSignalCount =>
      signals.where((s) => s.isComputed).length +
      children.fold<int>(0, (sum, c) => sum + c.computedSignalCount);

  /// Build hierarchical addresses for this occurrence and all descendants.
  ///
  /// This performs a single O(n) tree traversal to assign [OccurrenceAddress]
  /// to every occurrence and signal in the tree. Call this once after tree
  /// construction to enable efficient address-based navigation.
  ///
  /// **Signal address ordering**: ports (signals with a non-null
  /// [SignalOccurrence.direction]) are assigned indices first
  /// (`0 .. portCount-1`), followed by internal signals
  /// (`portCount .. signals.length-1`).  Within each group the
  /// original list order is preserved.
  ///
  /// This means a port's [SignalOccurrence.portIndex] always equals its
  /// signal address index, which consumers (e.g. schematic hyperedges) can
  /// rely on remaining stable across incremental expansion.
  ///
  /// Example:
  /// ```dart
  /// root.buildAddresses();  // Assign addresses to all occurrences/signals
  /// final signalAddr = signals[0].address;  // Now available
  /// ```
  void buildAddresses([OccurrenceAddress startAddr = OccurrenceAddress.root]) {
    _address = startAddr;

    // Assign ports first, then internal signals, so that port indices
    // are stable across incremental hierarchy expansion.
    var idx = 0;
    for (final s in signals) {
      if (s.isPort) {
        s
          ..address = startAddr.signal(idx++)
          ..parent = this;
      }
    }
    for (final s in signals) {
      if (!s.isPort) {
        s
          ..address = startAddr.signal(idx++)
          ..parent = this;
      }
    }

    for (final (i, c) in children.indexed) {
      c
        .._parent = this
        ..buildAddresses(startAddr.child(i));
    }
  }
}
