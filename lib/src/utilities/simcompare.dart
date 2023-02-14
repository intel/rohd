/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// simcompare.dart
/// Helper functionality for unit testing (sv testbench generation, iverilog simulation, vectors, checking/comparison, etc.)
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/exceptions.dart';
import 'package:test/test.dart';

/// Represents a single test case to check in a single clock cycle.
///
/// Useful for testing equivalent behavior in different simulation environments.
class Vector {
  /// The period of the clock used for each vector
  static const int _period = 10;

  /// The offset from the clock edge to perform checks.
  static const int _offset = 2;

  /// A map of input names in a [Module] to associated values to drive
  /// in this vector.
  final Map<String, dynamic> inputValues;

  /// A map of output names in a [Module] to associated values to expect
  /// on those outputs for this vector.
  final Map<String, dynamic> expectedOutputValues;

  /// A single vector to test in a simulation with provided inputs and
  /// expected outputs.
  Vector(this.inputValues, this.expectedOutputValues);

  @override
  String toString() => '$inputValues => $expectedOutputValues';

  /// Computes a SystemVerilog code string that checks in a SystemVerilog
  /// simulation whether a signal [sigName] has the [expected] value given
  /// the [inputValues].
  String _errorCheckString(
      String sigName, dynamic expected, String inputValues) {
    final expectedHexStr = expected is int
        ? '0x${expected.toRadixString(16)}'
        : expected.toString();
    final expectedValStr = (expected is LogicValue && expected.width == 1)
        ? "'${expected.toString(includeWidth: false)}"
        : expected.toString();

    if (expected is! int && expected is! LogicValue) {
      throw Exception(
          'Support for ${expected.runtimeType} is not supported (yet?).');
    }

    return 'if($sigName !== $expectedValStr) '
        '\$error(\$sformatf("Expected $sigName=$expectedHexStr,'
        ' but found $sigName=0x%x with inputs $inputValues", $sigName));';
  }

  /// Converts this vector into a SystemVerilog check.
  String toTbVerilog() {
    final assignments = inputValues.keys
        .map((signalName) => '$signalName = ${inputValues[signalName]};')
        .join('\n');
    final checks = expectedOutputValues.keys
        .map((signalName) => _errorCheckString(signalName,
            expectedOutputValues[signalName], inputValues.toString()))
        .join('\n');
    final tbVerilog = [
      assignments,
      '#$_offset',
      checks,
      '#${_period - _offset}',
    ].join('\n');
    return tbVerilog;
  }
}

/// A utility class for checking a collection of [Vector]s against
/// different simulators.
abstract class SimCompare {
  /// Runs a ROHD simulation where each of the [vectors] is executed per
  /// clock cycle sequentially.
  ///
  /// If [enableChecking] is set to false, then it will drive the simulation
  /// but not check that the outputs match.
  static Future<void> checkFunctionalVector(Module module, List<Vector> vectors,
      {bool enableChecking = true}) async {
    var timestamp = 1;
    for (final vector in vectors) {
      // print('Running vector: $vector');
      Simulator.registerAction(timestamp, () {
        for (final signalName in vector.inputValues.keys) {
          final value = vector.inputValues[signalName];
          // ignore: invalid_use_of_protected_member
          module.input(signalName).put(value);
        }

        if (enableChecking) {
          Simulator.postTick.first.then((value) {
            for (final signalName in vector.expectedOutputValues.keys) {
              final value = vector.expectedOutputValues[signalName];
              final o = module.output(signalName);

              final errorReason =
                  'For vector #${vectors.indexOf(vector)} $vector,'
                  ' expected $o to be $value, but it was ${o.value}.';
              if (value is int) {
                expect(o.value.isValid, isTrue, reason: errorReason);
                expect(o.value.toInt(), equals(value), reason: errorReason);
              } else if (value is LogicValue) {
                if (o.width > 1 &&
                    (value == LogicValue.x || value == LogicValue.z)) {
                  for (final oBit in o.value.toList()) {
                    expect(oBit, equals(value), reason: errorReason);
                  }
                } else {
                  expect(o.value, equals(value));
                }
              } else {
                throw NonSupportedTypeException(value.runtimeType.toString());
              }
            }
          }).catchError(
            test: (error) => error is Exception,
            // ignore: avoid_types_on_closure_parameters
            (Object err, StackTrace stackTrace) {
              Simulator.throwException(err as Exception, stackTrace);
            },
          );
        }
      });
      timestamp += Vector._period;
    }
    Simulator.registerAction(timestamp + Vector._period,
        () {}); // just so it does one more thing at the end
    Simulator.setMaxSimTime(timestamp + 2 * Vector._period);
    await Simulator.run();
  }

