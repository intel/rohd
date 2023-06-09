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

import 'package:collection/collection.dart';
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
  static String _errorCheckString(String sigName, dynamic expected,
      LogicValue expectedVal, String inputValues) {
    final expectedHexStr = expected is int
        ? '0x${expected.toRadixString(16)}'
        : expected.toString();
    final expectedValStr = expectedVal.toString();

    if (expected is! int && expected is! LogicValue) {
      throw Exception(
          'Support for ${expected.runtimeType} is not supported (yet?).');
    }

    return 'if($sigName !== $expectedValStr) '
        '\$error(\$sformatf("Expected $sigName=$expectedHexStr,'
        ' but found $sigName=0x%x with inputs $inputValues", $sigName));';
  }

  /// Converts this vector into a SystemVerilog check.
  String toTbVerilog(Module module) {
    final assignments = inputValues.keys.map((signalName) {
      // ignore: invalid_use_of_protected_member
      final signal = module.input(signalName);

      if (signal is LogicArray) {
        final arrAssigns = StringBuffer();
        var index = 0;
        final fullVal =
            LogicValue.of(inputValues[signalName], width: signal.width);
        for (final leaf in signal.leafElements) {
          final subVal = fullVal.getRange(index, index + leaf.width);
          arrAssigns.writeln('${leaf.structureName} = $subVal;');
          index += leaf.width;
        }
        return arrAssigns.toString();
      } else {
        return '$signalName = ${inputValues[signalName]};';
      }
    }).join('\n');

    final checksList = <String>[];
    for (final expectedOutput in expectedOutputValues.entries) {
      final outputName = expectedOutput.key;
      final outputPort = module.output(outputName);
      final expected = expectedOutput.value;
      final expectedValue = LogicValue.of(
        expected,
        width: outputPort.width,
      );
      final inputStimulus = inputValues.toString();

      if (outputPort is LogicArray) {
        var index = 0;
        for (final leaf in outputPort.leafElements) {
          final subVal = expectedValue.getRange(index, index + leaf.width);
          checksList.add(_errorCheckString(
              leaf.structureName, subVal, subVal, inputStimulus));
          index += leaf.width;
        }
      } else {
        checksList.add(_errorCheckString(
            outputName, expected, expectedValue, inputStimulus));
      }
    }
    final checks = checksList.join('\n');

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
                  expect(o.value, equals(value), reason: errorReason);
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

  /// A collection of warnings that are fine to ignore usually.
  static final List<RegExp> _knownWarnings = [
    RegExp('sorry: Case unique/unique0 qualities are ignored.'),
    RegExp(r'sorry: constant selects in always_\* processes'
        ' are not currently supported'),
    RegExp('warning: always_comb process has no sensitivities'),
  ];

  /// Executes [vectors] against the Icarus Verilog simulator and checks
  /// that it passes.
  static void checkIverilogVector(
    Module module,
    List<Vector> vectors, {
    String? moduleName,
    bool dontDeleteTmpFiles = false,
    bool dumpWaves = false,
    List<String> iverilogExtraArgs = const [],
    bool allowWarnings = false,
    bool maskKnownWarnings = true,
    bool enableChecking = true,
    bool buildOnly = false,
  }) {
    final result = iverilogVector(module, vectors,
        moduleName: moduleName,
        dontDeleteTmpFiles: dontDeleteTmpFiles,
        dumpWaves: dumpWaves,
        iverilogExtraArgs: iverilogExtraArgs,
        allowWarnings: allowWarnings,
        maskKnownWarnings: maskKnownWarnings,
        buildOnly: buildOnly);
    if (enableChecking) {
      expect(result, true);
    }
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
    bool maskKnownWarnings = true,
    bool buildOnly = false,
  }) {
    String signalDeclaration(String signalName) {
      final signal = module.signals.firstWhere((e) => e.name == signalName);

      if (signal is LogicArray) {
        final unpackedDims =
            signal.dimensions.getRange(0, signal.numUnpackedDimensions);
        final packedDims = signal.dimensions
            .getRange(signal.numUnpackedDimensions, signal.dimensions.length);
        // ignore: parameter_assignments, prefer_interpolation_to_compose_strings
        return packedDims.map((d) => '[${d - 1}:0]').join() +
            ' [${signal.elementWidth - 1}:0] $signalName' +
            unpackedDims.map((d) => '[${d - 1}:0]').join();
      } else if (signal.width != 1) {
        return '[${signal.width - 1}:0] $signalName';
      } else {
        return signalName;
      }
    }

    final topModule = moduleName ?? module.definitionName;
    final allSignals = <String>{
      for (final v in vectors) ...v.inputValues.keys,
      for (final v in vectors) ...v.expectedOutputValues.keys,
    };
    final localDeclarations =
        allSignals.map((e) => 'logic ${signalDeclaration(e)};').join('\n');
    final moduleConnections = allSignals.map((e) => '.$e($e)').join(', ');
    final moduleInstance = '$topModule dut($moduleConnections);';
    final stimulus = vectors.map((e) => e.toTbVerilog(module)).join('\n');
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
      final maskedOutput = output
          .toString()
          .split('\n')
          .where((element) => element.isNotEmpty)
          .map((line) {
            for (final knownWarning in _knownWarnings) {
              if (knownWarning.hasMatch(line)) {
                return null;
              }
            }
            return line;
          })
          .whereNotNull()
          .join('\n');
      if (maskedOutput.isNotEmpty) {
        print(maskedOutput);
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

    if (!buildOnly) {
      final simResult = Process.runSync('vvp', [tmpOutput]);
      if (printIfContentsAndCheckError(simResult.stdout)) {
        return false;
      }
      if (printIfContentsAndCheckError(simResult.stderr)) {
        return false;
      }
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
