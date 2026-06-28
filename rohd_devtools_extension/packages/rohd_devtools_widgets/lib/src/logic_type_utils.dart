// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_type_utils.dart
// Utilities for expanding LogicStructure/LogicArray type metadata and
// extracting sub-field values via bit-slicing.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

/// A node in the expanded type tree, used for structured display.
class TypeFieldNode {
  /// Field name (e.g. "mantissa", "[0]").
  final String name;

  /// Bit width of this field.
  final int width;

  /// Extracted value string for this field, or null if unavailable.
  final String? value;

  /// Child fields for nested structs/arrays.
  final List<TypeFieldNode> children;

  /// The bit range within the parent: [startBit, endBit) (LSB-first).
  final int startBit;

  /// Creates a type field node.
  TypeFieldNode({
    required this.name,
    required this.width,
    this.value,
    this.children = const [],
    this.startBit = 0,
  });
}

/// Expand a `logic_type` metadata map into a tree of [TypeFieldNode]s.
///
/// If [parentValue] is provided (as a binary string, MSB-first), sub-field
/// values are extracted via bit-slicing.
///
/// The `logic_type` format for structs:
/// ```json
/// {"typeName": "FloatingPoint", "fields": [
///   {"name": "mantissa", "width": 4, "bits": [0,1,2,3]},
///   {"name": "exponent", "width": 4, "bits": [4,5,6,7]},
///   {"name": "sign", "width": 1, "bits": [8]}
/// ]}
/// ```
///
/// For arrays:
/// ```json
/// {"width": 80, "arrayDims": [10], "elementWidth": 8}
/// ```
List<TypeFieldNode> expandLogicType(
  Map<String, dynamic>? logicType, {
  String? parentBinaryValue,
}) {
  if (logicType == null) return const [];

  // Struct case
  final fields = logicType['fields'] as List<dynamic>?;
  if (fields != null) {
    return _expandStructFields(fields, parentBinaryValue);
  }

  // Array case
  final arrayDims = logicType['arrayDims'] as List<dynamic>?;
  if (arrayDims != null) {
    final elementWidth = (logicType['elementWidth'] as int?) ?? 1;
    final elementType = logicType['elementType'] as Map<String, dynamic>?;
    return _expandArrayElements(
      arrayDims.cast<int>(),
      elementWidth,
      elementType,
      parentBinaryValue,
    );
  }

  return const [];
}

/// Expand struct fields from the `fields` list.
List<TypeFieldNode> _expandStructFields(
  List<dynamic> fields,
  String? parentBinaryValue,
) {
  // The `bits` arrays in struct metadata may use module-level absolute
  // indices (e.g. [390..398] for a 9-bit signal).  Normalize to signal-
  // relative indices by subtracting the global minimum across all fields.
  var baseOffset = 0;
  if (parentBinaryValue != null) {
    var minBit = 1 << 30;
    for (final fieldRaw in fields) {
      final field = fieldRaw as Map<String, dynamic>;
      final bits = field['bits'] as List<dynamic>?;
      if (bits != null && bits.isNotEmpty) {
        for (final b in bits) {
          final bInt = b as int;
          if (bInt < minBit) minBit = bInt;
        }
      }
    }
    // Only apply offset if the bits exceed the binary value length,
    // indicating module-level absolute indices.
    if (minBit > 0 && minBit >= parentBinaryValue.length) {
      baseOffset = minBit;
    }
  }

  final nodes = <TypeFieldNode>[];
  for (final fieldRaw in fields) {
    final field = fieldRaw as Map<String, dynamic>;
    final name = field['name'] as String? ?? '?';
    final width = field['width'] as int? ?? 1;
    final bits = field['bits'] as List<dynamic>?;
    final nestedType = field['type'] as Map<String, dynamic>?;

    // Normalize bits to signal-relative indices.
    final relativeBits = bits?.cast<int>().map((b) => b - baseOffset).toList();

    // Determine start bit from bits array (min value, relative).
    final startBit = relativeBits != null && relativeBits.isNotEmpty
        ? relativeBits.reduce((a, b) => a < b ? a : b)
        : 0;

    // Extract value for this field.
    String? fieldValue;
    if (parentBinaryValue != null &&
        relativeBits != null &&
        relativeBits.isNotEmpty) {
      fieldValue = _extractBitsFromBinary(parentBinaryValue, relativeBits);
    }

    // Recursively expand nested types.
    final children = nestedType != null
        ? expandLogicType(nestedType, parentBinaryValue: fieldValue)
        : const <TypeFieldNode>[];

    nodes.add(
      TypeFieldNode(
        name: name,
        width: width,
        value: fieldValue,
        children: children,
        startBit: startBit,
      ),
    );
  }
  return nodes;
}