  /// Executes [vectors] against the Icarus Verilog simulator.
  static bool iverilogVector(
    Module module,
    List<Vector> vectors, {
    String? moduleName,
    bool dontDeleteTmpFiles = false,
    bool dumpWaves = false,
    List<String> iverilogExtraArgs = const [],
    bool allowWarnings = false,
  }) {
    String signalDeclaration(String signalName) {
      final signal = module.signals.firstWhere((e) => e.name == signalName);
      if (signal.width != 1) {
        return '[${signal.width - 1}:0] $signalName';
      } else {
        return signalName;
      }
    }

    final topModule = moduleName ?? module.definitionName;
    final allSignals = <String>{
      for (final e in vectors) ...e.inputValues.keys,
      for (final e in vectors) ...e.expectedOutputValues.keys,
    };
    final localDeclarations =
        allSignals.map((e) => 'logic ${signalDeclaration(e)};').join('\n');
    final moduleConnections = allSignals.map((e) => '.$e($e)').join(', ');
    final moduleInstance = '$topModule dut($moduleConnections);';
    final stimulus = vectors.map((e) => e.toTbVerilog()).join('\n');
    final generatedVerilog = module.generateSynth();

    // so that when they run in parallel, they dont step on each other
    final uniqueId =
        (generatedVerilog + localDeclarations + stimulus + moduleInstance)
            .hashCode;

    const dir = 'tmp_test';
    final tmpTestFile = '$dir/tmp_test$uniqueId.sv';
    final tmpOutput = '$dir/tmp_out$uniqueId';
    final tmpVcdFile = '$dir/tmp_waves_$uniqueId.vcd';

    final waveDumpCode = '''
\$dumpfile("$tmpVcdFile");
\$dumpvars(0,dut);
''';

    final testbench = [
      generatedVerilog,
      'module tb;',
      localDeclarations,
      moduleInstance,
      'initial begin',
      if (dumpWaves) waveDumpCode,
      '#1',
      stimulus,
      r'$finish;', // so the test doesn't run forever if there's a clock gen
      'end',
      'endmodule',
    ].join('\n');

    Directory(dir).createSync(recursive: true);
    File(tmpTestFile).writeAsStringSync(testbench);
    final compileResult = Process.runSync('iverilog',
        ['-g2012', '-o', tmpOutput, ...iverilogExtraArgs, tmpTestFile]);
    bool printIfContentsAndCheckError(dynamic output) {
      if (output.toString().isNotEmpty) {
        print(output);
      }
      return output.toString().contains(RegExp(
          [
            'error',
            'unable',
            if (!allowWarnings) 'warning',
          ].join('|'),
          caseSensitive: false));
    }

    if (printIfContentsAndCheckError(compileResult.stdout)) {
      return false;
    }
    if (printIfContentsAndCheckError(compileResult.stderr)) {
      return false;
    }

    final simResult = Process.runSync('vvp', [tmpOutput]);
    if (printIfContentsAndCheckError(simResult.stdout)) {
      return false;
    }
    if (printIfContentsAndCheckError(simResult.stderr)) {
      return false;
    }

    if (!dontDeleteTmpFiles) {
      try {
        File(tmpOutput).deleteSync();
        File(tmpTestFile).deleteSync();
        if (dumpWaves) {
          File(tmpVcdFile).deleteSync();
        }
      } on Exception catch (e) {
        print("Couldn't delete: $e");
        return false;
      }
    }
    return true;
  }
}
