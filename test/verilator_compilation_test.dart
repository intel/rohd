// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// verilator_compilation_test.dart
// Tests for Verilator compilation checks and tool availability.
//
// 2026 September 9
// Author: Max Korbel <max.korbel@intel.com>

@Tags(['verilator'])
library;

import 'dart:async';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class ArrayConnectionFixture extends Module with SystemVerilog {
  final String connection;

  ArrayConnectionFixture(this.connection)
      : super(definitionName: 'ArrayConnectionFixture');

  @override
  String definitionVerilog(String definitionType) => '''
module ArrayConsumer(input logic [1:0] a [0:0], output logic [1:0] observed);
assign observed = a[0];
endmodule
module $definitionType(output logic [1:0] observed);
ArrayConsumer child(.a($connection), .observed(observed));
endmodule
''';
}

class VectorArrayFixture extends Module {
  VectorArrayFixture() {
    final array = addInputArray(
        'array', LogicArray([3], 4, numUnpackedDimensions: 1),
        dimensions: [3], elementWidth: 4, numUnpackedDimensions: 1);
    addOutputArray('observed',
            dimensions: [3], elementWidth: 4, numUnpackedDimensions: 1) <=
        array;
  }
}

class EarlyFinishFixture extends Module with SystemVerilog {
  @override
  String definitionVerilog(String definitionType) => '''
module $definitionType();
initial \$finish;
endmodule
''';
}

