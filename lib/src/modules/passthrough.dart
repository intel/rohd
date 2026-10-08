// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// passthrough.dart
// A module that does nothing but pass a signal through.

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/operation_utils.dart';

/// A no-op module that preserves [LogicType].
///
/// The input supplies the output representation when `outputGenerator` is
/// omitted. Request `<Logic>` explicitly to normalize a constant or net input
/// into a driveable scalar output.
abstract class Passthrough<LogicType extends Logic> extends Module {
  /// Input port.
  LogicType get in_;

  /// Output port.
  LogicType get out;

  /// Constructs a pass-through preserving [LogicType].
  factory Passthrough(
    LogicType input, [
    String name = 'passthrough',
  ]) =>
      Passthrough._create(input, name, null);

  /// Constructs a pass-through with an explicit output representation.
  factory Passthrough.withOutput(
    LogicType input, {
    required LogicType Function({String? name}) outputGenerator,
    String name = 'passthrough',
  }) =>
      Passthrough._create(input, name, outputGenerator);

  static Passthrough<LogicType> _create<LogicType extends Logic>(
    LogicType input,
    String name,
    LogicType Function({String? name})? outputGenerator,
  ) {
    final outputSchema = createOperationOutput<LogicType>(
      width: input.width,
      name: 'out',
      operation: 'Passthrough<$LogicType>',
      prototype: input,
      outputGenerator: outputGenerator,
    );
    validateOperationSource(
      input,
      outputSchema,
      operation: 'Passthrough input',
    );

    if (LogicType == Logic) {
      return _ScalarPassthrough(
        input,
        outputSchema as Logic,
        usesOutputGenerator: outputGenerator != null,
        name: name,
      ) as Passthrough<LogicType>;
    }
    return _DomainPassthrough<LogicType>(
      input,
      outputSchema,
      name: name,
    );
  }

  Passthrough._({super.name, super.definitionName});
}

/// Scalar implementation of [Passthrough].
class _ScalarPassthrough extends Passthrough<Logic> {
  @override
  late final Logic in_;

  @override
  late final Logic out;

  _ScalarPassthrough(
    Logic input,
    Logic outputSchema, {
    required bool usesOutputGenerator,
    super.name = 'passthrough',
  }) : super._() {
    in_ = addInput('in', input, width: input.width);
    out = usesOutputGenerator
        ? addTypedOutput(
            'out',
            operationOutputClone(outputSchema),
          )
        : addOutput(
            'out',
            width: input.width,
          );
    final inner = Logic(name: 'inner', width: in_.width);
    inner <= in_;
    out <= inner;
  }
}

/// Type-preserving implementation of [Passthrough].
class _DomainPassthrough<LogicType extends Logic>
    extends Passthrough<LogicType> {
  @override
  late final LogicType in_;

  @override
  late final LogicType out;

  _DomainPassthrough(
    LogicType input,
    LogicType outputSchema, {
    super.name = 'passthrough',
  }) : super._(
          definitionName: 'Passthrough_${_schemaSignature(outputSchema)}',
        ) {
    in_ = addTypedInput('in', input);
    out = addTypedOutput(
      'out',
      operationOutputClone(outputSchema),
    );

    if (out is LogicStructure && in_ is LogicStructure) {
      final structuredOut = out as LogicStructure;
      final structuredIn = in_ as LogicStructure;
      for (var index = 0; index < structuredOut.leafElements.length; index++) {
        structuredOut.leafElements[index] <= structuredIn.leafElements[index];
      }
    } else {
      out <= in_;
    }
  }
}

String _schemaSignature(Logic logic) => logic is LogicStructure
    ? logicStructureShapeSignature(logic)
    : '${logic.runtimeType}_W${logic.width}';
