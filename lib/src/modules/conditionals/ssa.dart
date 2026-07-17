// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// ssa.dart
// Definitions for usage with combinational SSA.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// A signal that represents an SSA node in [Combinational.ssa] which is
/// associated with one specific [Combinational].
class SsaLogic extends Logic {
  /// The signal that this represents.
  final Logic ref;

  /// A unique identifier for the context of which [Combinational.ssa] it is
  /// associated with.
  final int context;

  /// Constructs a new SSA node referring to a signal in a specific context.
  SsaLogic(this.ref, this.context)
      : super(width: ref.width, name: ref.name, naming: Naming.mergeable);

  @override
  SsaLogic clone({String? name}) =>
      throw UnimplementedError('Should not clone an SsaLogic');
}
