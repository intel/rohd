// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// synth_operation_namer.dart
// Stable naming for synthesis-created helper operations.
//
// 2026 July 14
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

/// Stable names for synthesis-created helper operations.
@internal
class SynthOperationNamer {
  /// Canonical base name for synthesis-created array slice operations.
  ///
  /// Netlist synthesis uses these when a [LogicArray] port or submodule output
  /// must be decomposed into element wires, such as a child reading
  /// `values.elements[0]` from an aggregate array input port.
  static const String arraySliceOperationName = 'array_slice';

  /// Canonical base name for synthesis-created array concat operations.
  ///
  /// Netlist synthesis uses these when independently driven [LogicArray]
  /// elements must be reassembled for an aggregate consumer, such as
  /// `values.elements[0] <= a` and `values.elements[1] <= b` feeding a child
  /// array input port.
  static const String arrayConcatOperationName = 'array_concat';

  /// Canonical base name for synthesis-created structure slice operations.
  ///
  /// Synthesis uses these internally when a [LogicStructure] aggregate must
  /// expose field wires. The netlist projection can replace them with
  /// `$struct_unpack` cells so field names are preserved.
  static const String structureSliceOperationName = 'struct_slice';

  /// Canonical base name for synthesis-created structure concat operations.
  ///
  /// Netlist synthesis uses these when independently driven [LogicStructure]
  /// fields must be packed back into an aggregate struct output or submodule
  /// input. The emitted netlist projection represents this as `$struct_pack`.
  static const String structureConcatOperationName = 'struct_concat';

  SynthOperationNamer._();

  /// Returns the canonical instance name for a synthesis-created operation
  /// that targets [destination].
  ///
  /// The numeric suffix is derived from [destination]'s structural position,
  /// not from the order in which a backend asks for names. This keeps helper
  /// operation names stable across output formats that traverse a module in
  /// different orders.
  static String instanceName({
    required String operationName,
    required Logic destination,
  }) =>
      '${Sanitizer.sanitizeSV(operationName)}_'
      '${_destinationSuffix(destination)}';

  static String _destinationSuffix(Logic destination) {
    final parts = <int>[
      ..._modulePathIndices(destination.parentModule),
      ..._logicLocationIndices(destination),
    ];

    return parts.isEmpty ? '0' : parts.join('_');
  }

  static List<int> _modulePathIndices(Module? module) {
    if (module == null) {
      return const [0];
    }

    final parent = module.parent;
    if (parent == null) {
      return const [0];
    }

    final siblings = parent.subModules.toList();
    final index = siblings.indexWhere(
      (submodule) => identical(submodule, module),
    );
    return [..._modulePathIndices(parent), if (index < 0) 0 else index];
  }

  static List<int> _logicLocationIndices(Logic destination) {
    final elementPath = <int>[];
    var root = destination;
    while (root.parentStructure != null) {
      final parent = root.parentStructure!;
      final index = parent.elements.indexWhere(
        (element) => identical(element, root),
      );
      elementPath.insert(0, index < 0 ? root.arrayIndex ?? 0 : index);
      root = parent;
    }

    final module = root.parentModule;
    if (module == null) {
      return [0, ...elementPath];
    }

    final location = _logicLocationInModule(module, root);
    return [...location, ...elementPath];
  }

  static List<int> _logicLocationInModule(Module module, Logic root) {
    final inputIndex = _identityIndex(module.inputs.values, root);
    if (inputIndex >= 0) {
      return [0, inputIndex];
    }

    final outputIndex = _identityIndex(module.outputs.values, root);
    if (outputIndex >= 0) {
      return [1, outputIndex];
    }

    final inOutIndex = _identityIndex(module.inOuts.values, root);
    if (inOutIndex >= 0) {
      return [2, inOutIndex];
    }

    final internalIndex = _identityIndex(module.internalSignals, root);
    if (internalIndex >= 0) {
      return [3, internalIndex];
    }

    return const [4, 0];
  }

  static int _identityIndex(Iterable<Logic> logics, Logic target) {
    var index = 0;
    for (final logic in logics) {
      if (identical(logic, target)) {
        return index;
      }
      index++;
    }
    return -1;
  }
}
