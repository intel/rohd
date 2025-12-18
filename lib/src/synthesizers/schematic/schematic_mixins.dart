// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// schematic_mixins.dart
// Definition for Schematic Mixins for controlling schematic synthesis.
//
// 2025 December
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// Represents a primitive cell in the schematic JSON output.
///
/// Used by [Schematic.schematicCell] to return custom cell representations.
class SchematicCellDefinition {
  /// The Yosys-style type name (e.g., `$and`, `$mux`, `$dff`).
  final String type;

  /// Parameters for the cell (e.g., `{'WIDTH': 8}`).
  final Map<String, Object?> parameters;

  /// Attributes for the cell.
  final Map<String, Object?> attributes;

  /// Port directions: port name → `'input'` | `'output'` | `'inout'`.
  final Map<String, String> portDirections;

  /// Creates a [SchematicCellDefinition].
  const SchematicCellDefinition({
    required this.type,
    this.parameters = const {},
    this.attributes = const {},
    this.portDirections = const {},
  });
}

/// What kind of schematic definition this [Module] generates, or whether it
/// does at all.
enum SchematicDefinitionGenerationType {
  /// No definition will be generated; the module is a primitive/leaf.
  none,

  /// A standard definition will be generated via the normal synthesis flow.
  standard,

  /// A custom definition will be generated via [Schematic.schematicDefinition].
  custom,
}

/// Allows a [Module] to control the instantiation and/or definition of
/// generated schematic JSON for that module.
///
/// Similar to [SystemVerilog] mixin for SystemVerilog synthesis, this mixin
/// provides hooks for modules to customize their schematic representation.
///
/// ## Example
///
/// ```dart
/// class MyCustomPrimitive extends Module with Schematic {
///   MyCustomPrimitive(Logic a, Logic b) {
///     a = addInput('a', a);
///     b = addInput('b', b);
///     addOutput('y') <= a & b;
///   }
///
///   @override
///   SchematicDefinitionGenerationType get schematicDefinitionType =>
///       SchematicDefinitionGenerationType.none;
///
///   @override
///   SchematicCellDefinition? schematicCell(
///     String instanceType,
///     String instanceName,
///     Map<String, Logic> ports,
///   ) {
///     return SchematicCellDefinition(
///       type: r'$and',
///       parameters: {
///         'A_WIDTH': ports['a']!.width,
///         'B_WIDTH': ports['b']!.width,
///       },
///       portDirections: {'A': 'input', 'B': 'input', 'Y': 'output'},
///     );
///   }
/// }
/// ```
mixin Schematic on Module {
  /// Generates a custom schematic cell definition to be used when this module
  /// is instantiated as a child in another module's schematic.
  ///
  /// The [instanceType] and [instanceName] represent the type and name,
  /// respectively, of the module that would have been instantiated.
  /// [ports] provides access to the actual port [Logic] objects.
  ///
  /// Return a [SchematicCellDefinition] to provide custom cell data.
  /// Return `null` to use standard cell generation.
  ///
  /// By default, returns `null` (use standard generation).
  SchematicCellDefinition? schematicCell(
    String instanceType,
    String instanceName,
    Map<String, Logic> ports,
  ) =>
      null;

  /// A custom schematic module definition to be produced for this [Module].
  ///
  /// Returns a map representing the module's JSON structure with keys:
  /// - `'ports'`: `Map<String, Map<String, Object?>>`
  /// - `'cells'`: `Map<String, Map<String, Object?>>`
  /// - `'netnames'`: `Map<String, Object?>`
  /// - `'attributes'`: `Map<String, Object?>`
  ///
  /// If `null` is returned, a standard definition will be generated.
  /// If an empty map is returned, no definition will be generated.
  ///
  /// This function should have no side effects and always return the same thing
  /// for the same inputs.
  ///
  /// By default, returns `null` (use standard generation).
  Map<String, Object?>? schematicDefinition(String definitionType) => null;

  /// What kind of schematic definition this [Module] generates, or whether it
  /// does at all.
  ///
  /// By default, this is automatically calculated based on the return value of
  /// [schematicDefinition] and [schematicCell].
  SchematicDefinitionGenerationType get schematicDefinitionType {
    // If schematicCell returns non-null, treat as primitive (no definition)
    // We use an empty ports map for the check since we just need to see if
    // the module provides a custom implementation.
    final cell = schematicCell('*PLACEHOLDER*', '*PLACEHOLDER*', {});
    if (cell != null) {
      return SchematicDefinitionGenerationType.none;
    }

    // Check schematicDefinition
    final def = schematicDefinition('*PLACEHOLDER*');
    if (def == null) {
      return SchematicDefinitionGenerationType.standard;
    } else if (def.isNotEmpty) {
      return SchematicDefinitionGenerationType.custom;
    } else {
      return SchematicDefinitionGenerationType.none;
    }
  }

  /// Whether this module should be treated as a primitive in schematic output.
  ///
  /// When `true`, no separate module definition is generated; instead, the
  /// module is represented directly as a cell in the parent module.
  ///
  /// Override this to `true` for leaf primitives that should not have their
  /// own definition.
  ///
  /// By default, returns `true` if [schematicDefinitionType] is
  /// [SchematicDefinitionGenerationType.none].
  bool get isSchematicPrimitive =>
      schematicDefinitionType == SchematicDefinitionGenerationType.none;

  /// The Yosys primitive type name to use when this module is emitted as a
  /// cell (e.g., `$and`, `$mux`, `$dff`).
  ///
  /// Only used when [isSchematicPrimitive] is `true` or [schematicCell]
  /// returns `null` but the synthesizer determines this is a primitive.
  ///
  /// By default, returns `null`, meaning the module's definition name is used.
  String? get schematicPrimitiveName => null;

  /// Indicates that this module is only wires, no logic inside, which can be
  /// leveraged for pruning in schematic generation.
  @internal
  bool get isSchematicWiresOnly => false;
}

