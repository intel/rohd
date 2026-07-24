// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

//
// synth_array_slice.dart
// Shared array slice helper for synthesis backends.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/synth_operation_namer.dart';

/// A [BusSubset] used by synthesis backends to explicitly extract a
/// [LogicArray] element from its packed parent representation.
@internal
class SynthArraySlice extends BusSubset {
  final Logic _destination;

  /// Creates a synthesis array slice over the selected indices of [bus].
  SynthArraySlice(
    super.bus,
    super.startIndex,
    super.endIndex, {
    required Logic destination,
  })  : _destination = destination,
        super(
          name: SynthOperationNamer.instanceName(
            operationName: SynthOperationNamer.arraySliceOperationName,
            destination: destination,
          ),
        );

  @override
  bool get hasBuilt => true;

  @override
  Object get instanceNameKey => (
        operationName: SynthOperationNamer.arraySliceOperationName,
        destination: _destination,
      );
}
