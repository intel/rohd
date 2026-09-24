// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sv_param_naming_test.dart
// Unit tests for SystemVerilog parameter names sharing the module namespace
//
// 2026 September 21
// Author: Shubham Padkonde <shubhampadkonde12@gmail.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

/// A module with one definition parameter and one internal signal, so a
/// parameter name can be made to collide with a port, an internal signal, or
/// nothing at all.
class ParameterizedMod extends Module with SystemVerilog {
  @override
  final List<SystemVerilogParameterDefinition> definitionParameters;

  ParameterizedMod(
    Logic a,
    String parameterName, {
    Naming internalNaming = Naming.renameable,
    super.name = 'parameterized_mod',
  }) : definitionParameters = [
          SystemVerilogParameterDefinition(parameterName,
              type: 'int', defaultValue: '3'),
        ] {
    a = addInput('a', a, width: 8);

    final internal =
        Logic(name: 'myInternal', width: 8, naming: internalNaming);
    internal <= a;

    addOutput('b', width: 8) <= internal;
  }

  @override
  String? definitionVerilog(String definitionType) => null;
}

Future<String> synthOf(ParameterizedMod mod) async {
  await mod.build();
  return mod.generateSynth();
}

void main() {
  group('a definition parameter cannot take a name that cannot move', () {
    for (final portName in ['a', 'b']) {
      test('such as the port $portName', () {
        expect(
            () async =>
                synthOf(ParameterizedMod(Logic(width: 8), portName)),
            throwsA(isA<UnavailableReservedNameException>()));
      });
    }

    test('such as a reserved internal signal', () {
      expect(
          () async => synthOf(ParameterizedMod(Logic(width: 8), 'myInternal',
              internalNaming: Naming.reserved)),
          throwsA(isA<UnavailableReservedNameException>()));
    });
  });

  test('a renameable signal is moved out of a parameter name', () async {
    final sv = await synthOf(ParameterizedMod(Logic(width: 8), 'myInternal'));

    expect(sv, contains('parameter int myInternal = 3'));

    // The signal must no longer be declared as plain `myInternal`, or the
    // module would declare that identifier twice.
    expect(sv, isNot(contains('logic [7:0] myInternal;')));
    expect(sv, contains('myInternal_0'));
  });

  test('a parameter that collides with nothing is left alone', () async {
    final sv = await synthOf(ParameterizedMod(Logic(width: 8), 'WIDTH'));

    expect(sv, contains('parameter int WIDTH = 3'));
    expect(sv, contains('logic [7:0] myInternal;'));
  });
}
