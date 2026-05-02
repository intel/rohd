// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_models.dart
// Generic hierarchy data models for source-agnostic navigation.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The kind of node in the hardware hierarchy.
enum HierarchyKind {
  /// A module definition in the hierarchy.
  module,

  /// An instance of a module in the hierarchy.
  instance,
}

/// Efficient hierarchical address using indices instead of strings.
///
/// Format: [moduleIndex0, moduleIndex1, ..., signalIndex] or [] for root.
/// Example: [0, 2, 4] means root's 0th child, then 2nd child of that, then 4th
/// signal.
///
/// Advantages:
/// - O(1) address creation (just append index)
/// - O(depth) tree navigation (direct array indexing)
/// - Deterministic serialization (no parsing needed)
/// - Natural alignment with waveform dictionary (integer indices)
/// - Supports hierarchical queries (ancestor matching, batching by prefix)
///
/// This replaces string-based scopeId lookups with typed, semantic addressing.
@immutable
class HierarchyAddress {
  /// Path through tree as indices stored as immutable list.
  /// Empty list represents root node.
  /// Non-empty list: all but last are module indices, last is signal index.
  final List<int> path;

  /// Create a hierarchy address from a path list.
  const HierarchyAddress(this.path);

  /// Root address (empty path).
  static const HierarchyAddress root = HierarchyAddress(<int>[]);

  /// Create a child address by appending module index.
  /// Use this when navigating to a child module.
  HierarchyAddress child(int moduleIndex) =>
      HierarchyAddress([...path, moduleIndex]);

  /// Create a signal address by appending signal index.
  /// Use this when addressing a signal within current module.
  HierarchyAddress signal(int signalIndex) =>
      HierarchyAddress([...path, signalIndex]);

  /// Serialize to a dot-separated string suitable for use as a JSON key.
  ///
  /// Examples: `""` (root), `"0"`, `"0.2.4"`.
  /// Round-trips with [HierarchyAddress.fromDotString].
  String toDotString() => path.join('.');

