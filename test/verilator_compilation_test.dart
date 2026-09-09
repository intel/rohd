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

void main() {
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
    SimCompare.checkVerilatorCompilation(module);
  });

  test('Verilator rejects a scalar connected to an unpacked array', () async {
    final valid = ArrayConnectionFixture("{2'h0}");
    await valid.build();
    if (!SimCompare.checkVerilatorCompilation(valid)) {
      return;
    }

    final invalid = ArrayConnectionFixture("2'h0");
    await invalid.build();
    expect(
      () => SimCompare.checkVerilatorCompilation(invalid, requireTool: false),
      throwsA(isA<TestFailure>().having((error) => error.message, 'diagnostic',
          contains('Verilator compilation failed'))),
    );
  });

  test('missing optional Verilator explicitly skips', () {
    expect(
        SimCompare.checkVerilatorCompilation(ArrayConnectionFixture("{2'h0}"),
            verilatorExecutable: '/rohd/nonexistent/verilator',
            requireTool: false),
        isFalse);
  });

  test('missing required Verilator fails', () {
    expect(
      () => SimCompare.checkVerilatorCompilation(
          ArrayConnectionFixture("{2'h0}"),
          verilatorExecutable: '/rohd/nonexistent/verilator',
          requireTool: true),
      throwsA(isA<TestFailure>().having(
          (error) => error.message, 'diagnostic', contains('not found'))),
    );
  }, testOn: 'vm');

  test('missing Verilator follows the environment policy', () {
    bool check() =>
        SimCompare.checkVerilatorCompilation(ArrayConnectionFixture("{2'h0}"),
            verilatorExecutable: '/rohd/nonexistent/verilator');
    if (Platform.environment['ROHD_REQUIRE_VERILATOR'] == '1') {
      expect(check, throwsA(isA<TestFailure>()));
    } else {
      expect(check(), isFalse);
    }
  }, testOn: 'vm');

  test('a broken version command is not treated as a missing tool', () {
    final executable = fakeExecutable('exit 7');
    expect(
        () => SimCompare.checkVerilatorCompilation(
            ArrayConnectionFixture("{2'h0}"),
            verilatorExecutable: executable.path,
            requireTool: false),
        throwsA(isA<TestFailure>().having((error) => error.message,
            'diagnostic', contains('Could not run'))));
  }, testOn: 'vm && (linux || mac-os)');

  test('permission errors are not treated as a missing tool', () {
    final executable = fakeExecutable('exit 0', executable: false);
    expect(
        () => SimCompare.checkVerilatorCompilation(
            ArrayConnectionFixture("{2'h0}"),
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
      SimCompare.checkVerilatorCompilation(module,
          verilatorExecutable: executable.path, requireTool: false);
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
        () => SimCompare.checkVerilatorCompilation(
            ArrayConnectionFixture("{2'h0}"),
            verilatorExecutable: executable.path,
            requireTool: false),
        throwsA(isA<ProcessException>()));
  }, testOn: 'vm && (linux || mac-os)');

  test('extra arguments select the warning policy and top module', () async {
    final module = ArrayConnectionFixture("{2'h0}");
    await module.build();
    if (!SimCompare.checkVerilatorCompilation(module,
        verilatorExtraArgs: ['-Wall'])) {
      return;
    }
    expect(
        () => SimCompare.checkVerilatorCompilation(module,
            verilatorExtraArgs: ['-Wall', '-Werror-DECLFILENAME']),
        throwsA(isA<TestFailure>()));
    SimCompare.checkVerilatorCompilation(module, moduleName: 'ArrayConsumer');
    expect(
        () => SimCompare.checkVerilatorCompilation(module,
            moduleName: 'MissingTop', requireTool: false),
        throwsA(isA<TestFailure>()));
  });

  test('retained files use unique directories', () async {
    final module = ArrayConnectionFixture("{2'h0}");
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
    for (var iteration = 0; iteration < 2; iteration++) {
      if (!capture.run(() => SimCompare.checkVerilatorCompilation(module,
          dontDeleteTmpFiles: true))) {
        return;
      }
    }
    expect(directories.toSet(), hasLength(2));
    for (final path in directories) {
      expect(File('$path/design.sv').readAsStringSync(),
          contains('ArrayConsumer'));
    }
  }, testOn: 'vm');
}
