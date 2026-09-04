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
abstract class TypedPassthrough<LogicType extends Logic>
    extends TypedOp<LogicType> {
  /// Input port.
  LogicType get in_;

  /// Output port.
  @override
  LogicType get out;

  /// Creates a typed pass-through implementation.
  TypedPassthrough({
    super.name = 'typed_passthrough',
    super.reserveName,
    super.definitionName,
    super.reserveDefinitionName,
  });
}

/// A very simple noop module that just passes a signal through.
class Passthrough extends TypedPassthrough<Logic> {
  /// The input port.
  @override
  Logic get in_ => input('in');

  /// The output port.
  @override
  Logic get out => output('out');

  /// Constructs a simple pass-through module that performs no operations
  /// between [a] and [out].
  Passthrough(Logic a, [String name = 'passthrough']) : super(name: name) {
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

/// A no-op module that preserves a concrete [LogicStructure] type.
///
/// The input and output retain all nested [LogicArray] and [LogicArrayOf]
/// boundaries. Typed ports reject structures containing constants or nets.
class StructurePassthrough<LogicType extends LogicStructure>
    extends TypedPassthrough<LogicType> {
  @override
  late final LogicType in_;

  @override
  late final LogicType out;

  /// Creates a structure-preserving pass-through module.
  StructurePassthrough(LogicType input, {super.name = 'structure_passthrough'})
      : super(definitionName: _structurePassthroughDefinitionName(input)) {
    LogicType cloneOutput({String name = 'out'}) =>
        typedClone(input, name: name);

    in_ = addTypedInput('in', input);
    out = addTypedOutput('out', cloneOutput);
    for (var index = 0; index < out.leafElements.length; index++) {
      out.leafElements[index] <= in_.leafElements[index];
    }
  }
}
