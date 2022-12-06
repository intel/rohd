/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// long_chain_test.dart
/// Tests with long chains of combinational logic.
///
/// 2022 November 8
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/passthrough.dart';
import 'package:test/test.dart';

class LongChain extends Module {
  final int length;

  Logic get chainOut => output('chainOut');

  LongChain(Logic chainIn, {this.length = 1000}) : super(name: 'longChain') {
    chainIn = addInput('chainIn', chainIn);
    var intermediate = chainIn;
    for (var i = 0; i < length; i++) {
      intermediate = ~Passthrough(intermediate).out;
    }
    addOutput('chainOut') <= intermediate;
  }
}

void main() {
  test('long chain of combinational logic and modules', () async {
    final chainIn = Logic(name: 'chainIn');
    final chain = LongChain(chainIn);
    await chain.build();

    chainIn.put(0);
    expect(chain.chainOut.value.toInt(), equals(chain.length % 2));
  });
}
