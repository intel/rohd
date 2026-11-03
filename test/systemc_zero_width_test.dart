// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_zero_width_test.dart
// Tests SystemC generation and compilation for zero-width ports.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _EmptyAddressLeaf extends Module {
  _EmptyAddressLeaf(Logic address) {
    address = addInput('address', address, width: 0);
    addOutput('isZero') <= address.eq(0);
  }
}

class _EmptyAddressTop extends Module {
  _EmptyAddressTop() {
    final address = addInput('address', Logic(width: 0), width: 0);
    addOutput('externalMatch') <= _EmptyAddressLeaf(address).output('isZero');
    addOutput('constantMatch') <=
        _EmptyAddressLeaf(Const(0, width: 0)).output('isZero');
  }
}

void main() {
  tearDown(() async {
    ModuleServices.instance.reset();
    await Simulator.reset();
  });

  test('zero-width ports and constant bindings preserve empty-value semantics',
      () async {
    final top = _EmptyAddressTop();
    await top.build();
    final service = SystemCService(top, register: false);
    expect(service.output, isNot(contains('sc_uint<0>')));
    final directory =
        await Directory.systemTemp.createTemp('rohd_sc_zero_width_');
    try {
      await File('${directory.path}/model.h').writeAsString(service.output);
      await File('${directory.path}/test.cpp').writeAsString('''
#include "model.h"
int sc_main(int,char**) {
  sc_signal<bool> address,external_match,constant_match;
  ${service.instanceTypeOf(top)} dut("dut");
  dut.address(address); dut.externalMatch(external_match);
  dut.constantMatch(constant_match);
  address.write(true);
  sc_start(1,SC_NS);
  if(!external_match.read() || !constant_match.read()) return 1;
  address.write(false);
  sc_start(1,SC_NS);
  return external_match.read() && constant_match.read() ? 0 : 2;
}
''');
      final compile = await Process.run('g++', [
        '-std=c++17',
        '-O0',
        '${directory.path}/test.cpp',
        '-lsystemc',
        '-o',
        '${directory.path}/test',
      ]);
      expect(compile.exitCode, 0,
          reason: '${compile.stdout}\n${compile.stderr}');
      final run = await Process.run('${directory.path}/test', []);
      expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
