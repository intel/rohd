/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// passthrough.dart
/// A module that does nothing but pass a signal through.
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';

/// A very simple noop module that just passes a signal through.
class Passthrough extends Module {
  /// The input port.
  Logic get in_ => input('in');

  /// The output port.
  Logic get out => output('out');

  /// Constructs a simple pass-through module that performs no operations
  /// between [a] and [out].
  Passthrough(Logic a, [String name = 'passthrough']) : super(name: name) {
    addInput('in', a, width: a.width);
    addOutput('out', width: a.width);
    _setup();
  }

  void _setup() {
    final inner = Logic(name: 'inner', width: in_.width);
    inner <= in_;
    out <= inner;
  }
}