/// Allows a [Module] to define a type of [Schematic] which can be represented
/// as an inline primitive cell without generating a separate definition.
///
/// This is the schematic equivalent of [InlineSystemVerilog].
mixin InlineSchematic on Module implements Schematic {
  /// The Yosys primitive type to use for this inline cell.
  ///
  /// Override this to specify the primitive type (e.g., `$and`, `$or`).
  @override
  String get schematicPrimitiveName;

  /// Parameters to include in the primitive cell.
  ///
  /// Override to provide cell parameters like `{'WIDTH': 8}`.
  Map<String, Object?> get schematicParameters => const {};

  /// Port name mapping from ROHD port names to primitive port names.
  ///
  /// Override if the primitive uses different port names than the ROHD module.
  /// For example: `{'a': 'A', 'b': 'B', 'y': 'Y'}`.
  Map<String, String> get schematicPortMap => const {};

  @override
  bool get isSchematicPrimitive => true;

  @override
  SchematicCellDefinition? schematicCell(
    String instanceType,
    String instanceName,
    Map<String, Logic> ports,
  ) {
    final portDirs = <String, String>{};
    for (final entry in ports.entries) {
      final primPortName = schematicPortMap[entry.key] ?? entry.key;
      final logic = entry.value;
      portDirs[primPortName] = logic.isInput
          ? 'input'
          : logic.isOutput
              ? 'output'
              : 'inout';
    }

    return SchematicCellDefinition(
      type: schematicPrimitiveName,
      parameters: schematicParameters,
      portDirections: portDirs,
    );
  }

  @override
  SchematicDefinitionGenerationType get schematicDefinitionType =>
      SchematicDefinitionGenerationType.none;

  @override
  Map<String, Object?>? schematicDefinition(String definitionType) => {};

  @internal
  @override
  bool get isSchematicWiresOnly => false;
}
