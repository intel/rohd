// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// operation_utils.dart
// Shared construction and validation for type-preserving operations.
//
// 2026 October 18
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/signals/signals.dart' show BaseLogicArray;

bool _sameDimensions(List<int> first, List<int> second) =>
    first.length == second.length &&
    first.indexed.every((entry) => entry.$2 == second[entry.$1]);

void _validateMatchingOperationStructure(
  Logic first,
  Logic second,
  String operation,
  String path,
) {
  if (first.width != second.width) {
    throw LogicConstructionException(
      '$operation operands differ in width at $path.',
    );
  }

  if (first is LogicEnum || second is LogicEnum) {
    if (first is! LogicEnum || !first.isEquivalentTypeTo(second)) {
      throw LogicConstructionException(
        '$operation operands use incompatible LogicEnum mappings at $path.',
      );
    }
  }

  if (first is LogicStructure || second is LogicStructure) {
    if (first is! LogicStructure ||
        second is! LogicStructure ||
        first.runtimeType != second.runtimeType ||
        first.elements.length != second.elements.length) {
      throw LogicConstructionException(
        '$operation operands differ in structure at $path.',
      );
    }

    if (first is BaseLogicArray && second is BaseLogicArray) {
      if (!_sameDimensions(first.dimensions, second.dimensions) ||
          first.elementWidth != second.elementWidth ||
          first.numUnpackedDimensions != second.numUnpackedDimensions ||
          first.isNet != second.isNet) {
        throw LogicConstructionException(
          '$operation array operands differ in shape at $path.',
        );
      }
      if (first is TypedLogicArray &&
          second is TypedLogicArray &&
          !identical(first.valueCodec, second.valueCodec)) {
        throw LogicConstructionException(
          '$operation typed-array operands use different value codecs at '
          '$path. Convert through packed to reinterpret their bits explicitly.',
        );
      }
    }

    for (var index = 0; index < first.elements.length; index++) {
      _validateMatchingOperationStructure(
        first.elements[index],
        second.elements[index],
        operation,
        '$path[$index]',
      );
    }
  }
}

/// Verifies structural compatibility for type-preserving operations.
///
/// This is an internal operation-building contract, not a signal API.
@internal
void validateMatchingOperationStructure(
  LogicStructure first,
  LogicStructure second, {
  required String operation,
}) =>
    _validateMatchingOperationStructure(first, second, operation, 'root');

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

  if (source is LogicEnum &&
      output is LogicEnum &&
      !source.isEquivalentTypeTo(output)) {
    throw LogicConstructionException(
      '$operation source and output use incompatible LogicEnum mappings.',
    );
  }

  if (source is LogicStructure && output is LogicStructure) {
    validateMatchingOperationStructure(source, output, operation: operation);
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
