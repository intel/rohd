// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_simcompare_test.dart
// Tests for SystemC synthesis and simulation comparison.
//
// 2026 May
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

/// A simple module with basic gates for testing SystemC synthesis.
class GateModule extends Module {
  GateModule(Logic a, Logic b) : super(name: 'GateModule') {
    a = addInput('a', a);
    b = addInput('b', b);
    final aAndB = addOutput('a_and_b');
    final aOrB = addOutput('a_or_b');
    final notA = addOutput('not_a');

    aAndB <= a & b;
    aOrB <= a | b;
    notA <= ~a;
  }
}

/// A simple counter for testing sequential SystemC synthesis.
class SimpleCounter extends Module {
  SimpleCounter(Logic clk, Logic reset, Logic en) : super(name: 'Counter') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    en = addInput('en', en);
    final val = addOutput('val', width: 8);

    final nextVal = Logic(name: 'nextVal', width: 8);

    Sequential(clk, reset: reset, [
      If(en, then: [nextVal < nextVal + 1], orElse: [nextVal < nextVal]),
    ]);

    val <= nextVal;
  }
}

/// A flip-flop module for testing.
class FlopModule extends Module {
  FlopModule(Logic clk, Logic reset, Logic d) : super(name: 'FlopModule') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    d = addInput('d', d, width: 8);
    final q = addOutput('q', width: 8);
    q <= flop(clk, d, reset: reset);
  }
}

/// A flip-flop with enable.
class FlopEnModule extends Module {
  FlopEnModule(Logic clk, Logic reset, Logic en, Logic d)
      : super(name: 'FlopEnModule') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    en = addInput('en', en);
    d = addInput('d', d, width: 8);
    final q = addOutput('q', width: 8);
    q <= flop(clk, d, reset: reset, en: en);
  }
}

/// Verifies that generated clocked processes capture on their first edge.
class FirstEdgeCaptureModule extends Module {
  FirstEdgeCaptureModule(Logic clk, Logic d) : super(name: 'FirstEdgeCapture') {
    clk = addInput('clk', clk);
    d = addInput('d', d, width: 8);

    addOutput('flopQ', width: 8) <= flop(clk, d);
    final sequentialQ = Logic(name: 'sequentialQ', width: 8);
    Sequential(clk, [
      sequentialQ < d,
    ]);
    addOutput('sequentialQ', width: 8) <= sequentialQ;
  }
}

/// Flops and Sequential blocks sharing signals but using different reset modes.
class MixedResetModesModule extends Module {
  MixedResetModesModule(Logic clk, Logic reset, Logic d)
      : super(name: 'MixedResetModesModule') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    d = addInput('d', d, width: 8);

    addOutput('syncQ', width: 8) <= flop(clk, d, reset: reset);
    addOutput('asyncQ', width: 8) <=
        flop(clk, d, reset: reset, asyncReset: true);

    final syncSequential = Logic(width: 8);
    final asyncSequential = Logic(width: 8);
    Sequential(clk, reset: reset, [
      syncSequential < d,
    ]);
    Sequential(clk, reset: reset, asyncReset: true, [
      asyncSequential < d,
    ]);
    addOutput('syncSequential', width: 8) <= syncSequential;
    addOutput('asyncSequential', width: 8) <= asyncSequential;
  }
}

/// A chained combinational module for checking generated sensitivity lists.
class ChainedGateModule extends Module {
  ChainedGateModule(Logic a, Logic b, Logic c)
      : super(name: 'ChainedGateModule') {
    a = addInput('a', a);
    b = addInput('b', b);
    c = addInput('c', c);
    final y = addOutput('y');

    final mid = (a & b).named('mid');
    y <= mid | c;
  }
}

class WideConditionalConstantModule extends Module {
  static final constant = (BigInt.one << 100) + BigInt.from(3);

  WideConditionalConstantModule(Logic select)
      : super(name: 'WideConditionalConstantModule') {
    select = addInput('select', select);
    final q = addOutput('q', width: 128);
    Combinational([
      If(
        select,
        then: [q < Const(constant, width: 128)],
        orElse: [q < 0],
      ),
    ]);
  }
}

class IntegerPowerModule extends Module {
  IntegerPowerModule(Logic base, Logic exponent)
      : super(name: 'IntegerPowerModule') {
    base = addInput('base', base, width: 64);
    exponent = addInput('exponent', exponent, width: 64);
    addOutput('result', width: 64) <= base.pow(exponent);
  }
}

