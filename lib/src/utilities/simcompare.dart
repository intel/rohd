/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// simcompare.dart
/// Helper functionality for unit testing (sv testbench generation, iverilog simulation, vectors, checking/comparison, etc.)
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:async';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class Vector {
  static const int period = 10;
  static const int offset = 2;
  final Map<String, dynamic> inputValues;
  final Map<String, dynamic> expectedOutputValues;
  Vector(this.inputValues, this.expectedOutputValues);

  @override
  String toString() {
    return '$inputValues => $expectedOutputValues';
  }

  String errorCheckString(
      String sigName, dynamic expected, String inputValues) {
    String expectedHexStr = expected is int
        ? '0x' + expected.toRadixString(16)
        : expected.toString();
    String expectedValStr = (expected is LogicValue && expected.width == 1)
        ? "'" + expected.toString(includeWidth: false)
        : expected.toString();

    if (expected is! int && expected is! LogicValue) {
      throw Exception(
          'Support for ${expected.runtimeType} is not supported (yet?).');
    }

    return 'if($sigName !== $expectedValStr) \$error(\$sformatf("Expected $sigName=$expectedHexStr, but found $sigName=0x%x with inputs $inputValues", $sigName));';
  }

  String toTbVerilog() {
    var assignments = inputValues.keys
        .map((signalName) => '$signalName = ${inputValues[signalName]};')
        .join('\n');
    var checks = expectedOutputValues.keys
        .map((signalName) => errorCheckString(signalName,
            expectedOutputValues[signalName], inputValues.toString()))
        .join('\n');
    var tbVerilog = [
      assignments,
      '#$offset',
      checks,
      '#${period - offset}',
    ].join('\n');
    return tbVerilog;
  }
}

class SimCompare {
  /// Runs a ROHD simulation where each of the [vectors] is executed per clock cycle
  /// sequentially.
  ///
  /// If [enableChecking] is set to false, then it will drive the simulation but not
  /// check that the outputs match.
  static Future<void> checkFunctionalVector(Module module, List<Vector> vectors,
      {bool enableChecking = true}) async {
    var timestamp = 1;
    for (var vector in vectors) {
      // print('Running vector: $vector');
      Simulator.registerAction(timestamp, () {
        for (var signalName in vector.inputValues.keys) {
          var value = vector.inputValues[signalName];
          module.input(signalName).put(value);
        }

        if (enableChecking) {
          Simulator.postTick.first.then((value) {
            for (var signalName in vector.expectedOutputValues.keys) {
              var value = vector.expectedOutputValues[signalName];
              var o = module.output(signalName);
              var errorReason =
                  'For vector #${vectors.indexOf(vector)} $vector, expected $o to be $value, but it was ${o.value}.';
              if (value is int) {
                if (!o.value.isValid) {
                  // invalid value causes exception without helpful message, so throw it
                  throw Exception(errorReason);
                }
                expect(o.value.toInt(), equals(value), reason: errorReason);
              } else if (value is LogicValue) {
                if (o.width > 1 &&
                    (value == LogicValue.x || value == LogicValue.z)) {
                  for (var oBit in o.value.toList()) {
                    expect(oBit, equals(value), reason: errorReason);
                  }
                } else {
                  expect(o.value, equals(value));
                }
              } else {
                throw Exception(
                    'Value type ${value.runtimeType} is not supported (yet?)');
              }
            }
          });
        }
      });
      timestamp += Vector.period;
    }
    Simulator.registerAction(timestamp + Vector.period,
        () {}); // just so it does one more thing at the end
    Simulator.setMaxSimTime(timestamp + 2 * Vector.period);
    await Simulator.run();
  }

  static bool iverilogVector(
    String generatedVerilog,
    String topModule,
    List<Vector> vectors, {
    bool dontDeleteTmpFiles = false,
    bool dumpWaves = false,
    Map<String, int> signalToWidthMap = const {},
    List<String> iverilogExtraArgs = const [],
    bool allowWarnings = false,
  }) {
    String signalDeclaration(String signalName) {
      if (signalToWidthMap.containsKey(signalName)) {
        var width = signalToWidthMap[signalName]!;
        return '[${width - 1}:0] $signalName';
      } else {
        return signalName;
      }
    }

    var allSignals = vectors
        .map((e) => [...e.inputValues.keys, ...e.expectedOutputValues.keys])
        .reduce((a, b) => [...a, ...b])
        .toSet();
    var localDeclarations =
        allSignals.map((e) => 'logic ' + signalDeclaration(e) + ';').join('\n');
    var moduleConnections = allSignals.map((e) => '.$e($e)').join(', ');
    var moduleInstance = '$topModule dut($moduleConnections);';
    var stimulus = vectors.map((e) => e.toTbVerilog()).join('\n');

    var uniqueId = (generatedVerilog +
            localDeclarations +
            stimulus +
            moduleInstance)
        .hashCode; // so that when they run in parallel, they dont step on each other
    var dir = 'tmp_test';
    var tmpTestFile = '$dir/tmp_test$uniqueId.sv';
    var tmpOutput = '$dir/tmp_out$uniqueId';
    var tmpVcdFile = '$dir/tmp_waves_$uniqueId.vcd';

    var waveDumpCode = '''
\$dumpfile("$tmpVcdFile");
\$dumpvars(0,dut);
''';

    var testbench = [
      generatedVerilog,
      'module tb;',
      localDeclarations,
      moduleInstance,
      'initial begin',
      if (dumpWaves) waveDumpCode,
      '#1',
      stimulus,
      '\$finish;', // so the test doesn't run forever if there's a clock generator
      'end',
      'endmodule',
    ].join('\n');

    Directory(dir).createSync(recursive: true);
    File(tmpTestFile).writeAsStringSync(testbench);
    var compileResult = Process.runSync('iverilog',
        ['-g2012', tmpTestFile, '-o', tmpOutput] + iverilogExtraArgs);
    bool printIfContentsAndCheckError(dynamic output) {
      if (output.toString().isNotEmpty) print(output);
      return output.toString().contains(RegExp(
          [
            'error',
            'unable',
            if (!allowWarnings) 'warning',
          ].join('|'),
          caseSensitive: false));
    }

    if (printIfContentsAndCheckError(compileResult.stdout)) return false;
    if (printIfContentsAndCheckError(compileResult.stderr)) return false;
    var simResult = Process.runSync('vvp', [tmpOutput]);
    if (printIfContentsAndCheckError(simResult.stdout)) return false;
    if (printIfContentsAndCheckError(simResult.stderr)) return false;
    if (!dontDeleteTmpFiles) {
      try {
        File(tmpOutput).deleteSync();
        File(tmpTestFile).deleteSync();
        if (dumpWaves) File(tmpVcdFile).deleteSync();
      } catch (e) {
        print("Couldn't delete: $e");
        return false;
      }
    }
    return true;
  }
}