  /// Deserialize from a dot-separated string produced by [toDotString].
  ///
  /// An empty string returns [root].
  factory HierarchyAddress.fromDotString(String s) {
    if (s.isEmpty) {
      return root;
    }
    return HierarchyAddress(s.split('.').map(int.parse).toList());
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
      other is HierarchyAddress &&
          const ListEquality<int>().equals(path, other.path);

  @override
  int get hashCode => Object.hashAll(path);

  /// Resolve a pathname string (e.g. `"Top/counter/clk"` or
  /// `"Top.counter.clk"`) to a [HierarchyAddress] by walking [root].
  ///
  /// Supports both `/` and `.` as separators.  If the first segment
  /// matches [root]'s name (case-insensitive), it is skipped — the root
  /// node is always at the empty address.
  ///
  /// The last segment is first tried as a **signal** name within the
  /// current module; if that fails it is tried as a **child** module name.
  /// This mirrors the pathname convention where a signal path has one more
  /// segment than its parent module path.
  ///
  /// Returns `null` if any segment cannot be resolved.
  ///
  /// ```dart
  /// final addr = HierarchyAddress.tryFromPathname('Top/cpu/clk', root);
  /// if (addr != null) {
  ///   final signal = service.signalByAddress(addr);
  /// }
  /// ```
  static HierarchyAddress? tryFromPathname(
    String pathname,
    HierarchyNode root,
  ) {
    final rootAddr = root.address ?? HierarchyAddress.root;
    final parts = pathname
        .replaceAll('.', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    // Skip leading segment that matches the root name.
    final segments =
        parts.isNotEmpty && parts.first.toLowerCase() == root.name.toLowerCase()
            ? parts.skip(1)
            : parts;

    ({HierarchyNode node, HierarchyAddress addr})? step(
      ({HierarchyNode node, HierarchyAddress addr})? cur,
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

    return segments.fold<({HierarchyNode node, HierarchyAddress addr})?>(
        (node: root, addr: rootAddr), step)?.addr;
  }
}

/// A generic node representing a module or instance in the hierarchy.
///
/// This is the core structural data model, independent of waveform data.
class HierarchyNode {
  /// Unique identifier for this node.
  final String id;

  /// Display name of this module or instance.
  final String name;

  /// Whether this node is a module or an instance.
  final HierarchyKind kind;

  /// Optional definition/type name for instances.
  final String? type;

  /// Identifier of this node's parent, or null for root.
  final String? parentId;

  /// Whether this node is a primitive cell (gate, operator, register, etc.)
  /// whose internal structure is not useful for design navigation.
  ///
  /// Set by the parser/adapter that creates the node.  The netlist adapter
  /// sets this for cells that lack a module definition in the JSON or whose
  /// type starts with `$` (Yosys built-in primitives).  Tool-specific
  /// primitives (e.g. ROHD's FlipFlop → `$dff`) are handled by the
  /// synthesizer mapping them to `$`-prefixed types before the JSON is
  /// written.
  final bool isPrimitive;

  /// Signals within this module (includes both internal signals and ports).
  /// Empty for instances.
  final List<Signal> signals;

  /// Child modules/instances. Populated from sub-modules in the hierarchy.
  final List<HierarchyNode> children;

  /// Hierarchical address for this node.
  /// Assigned by [buildAddresses] to enable efficient navigation.
  /// Format: [child0, child1, ..., childN] for nested modules.
  HierarchyAddress? address;

  /// Creates a [HierarchyNode] with the given properties.
  HierarchyNode({
    required this.id,
    required this.name,
    required this.kind,
    this.type,
    this.parentId,
    this.isPrimitive = false,
    List<Signal>? signals,
    List<HierarchyNode>? children,
    this.address,
  })  : signals = signals ?? [],
        children = children ?? [];

  /// Returns only signals that are ports (have a direction).
  /// Returns Port instances for type safety.
  List<Port> get ports => signals.whereType<Port>().toList();

  // ───────────────── Name → offset (index) lookups ─────────────────

  /// Lazily-built index: child name → offset in [children].
  Map<String, int>? _childNameIndex;

  /// Lazily-built index: signal name → offset in [signals].
  Map<String, int>? _signalNameIndex;

  /// Return the offset (index) of the child with [name] in [children],
  /// or -1 if not found.  Case-insensitive.
  /// O(1) after first call (lazily builds index).
  int childIndexByName(String name) {
    _childNameIndex ??= {
      for (var i = 0; i < children.length; i++)
        children[i].name.toLowerCase(): i,
    };
    return _childNameIndex![name.toLowerCase()] ?? -1;
  }

  /// Return the offset (index) of the signal with [name] in [signals],
  /// or -1 if not found.  Case-insensitive.
  /// O(1) after first call (lazily builds index).
  int signalIndexByName(String name) {
    _signalNameIndex ??= {
      for (var i = 0; i < signals.length; i++) signals[i].name.toLowerCase(): i,
    };
    return _signalNameIndex![name.toLowerCase()] ?? -1;
  }

  /// Whether [cellType] represents a Yosys built-in primitive cell type.
  ///
  /// Returns `true` for `$`-prefixed types (`$mux`, `$dff`, `$and`, etc.)
  /// which are Yosys built-in operators and primitives.
  ///
  /// Tool-specific primitive types (e.g. ROHD's `FlipFlop`) should be
  /// handled by the producer: the synthesizer should map them to
  /// `$`-prefixed cell types in the JSON output, or the adapter should
  /// set [isPrimitive] on the node at construction time.
  ///
  /// Use this before a [HierarchyNode] exists (e.g. when deciding whether
  /// to recurse into a Yosys cell definition).  For an existing node, use
  /// the instance getter [isPrimitiveCell] instead.
  static bool isPrimitiveType(String cellType) => cellType.startsWith(r'$');

  /// Whether this node represents a primitive cell that should be hidden
  /// from the module tree.
  ///
  /// Checks the [isPrimitive] field (set by the adapter at construction
  /// time) and falls back to [isPrimitiveType] on the node's [type].
  bool get isPrimitiveCell =>
      isPrimitive || (type != null && isPrimitiveType(type!));

  /// Returns only input signals.
  List<Signal> get inputs =>
      signals.where((s) => s.direction == 'input').toList();

  /// Returns only output signals.
  List<Signal> get outputs =>
      signals.where((s) => s.direction == 'output').toList();

  /// Collect all signals under this node in canonical depth-first order.
  ///
  /// The traversal visits this node's [signals] first, then recurses into
  /// [children] in order.  This is the **single source of truth** for the
  /// DFS signal ordering used by compact waveform transport — all
  /// producers and consumers must use this method (or the equivalent
  /// [HierarchyAddress]-based traversal) to ensure their keys agree.
  ///
  /// Each signal's [HierarchyAddress] (assigned by [buildAddresses]) is
  /// used as the canonical key in compact JSON dictionaries (via
  /// [HierarchyAddress.toDotString]).  The flat iteration order here
  /// matches the address assignment order.
  List<Signal> depthFirstSignals() =>
      [...signals, ...children.expand((c) => c.depthFirstSignals())];

  /// Build hierarchical addresses for this node and all descendants.
  ///
  /// This performs a single O(n) tree traversal to assign [HierarchyAddress]
  /// to every node and signal in the tree. Call this once after tree
  /// construction to enable efficient address-based navigation.
  ///
  /// Example:
  /// ```dart
  /// root.buildAddresses();  // Assign addresses to all nodes/signals
  /// final signalAddr = signals[0].address;  // Now available
  /// ```
  void buildAddresses([HierarchyAddress startAddr = HierarchyAddress.root]) {
    address = startAddr;
    for (final (i, s) in signals.indexed) {
      s.address = startAddr.signal(i);
    }
    for (final (i, c) in children.indexed) {
      c.buildAddresses(startAddr.child(i));
    }
  }
}

/// A signal in the hardware hierarchy.
///
/// Signals are the fundamental data carriers in hardware. A signal can be:
/// - An internal wire/register within a module
/// - A port on a module interface (has direction: input/output/inout)
///
/// This is a structural model without waveform data. Use rohd_waveform
/// to access waveform data for a signal by its ID.
class Signal {
  /// Local identifier for this signal (typically the bare signal name).
  ///
  /// For display and local lookups within a module.
  /// Not guaranteed unique across
  /// the full hierarchy — use [hierarchyPath] for unique keying.
  final String id;

  /// The name of the signal.
  final String name;

  /// Type of the signal (e.g., "wire", "reg", "logic", "input").
  final String type;

  /// The bit width of the signal.
  final int width;

  /// Full hierarchical path using '/' separator (e.g., "top/counter/clk").
  ///
  /// This is the canonical unique key for this signal across the hierarchy.
  /// Always set in production code; may be null in test fixtures.
  final String? fullPath;

  /// ID of the scope (module) containing this signal.
  final String? scopeId;

  /// Direction of the signal if it's a port.
  /// Null for internal signals (wires, registers).
  /// "input", "output", or "inout" for ports.
  final String? direction;

  /// Current runtime value of the signal (if available).
  /// Typically a hex or binary string representation.
  final String? value;

  /// Whether this signal's value is computed/derivable (e.g. constant,
  /// gate output, InlineSystemVerilog result) rather than directly tracked
  /// by the waveform service.
  final bool isComputed;

  /// Hierarchical address for this signal.
  /// Assigned by [HierarchyNode.buildAddresses] to enable efficient navigation.
  /// Format: [...moduleIndices, signalIndex]
  HierarchyAddress? address;

  /// Creates a [Signal] with the given properties.
  Signal({
    required this.id,
    required this.name,
    required this.type,
    required this.width,
    this.fullPath,
    this.scopeId,
    this.direction,
    this.value,
    this.isComputed = false,
    this.address,
  });

  /// The unique hierarchical path for this signal.
  ///
  /// Returns [fullPath] when available (production), falls back to [id].
  /// Use this as the canonical key for caches, save/load, and waveform lookup.
  String get hierarchyPath => fullPath ?? id;

  /// Returns true if this signal is a port (has a direction).
  bool get isPort => direction != null;

  /// Returns true if this is an input port.
  bool get isInput => direction == 'input';

  /// Returns true if this is an output port.
  bool get isOutput => direction == 'output';

  /// Returns true if this is a bidirectional port.
  bool get isInout => direction == 'inout';

  @override
  String toString() =>
      '$name ($type, width=$width${isPort ? ', $direction' : ''})';
}

/// A port is a signal on a module interface with a direction.
///
/// This is a convenience typedef/factory for creating port signals.
/// Use [Signal] directly with a non-null direction, or use this
/// factory for clarity.
class Port extends Signal {
  /// Creates a [Port] with the given properties and direction.
  Port({
    required super.id,
    required super.name,
    required super.type,
    required super.width,
    required String direction,
    super.fullPath,
    super.scopeId,
    super.isComputed,
  }) : super(direction: direction);

  /// Creates a Port with minimal parameters.
  factory Port.simple({
    required String name,
    required String direction,
    int width = 1,
    String? id,
    String type = 'wire',
    String? fullPath,
    String? scopeId,
    bool isComputed = false,
  }) =>
      Port(
        id: id ?? name,
        name: name,
        type: type,
        width: width,
        direction: direction,
        fullPath: fullPath,
        scopeId: scopeId,
        isComputed: isComputed,
      );
}

/// Result of a signal search with enriched metadata.
///
/// Contains the signal's full path, parsed path segments, and the full
/// [Signal] object if available. This is the hierarchy-only portion of
/// search results; UI layers can use the pre-computed display helpers
/// directly without re-parsing paths.
@immutable
class SignalSearchResult {
  /// The full hierarchical path (signal ID) that was found.
  /// Example: "Top/counter/clk"
  final String signalId;

  /// The hierarchical path segments.
  /// Example: ["Top", "counter", "clk"]
  final List<String> path;

  /// The underlying [Signal] from the hierarchy service (if available).
  /// Contains width, direction, type, and other signal metadata.
  final Signal? signal;

  /// Creates a signal search result.
  const SignalSearchResult({
    required this.signalId,
    required this.path,
    this.signal,
  });

  /// The signal name (last path segment).
  String get name => path.isNotEmpty ? path.last : signalId;

  // ───────────────────── Display helpers ─────────────────────

  /// Display path with the top-level module name stripped.
  ///
  /// For `Top/counter/clk` this returns `counter/clk`.
  /// For a single-segment path returns the original [signalId].
  String get displayPath => displaySegments.join('/');

  /// Path segments with the top-level module name stripped.
  ///
  /// For `["Top", "counter", "clk"]` this returns `["counter", "clk"]`.
  List<String> get displaySegments => path.length > 1 ? path.sublist(1) : path;

  /// Instance names that need to be expanded to reveal this signal.
  ///
  /// These are the intermediate path segments between the top module
  /// and the signal name — i.e. everything except the first (top module)
  /// and last (signal name) segments.
  ///
  /// For `Top/sub1/sub2/clk` this returns `["sub1", "sub2"]`.
  List<String> get intermediateInstanceNames =>
      path.length > 2 ? path.sublist(1, path.length - 1) : const <String>[];

  /// Normalize a user query for hierarchy search.
  ///
  /// Converts common separators (`.`) to the canonical `/` separator.
  static String normalizeQuery(String query) => query.replaceAll('.', '/');

  @override
  String toString() =>
      'SignalSearchResult($signalId, width=${signal?.width ?? "?"})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalSearchResult && signalId == other.signalId;

  @override
  int get hashCode => signalId.hashCode;
}

/// Result of a module/node search with enriched metadata.
///
/// Contains the module's full path, parsed path segments, and the full
/// [HierarchyNode] object. This mirrors [SignalSearchResult] for modules
/// and provides a consistent search results interface.
@immutable
class ModuleSearchResult {
  /// The full hierarchical path (node ID) that was found.
  /// Example: "Top/CPU/ALU"
  final String moduleId;

  /// The hierarchical path segments.
  /// Example: ["Top", "CPU", "ALU"]
  final List<String> path;

  /// The underlying [HierarchyNode] from the hierarchy service.
  /// Contains the node's name, kind, type, children, and signals.
  final HierarchyNode node;

  /// Creates a module search result.
  const ModuleSearchResult({
    required this.moduleId,
    required this.path,
    required this.node,
  });

  /// The module name (last path segment).
  String get name => path.isNotEmpty ? path.last : moduleId;

  /// The kind of this node (module or instance).
  HierarchyKind get kind => node.kind;

  /// Whether this is a module definition.
  bool get isModule => node.kind == HierarchyKind.module;

  /// Number of direct children (sub-modules/instances).
  int get childCount => node.children.length;

  // ───────────────────── Display helpers ─────────────────────

  /// Display path with the top-level module name stripped.
  ///
  /// For `Top/CPU/ALU` this returns `CPU/ALU`.
  /// For a single-segment path returns the original [moduleId].
  String get displayPath => displaySegments.join('/');

  /// Path segments with the top-level module name stripped.
  ///
  /// For `["Top", "CPU", "ALU"]` returns `["CPU", "ALU"]`.
  List<String> get displaySegments => path.length > 1 ? path.sublist(1) : path;

  /// Normalize a user query for module search.
  ///
  /// Converts common separators (`.`) to the canonical `/` separator.
  static String normalizeQuery(String query) => query.replaceAll('.', '/');

  @override
  String toString() => 'ModuleSearchResult($moduleId, kind=${kind.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModuleSearchResult && moduleId == other.moduleId;

  @override
  int get hashCode => moduleId.hashCode;
}