/// Expand array elements.
List<TypeFieldNode> _expandArrayElements(
  List<int> dims,
  int elementWidth,
  Map<String, dynamic>? elementType,
  String? parentBinaryValue,
) {
  if (dims.isEmpty) return const [];

  final outerDim = dims.first;
  final nodes = <TypeFieldNode>[];

  // The `elementWidth` from logicType is the LEAF element width.
  // For multi-dimensional arrays the actual per-element width at this level
  // is the product of remaining dimensions × leaf element width.
  // Derive it from the parent binary length when available, or compute it.
  final int stride;
  if (parentBinaryValue != null && parentBinaryValue.isNotEmpty) {
    stride = parentBinaryValue.length ~/ outerDim;
  } else if (dims.length > 1) {
    // Product of remaining dims × leaf element width.
    var product = elementWidth;
    for (var d = 1; d < dims.length; d++) {
      product *= dims[d];
    }
    stride = product;
  } else {
    stride = elementWidth;
  }

  for (var i = 0; i < outerDim; i++) {
    final startBit = i * stride;

    // Extract this element's value.
    String? elementValue;
    if (parentBinaryValue != null) {
      elementValue = _extractContiguousBits(
        parentBinaryValue,
        startBit,
        stride,
      );
    }

    // For multi-dimensional arrays, recurse into inner dimensions.
    List<TypeFieldNode> children;
    if (dims.length > 1) {
      // Only propagate elementType if it describes a leaf-level type (e.g.
      // a struct).  When elementType itself has 'arrayDims', it merely
      // re-describes the intermediate structure already encoded in the
      // parent's flat dims list — propagating it would incorrectly expand
      // leaf elements with children that exceed their bit width.
      final propagateElementType =
          elementType != null && !elementType.containsKey('arrayDims');
      final innerType = <String, dynamic>{
        'arrayDims': dims.sublist(1),
        'elementWidth': elementWidth,
        if (propagateElementType) 'elementType': elementType,
      };
      children = expandLogicType(innerType, parentBinaryValue: elementValue);
    } else if (elementType != null) {
      children = expandLogicType(elementType, parentBinaryValue: elementValue);
    } else {
      children = const [];
    }

    nodes.add(
      TypeFieldNode(
        name: '[$i]',
        width: stride,
        value: elementValue,
        children: children,
        startBit: startBit,
      ),
    );
  }
  return nodes;
}

/// Extract specified bit indices from a binary string (MSB-first format).
///
/// The binary string is MSB-first: index 0 is the rightmost (LSB) bit.
/// The [bitIndices] are LSB-indexed (matching the netlist `bits` array).
String _extractBitsFromBinary(String binaryValue, List<int> bitIndices) {
  final totalWidth = binaryValue.length;
  final result = StringBuffer();

  // Sort indices descending to produce MSB-first output.
  final sorted = List<int>.from(bitIndices)..sort((a, b) => b.compareTo(a));

  for (final idx in sorted) {
    // Convert LSB index to MSB-first string position.
    final pos = totalWidth - 1 - idx;
    if (pos >= 0 && pos < totalWidth) {
      result.write(binaryValue[pos]);
    } else {
      result.write('x');
    }
  }
  return result.toString();
}

