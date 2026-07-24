// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

//
// synth_array_concat.dart
// Shared array concatenation helper for synthesis backends.
//
// 2026 July 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/synth_operation_namer.dart';

/// A [Swizzle] used by synthesis backends to explicitly assemble a
/// [LogicArray] from its elements.
@internal
class SynthArrayConcat extends Swizzle {
  final LogicArray _destination;

  /// Creates a synthesis array concatenation from [signals].
  SynthArrayConcat(super.signals, {required LogicArray destination})
      : _destination = destination,
        super(
          name: SynthOperationNamer.instanceName(
            operationName: SynthOperationNamer.arrayConcatOperationName,
            destination: destination,
          ),
        );

  @override
  bool get hasBuilt => true;

  @override
  Object get instanceNameKey => (
        operationName: SynthOperationNamer.arrayConcatOperationName,
        destination: _destination,
      );
}
