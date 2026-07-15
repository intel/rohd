// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

//
// synth_structure_slice.dart
// Shared structure slice helper for synthesis backends.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/synth_operation_namer.dart';

/// A [BusSubset] used by synthesis backends to explicitly extract a
/// [LogicStructure] leaf from its packed parent representation.
@internal
class SynthStructureSlice extends BusSubset {
  final Logic _destination;

  /// Creates a synthesis structure slice over the selected indices of [bus].
  SynthStructureSlice(
    super.bus,
    super.startIndex,
    super.endIndex, {
    required Logic destination,
  })  : _destination = destination,
        super(
          name: SynthOperationNamer.instanceName(
            operationName: SynthOperationNamer.structureSliceOperationName,
            destination: destination,
          ),
        );

  @override
  bool get hasBuilt => true;

  @override
  Object get instanceNameKey => (
        operationName: SynthOperationNamer.structureSliceOperationName,
        destination: _destination,
      );
}