/// Extract a contiguous bit range from a binary string (MSB-first format).
///
/// [startBit] is the LSB index, [width] is the number of bits.
String _extractContiguousBits(String binaryValue, int startBit, int width) {
  final totalWidth = binaryValue.length;
  final endBit = startBit + width; // exclusive
  final result = StringBuffer();

  // Extract MSB-first.
  for (var i = endBit - 1; i >= startBit; i--) {
    final pos = totalWidth - 1 - i;
    if (pos >= 0 && pos < totalWidth) {
      result.write(binaryValue[pos]);
    } else {
      result.write('x');
    }
  }
  return result.toString();
}

/// Convert a hex value string (e.g. "0x1a3f" or "1a3f") to binary (MSB-first).
///
/// Returns null if the input can't be parsed.
String? hexToBinary(String hexValue, int width) {
  var cleaned = hexValue.trim().toLowerCase();
  if (cleaned.startsWith('0x')) {
    cleaned = cleaned.substring(2);
  }
  // Handle 'x' or 'z' values.
  if (cleaned.contains('x') || cleaned.contains('z')) {
    // Expand each hex digit to 4 binary digits, preserving x/z.
    final buf = StringBuffer();
    for (final ch in cleaned.split('')) {
      if (ch == 'x') {
        buf.write('xxxx');
      } else if (ch == 'z') {
        buf.write('zzzz');
      } else {
        final nibble = int.tryParse(ch, radix: 16);
        if (nibble == null) return null;
        buf.write(nibble.toRadixString(2).padLeft(4, '0'));
      }
    }
    final full = buf.toString();
    // Trim or pad to desired width.
    if (full.length >= width) {
      return full.substring(full.length - width);
    }
    return full.padLeft(width, '0');
  }

  final bigInt = BigInt.tryParse(cleaned, radix: 16);
  if (bigInt == null) return null;
  final binary = bigInt.toRadixString(2);
  if (binary.length >= width) {
    return binary.substring(binary.length - width);
  }
  return binary.padLeft(width, '0');
}

/// Format a binary field value for display.
///
/// Short values (<=4 bits) show as binary. Longer values show as hex.
/// Uses ROHD radixString style: width'hHEX.
String formatFieldValue(String? binaryValue, int width) {
  if (binaryValue == null || binaryValue.isEmpty) return '';
  if (binaryValue.contains('x')) return "$width'hx";
  if (binaryValue.contains('z')) return "$width'hz";
  if (width <= 4) return "$width'b$binaryValue";
  // Convert to hex.
  final bigInt = BigInt.tryParse(binaryValue, radix: 2);
  if (bigInt == null) return binaryValue;
  final hexDigits = (width + 3) ~/ 4;
  final hex = bigInt.toRadixString(16).padLeft(hexDigits, '0');
  return "$width'h$hex";
}

/// Build a multi-line indented string showing struct/array fields with values.
///
/// Used for schematic hover tooltips.
String formatTypeTooltip(
  Map<String, dynamic>? logicType, {
  String? parentBinaryValue,
  String? signalName,
  int maxDepth = 6,
}) {
  if (logicType == null) return '';

  final nodes = expandLogicType(
    logicType,
    parentBinaryValue: parentBinaryValue,
  );
  if (nodes.isEmpty) return '';

  final buf = StringBuffer();
  final typeName = logicType['typeName'] as String?;
  if (signalName != null) {
    buf.write(signalName);
    if (typeName != null) buf.write(' ($typeName)');
    buf.writeln();
  } else if (typeName != null) {
    buf.writeln(typeName);
  }

  for (final node in nodes) {
    _formatNode(buf, node, indent: 1, maxDepth: maxDepth);
  }
  return buf.toString().trimRight();
}

void _formatNode(
  StringBuffer buf,
  TypeFieldNode node, {
  required int indent,
  required int maxDepth,
}) {
  final pad = '  ' * indent;
  buf.write('$pad${node.name}');
  if (node.value != null) {
    buf.write(': ${formatFieldValue(node.value, node.width)}');
  } else {
    buf.write(' [${node.width}]');
  }
  buf.writeln();

  if (indent < maxDepth) {
    for (final child in node.children) {
      _formatNode(buf, child, indent: indent + 1, maxDepth: maxDepth);
    }
  } else if (node.children.isNotEmpty) {
    buf.writeln('$pad  ...');
  }
}
