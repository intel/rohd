// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic_name_config_test.dart
// Unit tests for logic naming using configuration for naming preferences.
//
// 2023 November 3
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class FunctionGeneratedModule extends Module {
  FunctionGeneratedModule(
      void Function(Logic in1, Logic in2, Logic out1) builder) {
    builder(
      addInput('in1', Logic()),
      addInput('in2', Logic()),
      addOutput('out1'),
    );
  }
}

void main() {
  test('renameable name stays present', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic(name: 'intermediate');
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    expect(sv, contains('intermediate'));
  });

  test('mergeable name is omitted', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic(
        name: 'intermediate',
        naming: Naming.mergeable,
      );
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // no intermediate
    expect(sv.contains('intermediate'), isFalse);
  });

  test('unnamed is omitted', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic();
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // just the ports
    expect('logic'.allMatches(sv).length, 3);
  });

  test('unnamed is omitted even when named', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate = Logic(name: 'badname', naming: Naming.unnamed);
      intermediate <= in1;
      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // just the ports
    expect('logic'.allMatches(sv).length, 3);
  });

  test('reserved name stays present', () async {
    final dut = FunctionGeneratedModule((in1, in2, out1) {
      final intermediate =
          Logic(name: 'intermediate_1', naming: Naming.reserved);
      intermediate <= in1;

      for (var i = 0; i < 6; i++) {
        Logic(name: 'intermediate') <= in2;
      }

      out1 <= intermediate;
    });
    await dut.build();
    final sv = dut.generateSynth();

    // held one sticks
    expect(sv, contains('intermediate_1 = in1'));

    // renaming works, skips over reserved
    expect(sv, contains('intermediate_2 = in2'));
  });

  test('reserved and input with same name errors', () async {
    try {
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        final intermediate = Logic(name: 'in1', naming: Naming.reserved);
        intermediate <= in1;

        out1 <= intermediate;
      });
      await dut.build();
      dut.generateSynth();
      fail('expected an exception!');
    } on Exception catch (e) {
      expect(e, isA<UnavailableReservedNameException>());
    }
  });

  test('reserved and output with same name errors', () async {
    try {
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        final intermediate = Logic(name: 'out1', naming: Naming.reserved);
        intermediate <= in1;

        out1 <= intermediate;
      });
      await dut.build();
      dut.generateSynth();
      fail('expected an exception!');
    } on Exception catch (e) {
      expect(e, isA<UnavailableReservedNameException>());
    }
  });

  test('2x reserved name errors', () async {
    try {
      final dut = FunctionGeneratedModule((in1, in2, out1) {
        final intermediate =
            Logic(name: 'intermediate', naming: Naming.reserved);
        intermediate <= in1;

        final intermediate2 =
            Logic(name: 'intermediate', naming: Naming.reserved);
        intermediate2 <= in2;

        out1 <= intermediate | intermediate2;
      });
      await dut.build();
      dut.generateSynth();
      fail('expected an exception!');
    } on Exception catch (e) {
      expect(e, isA<UnavailableReservedNameException>());
    }
  });
}

// TODO: testplan:
// - unpreferred
//    - gets lower priority when merging
//    - automatically unpreferred if starts with _ (via function)
// - preference vs. availability? coverage? full priority with randomness?