/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// simcompare.dart
/// Helper functionality for unit testing (sv testbench generation, iverilog simulation, vectors, checking/comparison, etc.)
/// 
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class Vector {
  static const int period = 10;
  static const int offset = 2;
  final Map<String,dynamic> inputValues;
  final Map<String,dynamic> expectedOutputValues;
  Vector(this.inputValues, this.expectedOutputValues);

  @override
  String toString() {
    return '$inputValues => $expectedOutputValues';
  }

  String errorCheckString(String sigName, dynamic expected, String inputValues) {
    String expectedHexStr; 
    String expectedValStr;
    if(expected is int) {
      expectedHexStr = '0x'+expected.toRadixString(16);
      expectedValStr = expected.toString();
    } else if(expected is LogicValue) {
      expectedHexStr = expected.toString();
      expectedValStr = "'" + expected.toString();
    } else {
      throw Exception('Support for ${expected.runtimeType} is not supported (yet?).');
    }
    
    return 'if($sigName !== $expectedValStr) \$error(\$sformatf("Expected $sigName=$expectedHexStr, but found $sigName=0x%x with inputs $inputValues", $sigName));';
  }
  String toTbVerilog() {
    var assignments = inputValues.keys.map((signalName) => '$signalName = ${inputValues[signalName]};').join('\n');
    var checks = expectedOutputValues.keys
      .map((signalName) => errorCheckString(signalName, expectedOutputValues[signalName], inputValues.toString()))
      .join('\n');
    var tbVerilog = [
      assignments,
      '#$offset',
      checks,
      '#${period-offset}',
    ].join('\n');
    return tbVerilog;
  }
}


class SimCompare {
  
  static Future<void> checkFunctionalVector(Module module, List<Vector> vectors) async {
    var timestamp = 1.0;
    for(var vector in vectors) {
      // print('Running vector: $vector');
      Simulator.registerAction(timestamp, () async {
        for(var signalName in vector.inputValues.keys) {
          var value = vector.inputValues[signalName];
          await Simulator.tickExecute(() => module.input(signalName).put(value));
          // module.input(signalName).inject(value);
          // module.input(signalName).put(value);
        }
        for(var signalName in vector.expectedOutputValues.keys) {
          var value = vector.expectedOutputValues[signalName];
          var o = module.output(signalName);
          if(value is int) {
            expect(o.valueInt, equals(value));
          } else if(value is LogicValue && (value == LogicValue.x || value == LogicValue.z)) {
            o.value.toList().forEach((element) {
              expect(element, equals(value));
            });
          } else {
            throw Exception('Value type ${value.runtimeType} is not supported (yet?)');
          }
        }
      });
      timestamp += Vector.period;
    }
    Simulator.registerAction(timestamp + Vector.period, () => null); // just so it does one more thing at the end
    Simulator.setMaxSimTime(timestamp + 2*Vector.period);
    await Simulator.run();
  }

  static bool iverilogVector(String generatedVerilog, String topModule, List<Vector> vectors, 
        {
          bool dontDeleteTmpFiles=false,
          Map<String,int> signalToWidthMap = const {},
          List<String> iverilogExtraArgs = const [],
        }) {
    String signalDeclaration(String signalName) {
      if(signalToWidthMap.containsKey(signalName)) {
        var width = signalToWidthMap[signalName]!;
        return '[${width-1}:0] $signalName';
      } else {
        return signalName;
      }
    }
    var allSignals = vectors.map((e) => [...e.inputValues.keys, ...e.expectedOutputValues.keys]).reduce((a, b) => [...a, ...b]).toSet();
    var localDeclarations = allSignals.map((e) => 'logic ' + signalDeclaration(e) + ';').join('\n');
    var moduleConnections = allSignals.map((e) => '.$e($e)').join(', ');
    var moduleInstance = '$topModule dut($moduleConnections);';
    var stimulus = vectors.map((e) => e.toTbVerilog()).join('\n');

    var testbench = [
      generatedVerilog,
      'module tb;',
      localDeclarations,
      moduleInstance,
      'initial begin',
      stimulus,
      '\$finish;', // so the test doesn't run forever if there's a clock generator
      'end',
      'endmodule',
    ].join('\n');

    var uniqueId = testbench.hashCode; // so that when they run in parallel, they dont step on each other
    var dir = 'tmp_test';
    var tmpTestFile = '$dir/tmp_test$uniqueId.sv';
    var tmpOutput = '$dir/tmp_out$uniqueId';
    Directory(dir).createSync(recursive:true);
    File(tmpTestFile).writeAsStringSync(testbench);
    var compileResult = Process.runSync('iverilog', ['-g2012', tmpTestFile, '-o', tmpOutput] + iverilogExtraArgs);
    bool printIfContentsAndCheckError(dynamic output) {
      if(output.toString().isNotEmpty) print(output);
      return output.toString().contains(RegExp('error|unable|warning', caseSensitive: false));
    }
    if(printIfContentsAndCheckError(compileResult.stdout)) return false;
    if(printIfContentsAndCheckError(compileResult.stderr)) return false;
    var simResult = Process.runSync('vvp', [tmpOutput]);
    if(printIfContentsAndCheckError(simResult.stdout)) return false;
    if(printIfContentsAndCheckError(simResult.stderr)) return false;
    if(!dontDeleteTmpFiles) {
      try {
        File(tmpOutput).deleteSync();
        File(tmpTestFile).deleteSync();
      } catch (e) {
        print("Couldn't delete: $e");
        return false;
      }
    }
    return true;
  }
}

