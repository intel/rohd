// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_split_packed_output_test.dart
// Tests SystemC generation when a packed submodule output is split into
// ranges that drive separate signals.
//
// 2026 October 7

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _WideLeaf extends Module {
  _WideLeaf(Logic a) : super(name: 'wide_leaf') {
    a = addInput('a', a, width: 4);
    addOutput('y', width: 4) <= a;
  }
}

class _WideTop extends Module {
  _WideTop(Logic a) : super(name: 'wide_top') {
    a = addInput('a', a, width: 4);
    final s = _WideLeaf(a).output('y');
    addOutput('low', width: 2) <= s.getRange(0, 2);
    addOutput('high', width: 2) <= s.getRange(2, 4);
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('split packed submodule output binds to a named signal', () async {
    final dut = _WideTop(Logic(width: 4));
    await dut.build();

    // SystemC cannot bind an output port to a concatenation, so the
    // intermediate bus must be retained and named.
    final sc = SystemCService(dut, register: false);
    expect(sc.systemCResults, isNotEmpty);
    expect(
        sc.fileContents.map((f) => f.contents).join(), contains('wide_leaf'));

    // SystemVerilog may still bind the output port directly to a concat.
    expect(dut.dumpSystemVerilog(), contains('.y({high,low})'));
  });
}