class ShiftBoundaryModule extends Module {
  ShiftBoundaryModule(Logic data, Logic amount)
      : super(name: 'ShiftBoundaryModule') {
    data = addInput('data', data, width: 64);
    amount = addInput('amount', amount, width: 7);
    addOutput('left', width: 64) <= LShift(data, amount).out;
    addOutput('right', width: 64) <= RShift(data, amount).out;
    addOutput('arithmeticRight', width: 64) <= ARShift(data, amount).out;
  }
}

class DivideModuloModule extends Module {
  DivideModuloModule(Logic dividend, Logic divisor, {required int width})
      : super(name: 'DivideModulo${width}Module') {
    dividend = addInput('dividend', dividend, width: width);
    divisor = addInput('divisor', divisor, width: width);
    addOutput('quotient', width: width) <= dividend / divisor;
    addOutput('remainder', width: width) <= dividend % divisor;
  }
}

class CppKeywordModule extends Module {
  CppKeywordModule(Logic autoSource, Logic autoSuffixSource)
      : super(name: 'CppKeywordModule') {
    final autoPort = addInput('auto', autoSource, width: 8);
    final autoSuffixPort = addInput('auto_', autoSuffixSource, width: 8);
    addOutput('concept', width: 8) <= autoPort;
    addOutput('result', width: 8) <= autoSuffixPort;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  tearDownAll(SimCompare.cleanupSystemCCache);

  group('SimCompare SystemC', () {
    test('gate module passes vectors', () async {
      final a = Logic(name: 'a');
      final b = Logic(name: 'b');
      final mod = GateModule(a, b);
      await mod.build();

      final vectors = [
        Vector({'a': 0, 'b': 0}, {'a_and_b': 0, 'a_or_b': 0, 'not_a': 1}),
        Vector({'a': 1, 'b': 0}, {'a_and_b': 0, 'a_or_b': 1, 'not_a': 0}),
        Vector({'a': 0, 'b': 1}, {'a_and_b': 0, 'a_or_b': 1, 'not_a': 1}),
        Vector({'a': 1, 'b': 1}, {'a_and_b': 1, 'a_or_b': 1, 'not_a': 0}),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('wide conditional constant retains upper bits', () async {
      final mod = WideConditionalConstantModule(Logic());
      await mod.build();

      SimCompare.checkSystemCVector(mod, [
        Vector({'select': 1}, {'q': WideConditionalConstantModule.constant}),
        Vector({'select': 0}, {'q': BigInt.zero}),
      ]);
    });

    test('integer power remains exact beyond double precision', () async {
      final mod = IntegerPowerModule(Logic(width: 64), Logic(width: 64));
      await mod.build();

      SimCompare.checkSystemCVector(mod, [
        Vector(
          {'base': 3, 'exponent': 34},
          {'result': BigInt.from(3).pow(34)},
        ),
      ]);
    });

    test('narrow shift count guards the data-width boundary', () async {
      final mod = ShiftBoundaryModule(Logic(width: 64), Logic(width: 7));
      await mod.build();
      final highBit = BigInt.one << 63;
      final allOnes = (BigInt.one << 64) - BigInt.one;

      SimCompare.checkSystemCVector(mod, [
        Vector(
          {'data': 1, 'amount': 64},
          {'left': 0, 'right': 0, 'arithmeticRight': 0},
        ),
        Vector(
          {'data': 1, 'amount': 65},
          {'left': 0, 'right': 0, 'arithmeticRight': 0},
        ),
        Vector(
          {'data': highBit, 'amount': 64},
          {'left': 0, 'right': 0, 'arithmeticRight': allOnes},
        ),
      ]);
    });

    test('division and modulo compile across the 64-bit boundary', () async {
      for (final width in [64, 65]) {
        final mod = DivideModuloModule(
          Logic(width: width),
          Logic(width: width),
          width: width,
        );
        await mod.build();

        SimCompare.checkSystemCVector(mod, [
          Vector(
            {'dividend': BigInt.from(15), 'divisor': BigInt.from(3)},
            {'quotient': BigInt.from(5), 'remainder': BigInt.zero},
          ),
        ]);
      }
    });

    test('C++ keyword port names are collision-safe', () async {
      final mod = CppKeywordModule(Logic(width: 8), Logic(width: 8));
      await mod.build();

      final systemc = SystemCService(mod, register: false).output;
      expect(systemc, contains(' auto_{"auto_"};'));
      expect(systemc, contains(' auto__{"auto__"};'));
      expect(systemc, contains(' concept_{"concept_"};'));

      SimCompare.checkSystemCVector(mod, [
        Vector(
          {'auto': 0x12, 'auto_': 0x34},
          {'concept': 0x12, 'result': 0x34},
        ),
      ]);
    });

    test('counter module passes vectors', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final en = Logic(name: 'en');
      final mod = SimpleCounter(clk, reset, en);
      await mod.build();

      // Same vectors as counter_test.dart (iverilog-compatible timing)
      final vectors = [
        Vector({'en': 0, 'reset': 0}, {}),
        Vector({'en': 0, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 1}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 0}),
        Vector({'en': 1, 'reset': 0}, {'val': 1}),
        Vector({'en': 1, 'reset': 0}, {'val': 2}),
        Vector({'en': 1, 'reset': 0}, {'val': 3}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 4}),
        Vector({'en': 1, 'reset': 0}, {'val': 4}),
        Vector({'en': 0, 'reset': 0}, {'val': 5}),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('flip-flop module passes vectors', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final d = Logic(name: 'd', width: 8);
      final mod = FlopModule(clk, reset, d);
      await mod.build();

      // Flop: output follows input with 1-cycle latency
      final vectors = [
        Vector({'d': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0xAA, 'reset': 0}, {'q': 0}),
        Vector({'d': 0xBB, 'reset': 0}, {'q': 0xAA}),
        Vector({'d': 0xCC, 'reset': 0}, {'q': 0xBB}),
        Vector({'d': 0xDD, 'reset': 0}, {'q': 0xCC}),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('flip-flop with enable passes vectors', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final en = Logic(name: 'en');
      final d = Logic(name: 'd', width: 8);
      final mod = FlopEnModule(clk, reset, en, d);
      await mod.build();

      // When en=0, q holds; when en=1, q follows d with 1-cycle latency
      final vectors = [
        Vector({'d': 0, 'en': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0, 'en': 0, 'reset': 1}, {'q': 0}),
        Vector({'d': 0x42, 'en': 1, 'reset': 0}, {'q': 0}),
        Vector({'d': 0x55, 'en': 1, 'reset': 0}, {'q': 0x42}),
        Vector({'d': 0xFF, 'en': 0, 'reset': 0}, {'q': 0x55}),
        Vector({'d': 0x00, 'en': 0, 'reset': 0}, {'q': 0x55}),
        Vector({'d': 0x99, 'en': 1, 'reset': 0}, {'q': 0x55}),
        Vector({'d': 0xAA, 'en': 1, 'reset': 0}, {'q': 0x99}),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('mixed reset modes remain separate compiled processes', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final d = Logic(name: 'd', width: 8);
      final mod = MixedResetModesModule(clk, reset, d);
      await mod.build();

      final vectors = [
        Vector({
          'd': 0,
          'reset': 1
        }, {
          'syncQ': 0,
          'asyncQ': 0,
          'syncSequential': 0,
          'asyncSequential': 0,
        }),
        Vector({
          'd': 0x5a,
          'reset': 0
        }, {
          'syncQ': 0,
          'asyncQ': 0,
          'syncSequential': 0,
          'asyncSequential': 0,
        }),
        Vector({
          'd': 0x5a,
          'reset': 0
        }, {
          'syncQ': 0x5a,
          'asyncQ': 0x5a,
          'syncSequential': 0x5a,
          'asyncSequential': 0x5a,
        }),
        // Reset is asserted after the previous rising edge. Async members
        // reset before this check; synchronous members retain their values.
        Vector({
          'd': 0x5a,
          'reset': 1
        }, {
          'syncQ': 0x5a,
          'asyncQ': 0,
          'syncSequential': 0x5a,
          'asyncSequential': 0,
        }),
        // The next rising edge resets the synchronous members.
        Vector({
          'd': 0x5a,
          'reset': 1
        }, {
          'syncQ': 0,
          'asyncQ': 0,
          'syncSequential': 0,
          'asyncSequential': 0,
        }),
      ];

      SimCompare.checkSystemCVector(mod, vectors);
    });

    test('clocked processes capture known data on the first driven edge',
        () async {
      final mod = FirstEdgeCaptureModule(
        Logic(name: 'clk'),
        Logic(name: 'd', width: 8),
      );
      await mod.build();

      final vectorExecutable = SimCompare.buildSystemCVectorExecutable(mod);
      if (vectorExecutable == null) {
        return;
      }

      final systemcHome = [
        '/opt/systemc/include',
        '/usr/include',
      ].firstWhere(
        (path) => File('$path/systemc.h').existsSync(),
        orElse: () => '',
      );
      expect(systemcHome, isNotEmpty);

      final tempDir =
          Directory('tmp_test').createTempSync('systemc_first_driven_edge_');
      final source = File('${tempDir.path}/first_edge.cpp');
      final executable = '${tempDir.path}/first_edge';
      try {
        final apiSymbols = Process.runSync(
          'nm',
          ['-D', '${vectorExecutable.scLib}/libsystemc.so'],
        ).stdout.toString();
        final cxxStandard =
            apiSymbols.contains('cxx202002L') ? 'c++20' : 'c++17';
        source.writeAsStringSync('''
#include <systemc.h>

${SystemCService(mod, register: false).output}

int sc_main(int, char*[]) {
  sc_signal<bool> clk("clk");
  sc_signal<sc_uint<8>> d("d");
  sc_signal<sc_uint<8>> flopQ("flopQ");
  sc_signal<sc_uint<8>> sequentialQ("sequentialQ");
  FirstEdgeCaptureModule dut("dut");
  dut.clk(clk);
  dut.d(d);
  dut.flopQ(flopQ);
  dut.sequentialQ(sequentialQ);

  clk.write(false);
  d.write(42);
  sc_start(SC_ZERO_TIME);
  clk.write(true);
  sc_start(sc_time(1, SC_NS));

  if (flopQ.read() != 42 || sequentialQ.read() != 42) {
    cerr << "first edge capture failed: flopQ=" << flopQ.read()
         << ", sequentialQ=" << sequentialQ.read() << endl;
    return 1;
  }
  return 0;
}
''');

        final compile = Process.runSync(
          'g++',
          [
            '-std=$cxxStandard',
            '-I$systemcHome',
            source.path,
            '-L${vectorExecutable.scLib}',
            '-lsystemc',
            '-o',
            executable,
          ],
        );
        expect(
          compile.exitCode,
          0,
          reason: 'Could not compile first-edge SystemC regression:\n'
              '${compile.stdout}\n${compile.stderr}',
        );

        final run = Process.runSync(
          executable,
          const [],
          environment: {
            'LD_LIBRARY_PATH': vectorExecutable.scLib,
            'SC_COPYRIGHT_MESSAGE': 'DISABLE',
          },
        );
        expect(
          run.exitCode,
          0,
          reason: 'First-edge SystemC regression failed:\n'
              '${run.stdout}\n${run.stderr}',
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('independent inline gates share a method', () async {
      final mod = GateModule(Logic(name: 'a'), Logic(name: 'b'));
      await mod.build();

      final systemc = SystemCService(mod, register: false).output;
      final assignMethods =
          RegExp(r'SC_METHOD\(assign_\d+\);').allMatches(systemc).toList();

      expect(assignMethods, hasLength(1));
      expect(systemc, contains('sensitive << a;'));
      expect(systemc, contains('sensitive << b;'));
      expect(systemc, contains('a_and_b = a.read() & b.read();'));
      expect(systemc, contains('a_or_b = a.read() | b.read();'));
      expect(systemc, contains('not_a = !a.read();'));
    });

    test('chained inline gates use minimal sensitivity lists', () async {
      final mod = ChainedGateModule(
        Logic(name: 'a'),
        Logic(name: 'b'),
        Logic(name: 'c'),
      );
      await mod.build();

      final systemc = SystemCService(mod, register: false).output;
      final sensitivityBlocks = RegExp(
        r'SC_METHOD\(assign_\d+\);\n((?:    sensitive << .+;\n)+)',
      ).allMatches(systemc).map((match) => match.group(1)!).toList();

      expect(sensitivityBlocks, hasLength(2));
      expect(
        sensitivityBlocks,
        contains(
          allOf(
            contains('sensitive << a;'),
            contains('sensitive << b;'),
            isNot(contains('sensitive << mid;')),
          ),
        ),
      );
      expect(
        sensitivityBlocks,
        contains(
          allOf(
            contains('sensitive << mid;'),
            contains('sensitive << c;'),
            isNot(contains('sensitive << a;')),
            isNot(contains('sensitive << b;')),
          ),
        ),
      );
    });

    test('counter trace-based comparison', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic(name: 'reset');
      final en = Logic(name: 'en');
      final mod = SimpleCounter(clk, reset, en);
      await mod.build();

      // Use the trace-based approach: just write normal simulation code,
      // no vectors needed. The method records all I/O at every clock edge
      // and replays through SystemC.
      final result = await SimCompare.systemcSimCompare(
        mod,
        clk,
        stimulus: () async {
          reset.inject(1);
          en.inject(0);
          Simulator.registerAction(25, () {
            reset.put(0);
            en.put(1);
          });
          Simulator.registerAction(65, () {
            en.put(0);
          });
          Simulator.registerAction(85, () {
            en.put(1);
          });
          Simulator.setMaxSimTime(120);
        },
      );
      expect(result, isTrue);
    });
  });
}
