// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// operation_utils.dart
// Shared construction and validation for type-preserving operations.
//
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// Creates the output representation for a type-preserving operation.
///
/// If [outputGenerator] is supplied, it defines the output representation.
/// Otherwise, [prototype] supplies it. A requested [Logic] result is always
/// normalized to a fresh ordinary [Logic], allowing constants and nets to be
/// used as sources without making them the output type.
@internal
LogicType createOperationOutput<LogicType extends Logic>({
  required String name,
  required String operation,
  int? width,
  Naming? naming,
  LogicType? prototype,
  LogicType Function({String? name})? outputGenerator,
}) {
  if (width != null && prototype != null && prototype.width != width) {
    throw PortWidthMismatchException(prototype, width);
  }

  final LogicType output;
  if (outputGenerator != null) {
    output = outputGenerator(name: name);
  } else if (LogicType == Logic) {
    if (width == null) {
      throw LogicConstructionException(
        '$operation requires a width for a normalized Logic output.',
      );
    }
    output = Logic(name: name, width: width, naming: naming) as LogicType;
  } else if (prototype != null) {
    output = prototype.cloneTyped(name: name);
  } else {
    throw LogicConstructionException(
      '$operation cannot infer a $LogicType output representation. '
      'Provide an outputGenerator.',
    );
  }

  if (width != null && output.width != width) {
    throw PortWidthMismatchException(output, width);
  }
  if (output is Const ||
      output.isNet ||
      (output is LogicStructure && (output.hasConsts || output.hasNets))) {
    throw LogicConstructionException(
      '$operation requires a driveable output, but $output is not driveable. '
      'Request <Logic> to normalize a constant or net source.',
    );
  }
  if (output.name != name) {
    throw LogicConstructionException(
      '$operation output generator did not apply the requested name "$name".',
    );
  }

  return output;
}

/// Validates that [source] can drive [output] without losing a domain type.
///
/// Structured sources must match the output structure exactly. Callers that
/// intentionally reinterpret a different structure as packed bits must pass
/// its [Logic.packed] representation instead.
@internal
void validateOperationSource(
  Logic source,
  Logic output, {
  required String operation,
}) {
  if (source.width != output.width) {
    throw PortWidthMismatchException.equalWidth(source, output);
  }

  if (source is LogicStructure && output is LogicStructure) {
    validateMatchingLogicStructure(source, output, operation: operation);
  } else if (source is LogicStructure && output is! LogicStructure) {
    // An explicit <Logic> result intentionally normalizes packed structures.
    return;
  } else if (source is! LogicStructure && output is LogicStructure) {
    // A scalar Logic source is an explicit packed representation.
    return;
  }
}

/// Returns a typed output generator that clones [schema].
@internal
LogicType Function({String? name})
    operationOutputClone<LogicType extends Logic>(LogicType schema) {
  final cloneFactory = _OperationOutputClone<LogicType>(schema);
  return cloneFactory.call;
}

class _OperationOutputClone<LogicType extends Logic> {
  final LogicType schema;

  _OperationOutputClone(this.schema);

  LogicType call({String? name}) => schema.cloneTyped(name: name);
}
