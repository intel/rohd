// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_structure_signature.dart
// Internal structural signatures for operation module definitions.

import 'package:meta/meta.dart';
import 'package:rohd/src/signals/signals.dart';

String _logicShapeSignature(Logic logic) {
  if (logic is BaseLogicArray) {
    final signatures =
        logic.arrayElements.map(_logicShapeSignature).toList(growable: false);
    final elementSignature = signatures.isEmpty
        ? 'E'
        : signatures.every((signature) => signature == signatures.first)
            ? 'R${signatures.length}_${signatures.first}'
            : 'H${signatures.join('_')}';
    return 'A${logic.dimensions.join('x')}_W${logic.elementWidth}_'
        'U${logic.numUnpackedDimensions}_${logic.isNet ? 'N' : 'L'}_'
        '$elementSignature';
  }
  if (logic is LogicStructure) {
    return 'S${logic.elements.length}_'
        '${logic.elements.map(_logicShapeSignature).join('_')}';
  }
  return '${logic is Const ? 'C' : logic.isNet ? 'N' : 'L'}${logic.width}';
}

/// Returns an internal signature for a structure's recursive geometry.
///
/// This is used only when an operation's generated module definition depends
/// on the represented structure shape. It is intentionally not exported from
/// the public signal API.
@internal
String logicStructureShapeSignature(LogicStructure structure) =>
    _logicShapeSignature(structure);
