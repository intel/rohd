/// Copyright (C) 2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// comb_sensitivity_search_test.dart
/// Unit tests related to Combinational sensitivity searching.
///
/// 2023 January 5
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class CombySubModule extends Module {
  Logic get b => output('b');
  CombySubModule(Logic a) : super(name: 'combySubModule') {
    a = addInput('a', a);
    addOutput('b');

    Combinational([b < a]);
  }
}

class ContainerModule extends Module {
  ContainerModule(Logic a) : super(name: 'containerModule') {
    a = addInput('a', a);
    final b = addOutput('b');
    final bb = addOutput('bb');

    final combySubMod = CombySubModule(a);

    // attach `b` output first so that the CombySubModule gets found by
    // the output search before the inverter for `bb`
    b <= combySubMod.b;

    bb <= ~combySubMod.b;
  }
}

void main() {
  test('build runs properly for comb sensitivity search', () async {
    final mod = ContainerModule(Logic());
    await mod.build();
  });
}
