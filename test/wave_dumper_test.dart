/// Copyright (C) 2021 Intel Corporation
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

/// State of VCD parsing for [confirmValue].
enum VCDParseState { findSig, findDumpVars, findValue }

/// Checks that the contents of a VCD file ([vcdContents]) have [value] on
/// [signalName] at time [timestamp].
///
/// This function is basic and only works on flat, single modules, or at least
/// cases where only one signal is named [signalName] across all scopes.
bool confirmValue(
    String vcdContents, String signalName, int timestamp, LogicValue value) {
  final lines = vcdContents.split('\n');

  String? sigName;
  int? width;
  var currentTime = 0;
  LogicValue? currentValue;

  var state = VCDParseState.findSig;

  final sigNameRegexp = RegExp(r'\s*\$var\swire\s(\d+)\s(\S*)\s(\S*)\s\$end');
  for (final line in lines) {
    if (state == VCDParseState.findSig) {
      if (sigNameRegexp.hasMatch(line)) {
        final match = sigNameRegexp.firstMatch(line)!;
        final w = int.parse(match.group(1)!);
        final sName = match.group(2)!;
        final lName = match.group(3)!;

        if (lName == signalName) {
          sigName = sName;
          width = w;
          state = VCDParseState.findDumpVars;
        }
      }
    } else if (state == VCDParseState.findDumpVars) {
      if (line.contains(r'$dumpvars')) {
        state = VCDParseState.findValue;
      }
    } else if (state == VCDParseState.findValue) {
      if (line.startsWith('#')) {
        currentTime = int.parse(line.substring(1));
        if (currentTime > timestamp) {
          return currentValue == value;
        }
      } else if (line.endsWith(sigName!)) {
        if (width == 1) {
          // ex: zs1
          currentValue = LogicValue.ofString(line[0]);
        } else {
          // ex: bzzzzzzzz s2
          currentValue = LogicValue.ofString(line.split(' ')[0].substring(1));
        }
      }
    }
  }
  return currentValue == value;
}

void main() {
  tearDown(Simulator.reset);

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

    expect(confirmValue(vcdContents, 'a', 0, LogicValue.ofString('1')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 5, LogicValue.ofString('1')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
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

    expect(confirmValue(vcdContents, 'a', 0, LogicValue.ofString('1')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 1, LogicValue.ofString('1')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 20, LogicValue.ofString('1')),
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

    expect(confirmValue(vcdContents, 'a', 0, LogicValue.ofString('0')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 5, LogicValue.ofString('1')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 35, LogicValue.ofString('0')),
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

    expect(confirmValue(vcdContents, 'a', 0, LogicValue.ofInt(0x5a, 8)),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 10, LogicValue.ofInt(0xa5, 8)),
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

    expect(confirmValue(vcdContents, 'a', 0, LogicValue.ofString('01xzzx10')),
        equals(true));
    expect(confirmValue(vcdContents, 'a', 10, LogicValue.ofString('0x0x1z1z')),
        equals(true));

    deleteTemporaryDump(dumpName);
  });
}
