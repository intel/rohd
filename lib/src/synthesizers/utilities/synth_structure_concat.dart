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

/// A [Swizzle] used by synthesis backends to explicitly assemble a
/// [LogicStructure] from its leaf elements.
@internal
class SynthStructureConcat extends Swizzle {
  /// The canonical base name for synthesized structure concat operations.
  static const String operationName = 'struct_concat';

  final LogicStructure _destination;

  /// Creates a synthesis structure concatenation from [signals].
  SynthStructureConcat(super.signals, {required LogicStructure destination})
      : _destination = destination,
        super(name: operationName);

  @override
  bool get hasBuilt => true;

  @override
  Object get instanceNameKey => (
        operationName: operationName,
        destination: _destination,
      );
}
