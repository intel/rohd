// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_cell_spec.dart
// Backend-neutral semantic metadata for primitive leaf modules.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// ignore_for_file: public_member_api_docs

import 'package:meta/meta.dart';

/// Direction for a leaf-cell port.
enum LeafPortDirection {
  /// Input-only port.
  input,

  /// Output-only port.
  output,

  /// Bidirectional port.
  inOut,
}

/// Semantic operation kind for a leaf cell.
///
/// This is backend-neutral metadata that renderers can consume to emit
/// SystemVerilog, SystemC, or netlist primitive forms.
enum LeafOperationKind {
  not,
  and,
  or,
  xor,
  add,
  subtract,
  multiply,
  divide,
  modulo,
  power,
  equals,
  notEquals,
  lessThan,
  greaterThan,
  lessThanOrEqual,
  greaterThanOrEqual,
  andUnary,
  orUnary,
  xorUnary,
  shiftLeft,
  shiftRight,
  arithmeticShiftRight,
  mux,
  bitIndex,
  busSubset,
  swizzle,
  replication,
  custom,
}

/// A port declaration in a semantic leaf-cell spec.
@immutable
class LeafPortSpec {
  /// Name of the port in the source module.
  final String name;

  /// Bit-width of the port.
  final int width;

  /// Direction of the port.
  final LeafPortDirection direction;

  /// Creates a port spec.
  const LeafPortSpec(this.name, this.width, this.direction);
}

/// Semantic description of a primitive/leaf module operation.
@immutable
class LeafCellSpec {
  /// Operation kind represented by this leaf.
  final LeafOperationKind operation;

  /// All ports (inputs, outputs, inouts) for this leaf.
  final List<LeafPortSpec> ports;

  /// Extra operation-specific parameters.
  ///
  /// Keys are renderer-defined (for example: `startIndex`, `endIndex`,
  /// `signed`, `resultSignalName`, etc).
  final Map<String, Object?> metadata;

  /// Creates a semantic leaf-cell spec.
  const LeafCellSpec({
    required this.operation,
    this.ports = const [],
    this.metadata = const {},
  });
}

/// Optional interface for modules that can provide semantic leaf metadata.
///
/// This enables backend renderers to avoid backend-specific type switches.
abstract interface class LeafCellProvider {
  /// Semantic description of this leaf cell.
  LeafCellSpec get leafCellSpec;
}
