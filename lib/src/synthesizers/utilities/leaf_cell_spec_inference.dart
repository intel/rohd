// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// leaf_cell_spec_inference.dart
// Inference bridge from existing inline modules to leaf-cell metadata.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/leaf_cell_spec.dart';

/// Infers a semantic [LeafCellSpec] for existing inline modules.
///
/// This bridges current type-based inline modules into backend-neutral leaf
/// metadata without requiring those modules to implement [LeafCellProvider]
/// immediately.
LeafCellSpec? leafCellSpecForInlineModule(InlineLeaf module) {
  if (module is LeafCellProvider) {
    return (module as LeafCellProvider).leafCellSpec;
  }

  if (module is NotGate) {
    return LeafCellSpec(
      operation: LeafOperationKind.not,
      metadata: {
        'outputWidth': module.outputs.values.first.width,
      },
    );
  }

  if (module is And2Gate) {
    return const LeafCellSpec(operation: LeafOperationKind.and);
  }
  if (module is Or2Gate) {
    return const LeafCellSpec(operation: LeafOperationKind.or);
  }
  if (module is Xor2Gate) {
    return const LeafCellSpec(operation: LeafOperationKind.xor);
  }

  if (module is Subtract) {
    return const LeafCellSpec(operation: LeafOperationKind.subtract);
  }
  if (module is Multiply) {
    return const LeafCellSpec(operation: LeafOperationKind.multiply);
  }
  if (module is Divide) {
    return const LeafCellSpec(operation: LeafOperationKind.divide);
  }
  if (module is Modulo) {
    return const LeafCellSpec(operation: LeafOperationKind.modulo);
  }
  if (module is Power) {
    return LeafCellSpec(
      operation: LeafOperationKind.power,
      metadata: {
        'inputWidth': module.inputs.values.first.width,
        'makeSelfDetermined': true,
      },
    );
  }

  if (module is Equals) {
    return const LeafCellSpec(operation: LeafOperationKind.equals);
  }
  if (module is NotEquals) {
    return const LeafCellSpec(operation: LeafOperationKind.notEquals);
  }
  if (module is LessThan) {
    return const LeafCellSpec(operation: LeafOperationKind.lessThan);
  }
  if (module is GreaterThan) {
    return const LeafCellSpec(operation: LeafOperationKind.greaterThan);
  }
  if (module is LessThanOrEqual) {
    return const LeafCellSpec(operation: LeafOperationKind.lessThanOrEqual);
  }
  if (module is GreaterThanOrEqual) {
    return const LeafCellSpec(operation: LeafOperationKind.greaterThanOrEqual);
  }

  if (module is AndUnary) {
    return LeafCellSpec(
      operation: LeafOperationKind.andUnary,
      metadata: {
        'inputWidth': module.inputs.values.first.width,
      },
    );
  }
  if (module is OrUnary) {
    return LeafCellSpec(
      operation: LeafOperationKind.orUnary,
      metadata: {
        'inputWidth': module.inputs.values.first.width,
      },
    );
  }
  if (module is XorUnary) {
    return LeafCellSpec(
      operation: LeafOperationKind.xorUnary,
      metadata: {
        'inputWidth': module.inputs.values.first.width,
      },
    );
  }

  if (module is LShift) {
    return LeafCellSpec(
      operation: LeafOperationKind.shiftLeft,
      metadata: {
        'inputWidth': module.inputs.values.first.width,
        'shiftAmountWidth': module.inputs.values.toList()[1].width,
      },
    );
  }
  if (module is RShift) {
    return LeafCellSpec(
      operation: LeafOperationKind.shiftRight,
      metadata: {
        'inputWidth': module.inputs.values.first.width,
        'shiftAmountWidth': module.inputs.values.toList()[1].width,
      },
    );
  }
  if (module is ARShift) {
    return LeafCellSpec(
      operation: LeafOperationKind.arithmeticShiftRight,
      metadata: {
        'inputWidth': module.inputs.values.first.width,
        'shiftAmountWidth': module.inputs.values.toList()[1].width,
      },
    );
  }

  if (module is Mux) {
    return LeafCellSpec(
      operation: LeafOperationKind.mux,
      metadata: {
        'outputWidth': module.out.width,
      },
    );
  }
  if (module is IndexGate) {
    return LeafCellSpec(
      operation: LeafOperationKind.bitIndex,
      metadata: {
        'originalWidth': module.inputs.values.first.width,
      },
    );
  }

  if (module is BusSubset) {
    return LeafCellSpec(
      operation: LeafOperationKind.busSubset,
      metadata: {
        'inputWidth': module.original.width,
        'startIndex': module.startIndex,
        'endIndex': module.endIndex,
      },
    );
  }

  if (module is Swizzle) {
    final inputPorts = {
      ...module.inputs,
      ...module.inOuts,
    }..remove(module.resultSignalName);
    return LeafCellSpec(
      operation: LeafOperationKind.swizzle,
      metadata: {
        'inputCount': inputPorts.length,
        'inputWidths': inputPorts.values.map((input) => input.width).toList(),
        'inputIsArrayMember':
            inputPorts.values.map((input) => input.isArrayMember).toList(),
        'inputHasUnpackedArraySource':
            inputPorts.values.map(_hasUnpackedArraySource).toList(),
      },
    );
  }
  if (module is ReplicationOp) {
    final inputWidth = module.inputs.values.first.width;
    final outputWidth = module.replicated.width;
    return LeafCellSpec(
      operation: LeafOperationKind.replication,
      metadata: {
        'inputWidth': inputWidth,
        'outputWidth': outputWidth,
        'replicationCount': outputWidth ~/ inputWidth,
      },
    );
  }

  return null;
}

bool _hasUnpackedArraySource(Logic input) {
  var current = input.srcConnection;
  while (current?.parentStructure != null) {
    final parentStructure = current!.parentStructure!;
    if (parentStructure is LogicArray &&
        parentStructure.numUnpackedDimensions > 0) {
      return true;
    }
    current = parentStructure;
  }

  return false;
}
