/// Copyright (C) 2021 Intel Corporation
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
  Logic get a => input('a');

  /// The output port.
  Logic get b => output('b');

  /// Constructs a simple pass-through module that performs no operations
  /// between [a] and [b].
  Passthrough(Logic a, [String name = 'passthrough']) : super(name: name) {
    addInput('a', a);
    addOutput('b');
    _setup();
  }

  void _setup() {
    final inner = Logic(name: 'inner');
    inner <= a;
    b <= inner;
  }
}
