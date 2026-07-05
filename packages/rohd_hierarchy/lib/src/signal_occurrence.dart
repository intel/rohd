// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_occurrence.dart
// A signal in the hardware occurrence hierarchy.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd_hierarchy/src/hierarchy_occurrence.dart';
import 'package:rohd_hierarchy/src/occurrence_address.dart';

/// Signals are the fundamental data carriers in hardware. A signal can be:
/// - An internal signal within an occurrence
/// - A port on an occurrence interface (has direction: input/output/inout)
///
/// This is a structural model without waveform data. Path strings are
/// computed on demand from the parent occurrence reference — call [path]
/// with your desired separator.
class SignalOccurrence {
  /// The name of the signal (bare name within its scope).
  ///
  /// Used for display, search, and local lookups within an occurrence.
  /// Not guaranteed unique across the full hierarchy — use [path] for
  /// unique keying.
  final String name;

  /// The bit width of the signal.
  final int width;

  /// Direction of the signal if it's a port.
  /// Null for internal signals.
  /// "input", "output", or "inout" for ports.
  final String? direction;

  /// Current runtime value of the signal (if available).
  /// Typically a hex or binary string representation.
  final String? value;

  /// Whether this signal's value is computed/derivable (e.g. constant,
  /// gate output, InlineSystemVerilog result) rather than directly tracked
  /// by the waveform service.
  final bool isComputed;

  /// Stable ordering index among ports in the parent occurrence.
  ///
  /// Set by the adapter that creates the signal.  For ports (signals with
  /// a [direction]), this records the deterministic position from the
  /// original source (netlist JSON iteration order, ROHD module port
  /// declaration order, etc.).  Internal signals have `null`.
  ///
  /// [HierarchyOccurrence.buildAddresses] places ports before internal
  /// signals when assigning [OccurrenceAddress] indices, so a port with
  /// `portIndex == k` will receive signal address index `k`.
  ///
  /// Consumers that store connectivity by `(nodeId, portIndex)` tuples
  /// (e.g. schematic hyperedges) rely on this value remaining stable
  /// across incremental hierarchy expansion.
  final int? portIndex;

  /// Type metadata from the netlist `logic_type` JSON field.
  ///
  /// For a **LogicStructure** (non-array), the format is:
  /// ```json
  /// {"typeName": "FloatingPoint", "fields": [
  ///   {"name": "mantissa", "width": 4, "bits": [0,1,2,3]},
  ///   {"name": "exponent", "width": 4, "bits": [4,5,6,7]},
  ///   {"name": "sign", "width": 1, "bits": [8]}
  /// ]}
  /// ```
  ///
  /// For a **LogicArray**, the format is:
  /// ```json
  /// {"width": 80, "arrayDims": [10], "elementWidth": 8}
  /// ```
  ///
  /// For a plain signal: `{"width": N}` or `null`.
  ///
  /// Nested structs have a recursive `"type"` key in their field entries.
  Map<String, dynamic>? logicType;

  /// Hierarchical address for this signal. Assigned by
  /// [HierarchyOccurrence.buildAddresses] to enable efficient navigation.
  /// Format: [...occurrenceIndices, signalIndex]
  OccurrenceAddress? get address => _address;
  OccurrenceAddress? _address;

  /// Sets the address. Only for use by [HierarchyOccurrence.buildAddresses].
  @internal
  set address(OccurrenceAddress? value) => _address = value;

  /// Parent occurrence containing this signal. Set by
  /// [HierarchyOccurrence.buildAddresses].
  HierarchyOccurrence? get parent => _parent;
  HierarchyOccurrence? _parent;

  /// Sets the parent. Only for use by [HierarchyOccurrence.buildAddresses].
  @internal
  set parent(HierarchyOccurrence? value) => _parent = value;

  /// Creates a [SignalOccurrence] with the given properties.
  SignalOccurrence({
    required this.name,
    required this.width,
    this.direction,
    this.value,
    this.isComputed = false,
    this.portIndex,
    this.logicType,
  });

  /// Whether this signal is a LogicStructure (has named sub-fields).
  bool get isStruct => logicType != null && logicType!.containsKey('fields');

  /// Whether this signal is a LogicArray (has indexed elements).
  bool get isArray => logicType != null && logicType!.containsKey('arrayDims');

  /// The struct type name (e.g. "FloatingPoint"), or null if not a struct.
  String? get typeName => logicType?['typeName'] as String?;

