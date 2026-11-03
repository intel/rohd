// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_tool_policy_test.dart
// Tests SystemC required-tool and failure handling.
//
// 2026 October
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
import 'package:test/test.dart';

class _ToolPolicyModule extends Module {
  _ToolPolicyModule() : super(name: 'toolPolicyModule') {
    final dataIn = addInput('dataIn', Logic());
    addOutput('dataOut') <= dataIn;
  }
}

class _Unsigned64BoundaryModule extends Module {
  _Unsigned64BoundaryModule() : super(name: 'unsigned64Boundary') {
    final data = addInput('data', Logic(width: 64), width: 64);
    addOutput('dataOut', width: 64) <= data;
    addOutput('msb') <= data.getRange(63, 64);
  }
}

Future<_ToolPolicyModule> _buildModule() async {
  final module = _ToolPolicyModule();
  await module.build();
  return module;
}

void main() {
  tearDown(() async {
    await Simulator.reset();
  });
  tearDownAll(SimCompare.cleanupSystemCCache);

  test('shared vector defaults run ROHD, Icarus, and SystemC', () async {
    final module = await _buildModule();
    final report = await SimCompare.checkVectors(
      module,
      [
        Vector({'dataIn': 1}, {'dataOut': 1}),
      ],
      requireSystemC: true,
    );

    expect(report.results.keys, SimCompare.defaultVectorBackends);
    for (final result in report.results.values) {
      expect(result.status, SimCompareBackendStatus.passed);
    }
  });

  test('shared vector check distinguishes exclusions and tool skips', () async {
    final module = await _buildModule();
    final excluded = await SimCompare.checkVectors(
      module,
      [
        Vector({'dataIn': 0}, {'dataOut': 0}),
      ],
      backends: const {
        SimCompareBackend.rohd,
        SimCompareBackend.systemc,
      },
      excludedBackends: const {
        SimCompareBackend.systemc: 'Requires four-state behavior.',
      },
    );
    expect(
      excluded[SimCompareBackend.rohd]!.status,
      SimCompareBackendStatus.passed,
    );
    expect(
      excluded[SimCompareBackend.systemc]!.status,
      SimCompareBackendStatus.excluded,
    );

    final skipped = await SimCompare.checkVectors(
      module,
      const [],
      backends: const {SimCompareBackend.systemc},
      systemcHome: '/path/that/does/not/contain/systemc',
      systemcLib: '/path/that/does/not/contain/libsystemc',
      requireSystemC: false,
    );
    expect(
      skipped[SimCompareBackend.systemc]!.status,
      SimCompareBackendStatus.skipped,
    );
  });

  test('shared vector failures identify the backend', () async {
    final module = await _buildModule();

    await expectLater(
      SimCompare.checkVectors(
        module,
        [
          Vector({'dataIn': 1}, {'dataOut': 0}),
        ],
        backends: const {SimCompareBackend.rohd},
      ),
      throwsA(
        isA<TestFailure>().having(
          (error) => error.message,
          'message',
          contains('[rohd]'),
        ),
      ),
    );
  });

  test('optional SystemC absence reports a skip', () async {
    final module = await _buildModule();
    String? skipReason;

    final result = SimCompare.checkSystemCVector(
      module,
      const [],
      systemcHome: '/path/that/does/not/contain/systemc',
      systemcLib: '/path/that/does/not/contain/libsystemc',
      requireTool: false,
      onSkip: (reason) => skipReason = reason,
    );

    expect(result, isFalse);
    expect(skipReason, contains('SystemC headers and library were not found'));
  });

  test('required SystemC absence fails the check', () async {
    final module = await _buildModule();

    expect(
      () => SimCompare.checkSystemCVector(
        module,
        const [],
        systemcHome: '/path/that/does/not/contain/systemc',
        systemcLib: '/path/that/does/not/contain/libsystemc',
        requireTool: true,
        onSkip: (_) => fail('Required SystemC must not be skipped.'),
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  test('SystemC compilation failure fails the affected check', () async {
    final module = await _buildModule();
    final installation =
        Directory.systemTemp.createTempSync('rohd_fake_systemc_');
    final include = Directory('${installation.path}/include')..createSync();
    final lib = Directory('${installation.path}/lib')..createSync();
    File('${include.path}/systemc.h').writeAsStringSync('');
    File('${lib.path}/libsystemc.so').writeAsStringSync('');

    try {
      expect(
        () => SimCompare.checkSystemCVector(
          module,
          const [],
          systemcHome: include.path,
          systemcLib: lib.path,
          requireTool: true,
          cxxExecutable: Platform.resolvedExecutable,
          usePrecompiledHeader: false,
        ),
        throwsA(isA<TestFailure>()),
      );
    } finally {
      installation.deleteSync(recursive: true);
    }
  });

  test('SystemC execution failure after PASS fails the affected check',
      () async {
    final module = await _buildModule();
    final executable = SimCompare.buildSystemCVectorExecutable(
      module,
      requireTool: true,
    );
    expect(executable, isNotNull);
    final exe = executable!;
    final originalPath = '${exe.binaryPath}.passing';

    try {
      File(exe.binaryPath).renameSync(originalPath);
      File(exe.binaryPath).writeAsStringSync(
        '#!/bin/sh\n'
        '"$originalPath" "\$@"\n'
        'echo "teardown failed" >&2\n'
        'exit 42\n',
      );
      expect(
        Process.runSync('chmod', ['+x', exe.binaryPath]).exitCode,
        0,
      );

      expect(
        () => SimCompare.checkSystemCVectors(exe, const []),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Exit status: 42'),
              contains('PASS'),
              contains('teardown failed'),
            ),
          ),
        ),
      );
    } finally {
      exe.cleanup();
    }
  });

  test('SystemC vectors preserve unsigned 64-bit values', () async {
    final module = _Unsigned64BoundaryModule();
    await module.build();
    final executable = SimCompare.buildSystemCVectorExecutable(
      module,
      requireTool: true,
    );
    expect(executable, isNotNull);
    final exe = executable!;
    final highBit = BigInt.one << 63;
    final maxSigned = highBit - BigInt.one;

    try {
      expect(
        SimCompare.runSystemCVectors(exe, [
          Vector({'data': highBit}, {'dataOut': highBit, 'msb': 1}),
        ]),
        isTrue,
        reason: 'The high bit must reach the native SystemC model.',
      );
      expect(
        () => SimCompare.checkSystemCVectors(exe, [
          Vector({'data': maxSigned}, {'dataOut': highBit}),
        ]),
        throwsA(isA<TestFailure>()),
        reason: 'A wrong expected unsigned 64-bit output must not pass.',
      );
    } finally {
      exe.cleanup();
    }
  });

  test('SystemC vector checks reject four-state values', () async {
    final module = await _buildModule();
    final executable = SimCompare.buildSystemCVectorExecutable(
      module,
      requireTool: true,
    );
    expect(executable, isNotNull);
    final exe = executable!;

    try {
      expect(
        () => SimCompare.checkSystemCVectors(exe, [
          Vector(
            {'dataIn': LogicValue.x},
            {'dataOut': LogicValue.x},
          ),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Explicitly exclude SystemC with a reason'),
          ),
        ),
      );
    } finally {
      exe.cleanup();
    }
  });
}
