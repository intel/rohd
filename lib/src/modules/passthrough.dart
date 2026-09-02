// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// passthrough.dart
// A module that does nothing but pass a signal through.
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// A pass-through module with an input and output represented by [LogicType].
abstract class Passthrough<LogicType extends Logic> extends TypedOp<LogicType> {
  /// Input port.
  LogicType get in_;

  /// Output port.
  @override
  LogicType get out;

  /// Creates a pass-through with an output represented by [LogicType].
  ///
  /// Concrete [LogicStructure] inputs infer their output type. Constants and
  /// nets require `Passthrough<Logic>` because the result is driveable logic.
  factory Passthrough(LogicType input, [String name = 'passthrough']) {
    if (LogicType == Logic) {
      return _LogicPassthrough(input, name) as Passthrough<LogicType>;
    }
    if (input is! LogicStructure) {
      throw LogicConstructionException(
          'Passthrough<$LogicType> requires LogicType to be Logic or a '
          'concrete LogicStructure.');
    }
    return _StructurePassthrough<LogicType>(input, name: name);
  }

  Passthrough._({
    super.name,
    super.reserveName,
    super.definitionName,
    super.reserveDefinitionName,
  });
}

/// Scalar implementation of [Passthrough].
class _LogicPassthrough extends Passthrough<Logic> {
  /// The input port.
  @override
  Logic get in_ => input('in');

  /// The output port.
  @override
  Logic get out => output('out');

  /// Constructs a simple pass-through module that performs no operations
  /// between [a] and [out].
  _LogicPassthrough(Logic a, [String name = 'passthrough'])
      : super._(name: name) {
    addInput('in', a, width: a.width);
    addOutput('out', width: a.width);
    _setup();
  }

  void _setup() {
    final inner = Logic(name: 'inner', width: in_.width);
    inner <= in_;
    out <= inner;
  }
}

String _structurePassthroughDefinitionName(LogicStructure structure) =>
    'StructurePassthrough_${logicStructureShapeSignature(structure)}';

/// Structure-preserving implementation of [Passthrough].
///
/// The input and output retain all nested [LogicArray] and [LogicArrayOf]
/// boundaries. Typed ports reject structures containing constants or nets.
class _StructurePassthrough<LogicType extends Logic>
    extends Passthrough<LogicType> {
  @override
  late final LogicType in_;

  @override
  late final LogicType out;

  /// Creates a structure-preserving pass-through module.
  _StructurePassthrough(LogicType input, {super.name = 'structure_passthrough'})
      : super._(
          definitionName:
              _structurePassthroughDefinitionName(input as LogicStructure),
        ) {
    final structuredInput = input as LogicStructure;
    LogicType cloneOutput({String name = 'out'}) {
      final cloned = structuredInput.clone(name: name);
      if (cloned is! LogicType) {
        throw LogicConstructionException(
            'Passthrough output clone did not preserve its concrete type.');
      }
      return cloned as LogicType;
    }

    in_ = addTypedInput('in', input);
    out = addTypedOutput('out', cloneOutput);
    final structuredOut = out as LogicStructure;
    final structuredIn = in_ as LogicStructure;
    for (var index = 0; index < structuredOut.leafElements.length; index++) {
      structuredOut.leafElements[index] <= structuredIn.leafElements[index];
    }
  }
}
