// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_structure_layout.dart
// Shared packed LogicStructure layout utility for synthesis backends.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// An exclusive-end bit range within a packed [LogicStructure].
typedef SynthStructureBitRange = ({int start, int end});

typedef _SynthStructureRange = ({
  int start,
  int end,
  String name,
  String path,
  String fieldPath,
  int indexInParent,
});

/// Provides bit ranges and field names for a packed [LogicStructure].
class SynthStructureLayout {
  final List<_SynthStructureRange> _ranges = [];

  /// Creates a layout with elements ordered from least to most significant.
  SynthStructureLayout(LogicStructure structure) {
    _addStructure(structure, 0, '', '');
  }

  void _addStructure(
    LogicStructure structure,
    int baseOffset,
    String parentPath,
    String parentFieldPath,
  ) {
    var offset = baseOffset;
    for (var index = 0; index < structure.elements.length; index++) {
      final element = structure.elements[index];
      final end = offset + element.width;
      final path =
          parentPath.isEmpty ? element.name : '${parentPath}_${element.name}';
      final fieldPath = parentFieldPath.isEmpty
          ? element.name
          : '$parentFieldPath.${element.name}';
      _ranges.add((
        start: offset,
        end: end,
        name: element.name,
        path: path,
        fieldPath: fieldPath,
        indexInParent: index,
      ));
      if (element is LogicStructure && element is! BaseLogicArray) {
        _addStructure(element, offset, path, fieldPath);
      }
      offset = end;
    }
  }

  /// Returns the exclusive-end bit range for a dot-separated [fieldPath].
  ///
  /// For example, `a.b` returns the range for the nested `b` field in `a`.
  /// Returns `null` when [fieldPath] does not identify a field.
  SynthStructureBitRange? bitRangeForPath(String fieldPath) {
    for (final range in _ranges) {
      if (range.fieldPath == fieldPath) {
        return (start: range.start, end: range.end);
      }
    }
    return null;
  }

  /// Returns the best field name containing [bitOffset].
  ///
  /// When [anonymousUnpreferred] is true, an unpreferred leaf with no named
  /// ancestor is represented by its index rather than its raw name.
  String fieldNameAt(
    int bitOffset, {
    required String fallbackName,
    bool anonymousUnpreferred = false,
  }) {
    _SynthStructureRange? bestNamed;
    _SynthStructureRange? narrowest;

    for (final range in _ranges) {
      if (bitOffset < range.start || bitOffset >= range.end) {
        continue;
      }
      final span = range.end - range.start;
      if (narrowest == null || span < narrowest.end - narrowest.start) {
        narrowest = range;
      }
      if (!Naming.isUnpreferred(range.name) &&
          (bestNamed == null || span < bestNamed.end - bestNamed.start)) {
        bestNamed = range;
      }
    }

    if (bestNamed != null) {
      if (narrowest != null &&
          narrowest.end - narrowest.start < bestNamed.end - bestNamed.start) {
        final prefix = bestNamed.path;
        if (narrowest.path.length > prefix.length &&
            narrowest.path.startsWith(prefix)) {
          final suffix = narrowest.path.substring(prefix.length + 1);
          if (!Naming.isUnpreferred(suffix)) {
            return '${bestNamed.name}_$suffix';
          }
        }
        return '${bestNamed.name}_${narrowest.indexInParent}';
      }
      return bestNamed.name;
    }

    if (anonymousUnpreferred &&
        narrowest != null &&
        Naming.isUnpreferred(narrowest.name)) {
      return 'anonymous_${narrowest.indexInParent}';
    }
    return narrowest?.name ?? fallbackName;
  }
}
