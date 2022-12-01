/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// multimodule5_test.dart
/// Unit tests for a hierarchy of multiple modules and multiple instantiation
/// (another type)
///
/// 2022 November 22
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/passthrough.dart';
import 'package:test/test.dart';

class TopModule extends Module {
  TopModule(Logic inPort) {
    inPort = addInput('inPort', inPort);

    final internalNet = Logic(name: 'internalNet');
    final outPort = addOutput('outPort');

    Combinational([internalNet < inPort]);
    Combinational([outPort < internalNet]);

    Passthrough(internalNet);
  }
}

void main() {
  test('multimodules5', () async {
    final mod = TopModule(Logic());
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('Passthrough'));
  });
}
