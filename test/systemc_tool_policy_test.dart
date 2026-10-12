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

Future<_ToolPolicyModule> _buildModule() async {
  final module = _ToolPolicyModule();
  await module.build();
  return module;
}

void main() {
  tearDownAll(SimCompare.cleanupSystemCCache);

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
}
