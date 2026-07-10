// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

//
// synth_structure_concat.dart
// Shared structure concatenation helper for synthesis backends.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/namer.dart';

/// A [Swizzle] used by synthesis backends to explicitly assemble a
/// [LogicStructure] from its leaf elements.
@internal
class SynthStructureConcat extends Swizzle {
  final LogicStructure _destination;

  /// Creates a synthesis structure concatenation from [signals].
  SynthStructureConcat(
    super.signals, {
    required LogicStructure destination,
  })  : _destination = destination,
        super(
          name: Namer.synthOperationInstanceName(
            operationName: Namer.synthStructureConcatOperationName,
            destination: destination,
          ),
        );

  @override
  bool get hasBuilt => true;

  @override
  Object get instanceNameKey => (
        operationName: Namer.synthStructureConcatOperationName,
        destination: _destination,
      );
}
