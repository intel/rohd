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

/// A [Swizzle] used by synthesis backends to explicitly assemble a
/// [BaseLogicArray] from its elements.
@internal
class SynthArrayConcat extends Swizzle {
  /// The canonical base name for synthesized array concat operations.
  static const String operationName = 'array_concat';

  final BaseLogicArray _destination;

  /// Creates a synthesis array concatenation from [signals].
  SynthArrayConcat(super.signals, {required BaseLogicArray destination})
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