  /// The struct field descriptors, or empty list if not a struct.
  ///
  /// Each field is `{"name": ..., "width": ..., "bits": [...]}` with an
  /// optional `"type"` key for nested structs/arrays.
  List<Map<String, dynamic>> get structFields =>
      (logicType?['fields'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
      const [];

  /// Array dimensions (e.g. `[10]` for 1D, `[10, 2]` for 2D), or null.
  List<int>? get arrayDims =>
      (logicType?['arrayDims'] as List<dynamic>?)?.cast<int>();

  /// Element width for arrays, or null if not an array.
  int? get arrayElementWidth => logicType?['elementWidth'] as int?;

  /// Returns the expected sub-field signal names derived from [logicType].
  ///
  /// For structs, the synthesizer creates separate netnames for each field
  /// following the Namer/Sanitizer conventions:
  ///   `Sanitizer.sanitizeSV(structureName)` → `{parentName}_{fieldName}`
  ///
  /// For example, signal `fp` with fields `mantissa`, `exponent`, `sign`
  /// produces sub-field signal names: `fp_mantissa`, `fp_exponent`, `fp_sign`.
  ///
  /// These become separate [SignalOccurrence] entries in the same parent
  /// module.  Use `HierarchyOccurrence.findSubFieldSignals` to look
  /// them up.
  ///
  /// Returns a list of `(expectedName, fieldLabel, width, startBit,
  /// subLogicType)` for direct children.  `expectedName` follows the
  /// `{parentSignalName}_{fieldName}` convention.
  /// `subLogicType` is non-null when the child is itself a sub-array
  /// (remaining dimensions) and can be further expanded.
  /// Empty if this is not a struct/array with known sub-fields.
  List<
      ({
        String expectedName,
        String fieldLabel,
        int width,
        int startBit,
        Map<String, Object?>? subLogicType,
      })> get subFieldDescriptors {
    if (logicType == null) {
      return const [];
    }
    return subFieldDescriptorsForType(logicType!, name);
  }

  /// Compute sub-field descriptors for an arbitrary [logicType] map.
  ///
  /// [parentName] is used to derive expected signal names.
  /// This is static so it can be called recursively for nested arrays
  /// without needing a full [SignalOccurrence].
  static List<
      ({
        String expectedName,
        String fieldLabel,
        int width,
        int startBit,
        Map<String, Object?>? subLogicType,
      })> subFieldDescriptorsForType(
    Map<String, Object?> logicType,
    String parentName,
  ) {
    final fields = logicType['fields'] as List<dynamic>?;
    if (fields != null) {
      return fields.map((f) {
        final field = f as Map<String, dynamic>;
        final fieldName = field['name'] as String? ?? '?';
        final width = field['width'] as int? ?? 1;
        final bits = field['bits'] as List<dynamic>?;
        final startBit = bits != null && bits.isNotEmpty
            ? (bits.cast<int>().reduce((a, b) => a < b ? a : b))
            : 0;
        // Naming convention: Sanitizer.sanitizeSV("$parentName.$fieldName")
        // which produces "$parentName_$fieldName"
        final expectedName = '${parentName}_$fieldName';
        return (
          expectedName: expectedName,
          fieldLabel: fieldName,
          width: width,
          startBit: startBit,
          subLogicType: field['type'] as Map<String, Object?>?,
        );
      }).toList();
    }

    final arrayDims = logicType['arrayDims'] as List<dynamic>?;
    if (arrayDims != null && arrayDims.isNotEmpty) {
      final leafWidth = (logicType['elementWidth'] as int?) ?? 1;
      final outerDim = arrayDims.first as int;
      // For multi-dimensional arrays, each outer element spans all
      // remaining dimensions times the leaf element width.
      final remainingDims =
          arrayDims.length > 1 ? arrayDims.sublist(1).cast<int>() : <int>[];
      final elementWidth = remainingDims.isEmpty
          ? leafWidth
          : remainingDims.fold<int>(leafWidth, (acc, d) => acc * d);

      // Build sub-logicType for remaining dimensions (if any).
      final subLogicType = remainingDims.isEmpty
          ? null
          : <String, Object?>{
              'width': elementWidth,
              'arrayDims': remainingDims,
              'elementWidth': leafWidth,
            };

      return List.generate(outerDim, (i) {
        // Naming convention: Sanitizer.sanitizeSV("$parentName[$i]")
        // which produces "$parentName_${i}_"
        final expectedName = '${parentName}_${i}_';
        return (
          expectedName: expectedName,
          fieldLabel: '[$i]',
          width: elementWidth,
          startBit: i * elementWidth,
          subLogicType: subLogicType,
        );
      });
    }

    return const [];
  }

  /// Compute the full hierarchical path for this signal.
  ///
  /// Joins the parent occurrence's path with this signal's [name] using
  /// [separator].  Falls back to just [name] if parent is not yet set
  /// (e.g. in test fixtures before `buildAddresses`).
  String path({String separator = '/'}) {
    if (_parent == null) {
      return name;
    }
    return '${_parent!.path(separator: separator)}$separator$name';
  }

  /// Returns true if this signal is a port (has a direction).
  bool get isPort => direction != null;

  /// Returns true if this is an input port.
  bool get isInput => direction == 'input';

  /// Returns true if this is an output port.
  bool get isOutput => direction == 'output';

  /// Returns true if this is a bidirectional port.
  bool get isInout => direction == 'inout';

  @override
  String toString() => '$name (width=$width${isPort ? ', $direction' : ''})';
}