void main() {
  for (final value in [LogicValue.x, LogicValue.z, '10xz00000000']) {
    for (final isInput in [true, false]) {
      test(
          'Verilator rejects four-state ${isInput ? 'input' : 'output'} $value',
          () async {
        final module = VectorArrayFixture();
        await module.build();
        expect(
            () => SimCompare.checkVerilatorVector(module, [
                  Vector({'array': isInput ? value : 0},
                      {'observed': isInput ? 0 : value}),
                ]),
            throwsA(isA<ArgumentError>().having((error) => error.message,
                'diagnostic', contains('requires two-state vectors'))));
      }, testOn: 'vm');
    }
  }

  test('buildOnly permits four-state vectors', () async {
    final module = VectorArrayFixture();
    await module.build();
    SimCompare.checkVerilatorVector(
        module,
        [
          Vector({'array': LogicValue.x}, {'observed': LogicValue.x}),
        ],
        buildOnly: true);
  });

  test('simulation cannot pass by exiting before its checks', () async {
    final module = EarlyFinishFixture();
    await module.build();
    if (!SimCompare.checkVerilatorVector(module, const [], buildOnly: true)) {
      return;
    }
    expect(
        () => SimCompare.checkVerilatorVector(module, const []),
        throwsA(isA<TestFailure>().having((error) => error.message,
            'diagnostic', contains('before completing the vectors'))));
  });

  test('Verilator simulates unpacked-array vectors', () async {
    final module = VectorArrayFixture();
    await module.build();
    SimCompare.checkVerilatorVector(module, [
      Vector({'array': 0x123}, {'observed': 0x123}),
      Vector({'array': 0xabc}, {'observed': 0xabc}),
      Vector({'array': 0}, {'observed': 0}),
    ]);
  });

  test('buildOnly checks syntax without executing failing vectors', () async {
    final module = VectorArrayFixture();
    await module.build();
    SimCompare.checkVerilatorVector(
        module,
        [
          Vector({'array': 0x123}, {'observed': 0x321}),
        ],
        buildOnly: true);
  });

  test('Verilator simulation rejects incorrect expected values', () async {
    final module = VectorArrayFixture();
    await module.build();
    if (!SimCompare.checkVerilatorVector(module, const [], buildOnly: true)) {
      return;
    }
    TestFailure? failure;
    try {
      SimCompare.checkVerilatorVector(module, [
        Vector({'array': 0xabc}, {'observed': 0xabc}),
        Vector({'array': 0x123}, {'observed': 0x321}),
      ]);
    } on TestFailure catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    final message = failure!.message!;
    expect(message, contains('Verilator simulation failed'));
    expect(message, contains('Expected observed[0]'));
    final directory =
        RegExp(r'Command: (\S+)/obj_dir/rohd_sim').firstMatch(message)![1]!;
    expect(Directory(directory).existsSync(), isFalse);
  });

  File fakeExecutable(String body,
      {bool executable = true, String interpreter = '/bin/sh'}) {
    final directory = Directory.systemTemp.createTempSync('rohd_verilator_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/verilator')
      ..writeAsStringSync('#!$interpreter\n$body\n');
    if (executable) {
      expect(Process.runSync('chmod', ['+x', file.path]).exitCode, 0);
    }
    return file;
  }

  test('Verilator accepts an unpacked array concatenation', () async {
    final module = ArrayConnectionFixture("{2'h0}");
    await module.build();
    SimCompare.checkVerilatorVector(module, const [], buildOnly: true);
  });

  test('Verilator rejects a scalar connected to an unpacked array', () async {
    final valid = ArrayConnectionFixture("{2'h0}");
    await valid.build();
    if (!SimCompare.checkVerilatorVector(valid, const [], buildOnly: true)) {
      return;
    }

    final invalid = ArrayConnectionFixture("2'h0");
    await invalid.build();
    expect(
      () => SimCompare.checkVerilatorVector(invalid, const [],
          buildOnly: true, requireTool: false),
      throwsA(isA<TestFailure>().having((error) => error.message, 'diagnostic',
          contains('Verilator compilation failed'))),
    );
  });

  test('missing optional Verilator explicitly skips', () {
    expect(
        SimCompare.checkVerilatorVector(
            ArrayConnectionFixture("{2'h0}"), const [],
            buildOnly: true,
            verilatorExecutable: '/rohd/nonexistent/verilator',
            requireTool: false),
        isFalse);
  });

  test('missing required Verilator fails', () {
    expect(
      () => SimCompare.checkVerilatorVector(
          ArrayConnectionFixture("{2'h0}"), const [],
          buildOnly: true,
          verilatorExecutable: '/rohd/nonexistent/verilator',
          requireTool: true),
      throwsA(isA<TestFailure>().having(
          (error) => error.message, 'diagnostic', contains('not found'))),
    );
  }, testOn: 'vm');

  test('missing Verilator follows the environment policy', () {
    bool check() => SimCompare.checkVerilatorVector(
        ArrayConnectionFixture("{2'h0}"), const [],
        buildOnly: true, verilatorExecutable: '/rohd/nonexistent/verilator');
    if (Platform.environment['ROHD_REQUIRE_VERILATOR'] == '1') {
      expect(check, throwsA(isA<TestFailure>()));
    } else {
      expect(check(), isFalse);
    }
  }, testOn: 'vm');

  test('a broken version command is not treated as a missing tool', () {
    final executable = fakeExecutable('exit 7');
    expect(
        () => SimCompare.checkVerilatorVector(
            ArrayConnectionFixture("{2'h0}"), const [],
            buildOnly: true,
            verilatorExecutable: executable.path,
            requireTool: false),
        throwsA(isA<TestFailure>().having((error) => error.message,
            'diagnostic', contains('Could not run'))));
  }, testOn: 'vm && (linux || mac-os)');

  test('permission errors are not treated as a missing tool', () {
    final executable = fakeExecutable('exit 0', executable: false);
    expect(
        () => SimCompare.checkVerilatorVector(
            ArrayConnectionFixture("{2'h0}"), const [],
            buildOnly: true,
            verilatorExecutable: executable.path,
            requireTool: false),
        throwsA(isA<ProcessException>()));
  }, testOn: 'vm && (linux || mac-os)');

  test('nonzero exit with no diagnostics fails and cleans temporary files',
      () async {
    final executable = fakeExecutable(r'''
  case "$1" in
  --version) exit 0 ;;
  *) exit 7 ;;
esac
''');
    final module = ArrayConnectionFixture("{2'h0}");
    await module.build();
    TestFailure? failure;
    try {
      SimCompare.checkVerilatorVector(module, const [],
          buildOnly: true,
          verilatorExecutable: executable.path,
          requireTool: false);
    } on TestFailure catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    final message = failure!.message!;
    expect(message, contains('Verilator compilation failed'));
    final directory = RegExp(r'--Mdir (\S+)/obj_dir').firstMatch(message)![1]!;
    expect(Directory(directory).existsSync(), isFalse);
  }, testOn: 'vm && (linux || mac-os)');

  test('a missing interpreter is not treated as a missing executable', () {
    final executable =
        fakeExecutable('exit 0', interpreter: '/rohd/nonexistent/interpreter');
    expect(
        () => SimCompare.checkVerilatorVector(
            ArrayConnectionFixture("{2'h0}"), const [],
            buildOnly: true,
            verilatorExecutable: executable.path,
            requireTool: false),
        throwsA(isA<ProcessException>()));
  }, testOn: 'vm && (linux || mac-os)');

  test('extra arguments select the warning policy and top module', () async {
    final module = ArrayConnectionFixture("{2'h0}");
    await module.build();
    if (!SimCompare.checkVerilatorVector(module, const [],
        buildOnly: true, verilatorExtraArgs: ['-Wall'])) {
      return;
    }
    expect(
        () => SimCompare.checkVerilatorVector(module, const [],
            buildOnly: true,
            verilatorExtraArgs: ['-Wall', '-Werror-DECLFILENAME']),
        throwsA(isA<TestFailure>()));
    SimCompare.checkVerilatorVector(module, const [],
        buildOnly: true, moduleName: 'ArrayConsumer');
    expect(
        () => SimCompare.checkVerilatorVector(module, const [],
            buildOnly: true, moduleName: 'MissingTop', requireTool: false),
        throwsA(isA<TestFailure>()));
  });

  test('retained files use unique directories and include simulation waves',
      () async {
    final module = VectorArrayFixture();
    await module.build();
    final directories = <String>[];
    addTearDown(() {
      for (final path in directories) {
        Directory(path).deleteSync(recursive: true);
      }
    });
    final capture = Zone.current.fork(specification: ZoneSpecification(
      print: (self, parent, zone, message) {
        const prefix = 'Verilator files retained in ';
        if (message.startsWith(prefix)) {
          directories.add(message.substring(prefix.length));
        } else {
          parent.print(zone, message);
        }
      },
    ));
    for (final buildOnly in [true, false]) {
      if (!capture.run(() => SimCompare.checkVerilatorVector(
          module,
          [
            Vector({'array': 0x123}, {'observed': 0x123}),
            Vector({'array': 0xabc}, {'observed': 0xabc}),
          ],
          buildOnly: buildOnly,
          dumpWaves: true,
          dontDeleteTmpFiles: true,
          moduleName: module.definitionName,
          synthesizerConfiguration: const SystemVerilogSynthesizerConfiguration(
              inputPortType: SystemVerilogPortTypeConfiguration())))) {
        return;
      }
    }
    expect(directories.toSet(), hasLength(2));
    for (final path in directories) {
      expect(File('$path/design.sv').readAsStringSync(),
          contains('VectorArrayFixture'));
    }
    expect(File('${directories.first}/obj_dir/rohd_sim').existsSync(), isFalse);
    expect(File('${directories.last}/obj_dir/rohd_sim').existsSync(), isTrue);
    final waves = File('${directories.last}/waves.vcd').readAsStringSync();
    expect(waves, contains(r'$enddefinitions'));
    expect(waves, contains('observed'));
    expect(waves, contains('#11'));
  }, testOn: 'vm');
}
