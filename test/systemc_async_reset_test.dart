// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_async_reset_test.dart
// Verifies that an asynchronously reset Sequential emits its declared reset
// value in the SystemC reset branch, rather than zero.
//
// 2026 October 18
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _AsyncResetTop extends Module {
  _AsyncResetTop(Logic clk, Logic reset, Logic d) : super(name: 'top') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    d = addInput('d', d, width: 8);
    final q = addOutput('q', width: 8);

    final r = Logic(name: 'r', width: 8);
    Sequential(clk, [r < d],
        reset: reset, asyncReset: true, resetValues: {r: 0xAB});
    q <= r;
  }
}

void main() {
  tearDown(ModuleServices.instance.reset);

  test('async Sequential reset branch emits the declared reset value',
      () async {
    final top = _AsyncResetTop(
      Logic(name: 'clk'),
      Logic(name: 'reset'),
      Logic(name: 'd', width: 8),
    );
    await top.build();

    final outDir = Directory.systemTemp.createTempSync('rohd_sc_async_reset_');
    try {
      final sc = SystemCService(top, outputDirectory: outDir.path);
      final src = sc.contentsByDefinitionName.values.join('\n');

      // The async reset arm is the branch guarded by reset.read().
      final resetArm = RegExp(r'if \(reset\.read\(\)\) \{([\s\S]*?)\} else \{')
          .firstMatch(src)
          ?.group(1);
      expect(resetArm, isNotNull, reason: 'no async reset branch:\n$src');
      expect(resetArm, contains('171'),
          reason: 'reset branch must carry 0xAB (171):\n$resetArm');
      expect(resetArm, isNot(contains('r = 0;')),
          reason: 'reset branch must not force zero:\n$resetArm');
    } finally {
      outDir.deleteSync(recursive: true);
    }
  });
}
