/// Copyright (C) 2021-2023 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// wave_dumper_test.dart
/// Tests for the WaveDumper
///
/// 2021 November 4
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:async';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/vcd_parser.dart';
import 'package:test/test.dart';

class SimpleModule extends Module {
  SimpleModule(Logic a) {
    a = addInput('a', a, width: a.width);
    addOutput('b', width: a.width) <= ~a;
  }
}

const tempDumpDir = 'tmp_test';

/// Gets the path of the VCD file based on a name.
String temporaryDumpPath(String name) => '$tempDumpDir/temp_dump_$name.vcd';

/// Attaches a [WaveDumper] to [module] to VCD with [name].
void createTemporaryDump(Module module, String name) {
  Directory(tempDumpDir).createSync(recursive: true);
  final tmpDumpFile = temporaryDumpPath(name);
  WaveDumper(module, outputPath: tmpDumpFile);
}

/// Deletes the temporary VCD file associated with [name].
void deleteTemporaryDump(String name) {
  final tmpDumpFile = temporaryDumpPath(name);
  File(tmpDumpFile).deleteSync();
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('attach dumper after put', () async {
    final a = Logic(name: 'a');
    final mod = SimpleModule(a);
    await mod.build();

    const dumpName = 'dumpAfterPut';

    a.put(1);
    createTemporaryDump(mod, dumpName);

    Simulator.registerAction(10, () => a.put(0));
    await Simulator.run();

    final vcdContents = File(temporaryDumpPath(dumpName)).readAsStringSync();

    expect(
        VcdParser.confirmValue(vcdContents, 'a', 0, LogicValue.ofString('1')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 5, LogicValue.ofString('1')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
        equals(true));

    deleteTemporaryDump(dumpName);
  });

  test('attach dumper before put', () async {
    final a = Logic(name: 'a');
    final mod = SimpleModule(a);
    await mod.build();

    const dumpName = 'dumpBeforePut';

    createTemporaryDump(mod, dumpName);
    a.inject(1);

    Simulator.registerAction(10, () => a.put(0));
    Simulator.registerAction(20, () => a.put(1));
    await Simulator.run();

    final vcdContents = File(temporaryDumpPath(dumpName)).readAsStringSync();

    expect(
        VcdParser.confirmValue(vcdContents, 'a', 0, LogicValue.ofString('1')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 1, LogicValue.ofString('1')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 20, LogicValue.ofString('1')),
        equals(true));

    deleteTemporaryDump(dumpName);
  });

  test('multiple injects in the same timestamp', () async {
    final clk = SimpleClockGenerator(10).clk;
    final a = Logic(name: 'a');
    final mod = SimpleModule(a);
    a <= clk;

    await mod.build();

    const dumpName = 'multiInject';

    createTemporaryDump(mod, dumpName);

    Simulator.setMaxSimTime(100);
    unawaited(Simulator.run());

    await clk.nextPosedge;
    await clk.nextPosedge;
    await clk.nextPosedge;

    // inject a 0 on a when it should be 1 already from the clock
    a.inject(0);

    await Simulator.simulationEnded;

    final vcdContents = File(temporaryDumpPath(dumpName)).readAsStringSync();

    expect(
        VcdParser.confirmValue(vcdContents, 'a', 0, LogicValue.ofString('0')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 5, LogicValue.ofString('1')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 35, LogicValue.ofString('0')),
        equals(true));

    deleteTemporaryDump(dumpName);
  });

  test('multi-bit value', () async {
    final a = Logic(name: 'a', width: 8);
    final mod = SimpleModule(a);
    await mod.build();

    const dumpName = 'multiBit';

    createTemporaryDump(mod, dumpName);
    a.inject(0x5a);

    Simulator.registerAction(10, () => a.put(0xa5));
    await Simulator.run();

    final vcdContents = File(temporaryDumpPath(dumpName)).readAsStringSync();

    expect(
        VcdParser.confirmValue(vcdContents, 'a', 0, LogicValue.ofInt(0x5a, 8)),
        equals(true));
    expect(
        VcdParser.confirmValue(vcdContents, 'a', 10, LogicValue.ofInt(0xa5, 8)),
        equals(true));

    deleteTemporaryDump(dumpName);
  });

  test('multi-bit value mixed invalid', () async {
    final a = Logic(name: 'a', width: 8);
    final mod = SimpleModule(a);
    await mod.build();

    const dumpName = 'multiBitInvalid';

    createTemporaryDump(mod, dumpName);
    a.inject(LogicValue.ofString('01xzzx10'));

    Simulator.registerAction(10, () => a.put(LogicValue.ofString('0x0x1z1z')));
    await Simulator.run();

    final vcdContents = File(temporaryDumpPath(dumpName)).readAsStringSync();

    expect(
        VcdParser.confirmValue(
            vcdContents, 'a', 0, LogicValue.ofString('01xzzx10')),
        equals(true));
    expect(
        VcdParser.confirmValue(
            vcdContents, 'a', 10, LogicValue.ofString('0x0x1z1z')),
        equals(true));

    deleteTemporaryDump(dumpName);
  });

  test('dump after max sim time works', () async {
    final a = SimpleClockGenerator(10).clk;
    final mod = SimpleModule(a);
    await mod.build();

    const dumpName = 'maxSimTime';

    createTemporaryDump(mod, dumpName);

    Simulator.setMaxSimTime(100);

    await Simulator.run();

    final vcdContents = File(temporaryDumpPath(dumpName)).readAsStringSync();

    expect(
      VcdParser.confirmValue(vcdContents, 'a', 99, LogicValue.one),
      equals(true),
    );

    deleteTemporaryDump(dumpName);
  });
}
