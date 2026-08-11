// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_simcompare.dart
// SystemVerilog testbench generation and simulation comparison support for
// SimCompare.
//
// 2026 July 20
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// ignore_for_file: avoid_print

part of 'simcompare.dart';

class _SystemVerilogVectorTestbench {
  final Vector vector;
  final Module module;

  _SystemVerilogVectorTestbench(this.vector, this.module);

  /// Computes a SystemVerilog code string that checks in a SystemVerilog
  /// simulation whether a signal [sigName] has the [expected] value given
  /// the [inputValues].
  static String _errorCheckString(
    String sigName,
    dynamic expected,
    LogicValue expectedVal,
    String inputValues,
  ) {
    if (expected is! int &&
        expected is! LogicValue &&
        expected is! BigInt &&
        expected is! String) {
      throw NonSupportedTypeException(expected);
    }

    String expectedHexStr;
    if (expected is int) {
      expectedHexStr = BigInt.from(
        expected,
      ).toUnsigned(expectedVal.width).toRadixString(16);
      expectedHexStr = '0x$expectedHexStr';
    } else if (expected is BigInt) {
      expectedHexStr = expected.toUnsigned(expectedVal.width).toRadixString(16);
      expectedHexStr = '0x$expectedHexStr';
    } else {
      expectedHexStr = expected.toString();
    }

    final expectedValStr = expectedVal.toString();

    return 'if($sigName !== $expectedValStr) '
        '\$error(\$sformatf("Expected $sigName=$expectedHexStr,'
        ' but found $sigName=0x%x (0b%b) with inputs $inputValues",'
        ' $sigName, $sigName));';
  }

  String toTbVerilog() {
    final assignments = vector.inputValues.keys.map((signalName) {
      final signal = module.tryInOut(signalName) ?? module.input(signalName);

      if (signal is LogicArray) {
        final arrAssigns = StringBuffer();
        var index = 0;
        final fullVal = LogicValue.of(
          vector.inputValues[signalName],
          width: signal.width,
        );
        for (final leaf in signal.leafElements) {
          final subVal = fullVal.getRange(index, index + leaf.width);
          arrAssigns.writeln('${leaf.structureName} = $subVal;');
          index += leaf.width;
        }
        return arrAssigns.toString();
      } else {
        final signalVal = LogicValue.of(
          vector.inputValues[signalName],
          width: signal.width,
        );
        return '$signalName = $signalVal;';
      }
    }).join('\n');

    final checksList = <String>[];
    for (final expectedOutput in vector.expectedOutputValues.entries) {
      final outputName = expectedOutput.key;
      final outputPort =
          module.tryInOut(outputName) ?? module.output(outputName);
      final expected = expectedOutput.value;
      final expectedValue = LogicValue.of(expected, width: outputPort.width);
      final inputStimulus = vector.inputValues.toString();

      if (outputPort is LogicArray) {
        var index = 0;
        for (final leaf in outputPort.leafElements) {
          final subVal = expectedValue.getRange(index, index + leaf.width);
          checksList.add(
            _errorCheckString(
              leaf.structureName,
              subVal,
              subVal,
              inputStimulus,
            ),
          );
          index += leaf.width;
        }
      } else {
        checksList.add(
          _errorCheckString(outputName, expected, expectedValue, inputStimulus),
        );
      }
    }
    final checks = checksList.join('\n');

    return [
      assignments,
      '#${Vector._offset}',
      checks,
      '#${Vector._period - Vector._offset}',
    ].join('\n');
  }
}

class _SystemVerilogSimCompare {
  /// A collection of warnings that are fine to ignore usually.
  static final List<RegExp> _knownWarnings = [
    RegExp('sorry: Case unique/unique0 qualities are ignored.'),
    RegExp(
      r'sorry: constant selects in always_\* processes'
      ' are not currently supported',
    ),
    RegExp('warning: always_comb process has no sensitivities'),
    RegExp('finish called at'),
  ];

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
    SystemVerilogSynthesizerConfiguration synthesizerConfiguration =
        const SystemVerilogSynthesizerConfiguration(),
  }) {
    final result = iverilogVector(
      module,
      vectors,
      moduleName: moduleName,
      dontDeleteTmpFiles: dontDeleteTmpFiles,
      dumpWaves: dumpWaves,
      iverilogExtraArgs: iverilogExtraArgs,
      allowWarnings: allowWarnings,
      maskKnownWarnings: maskKnownWarnings,
      buildOnly: buildOnly,
      synthesizerConfiguration: synthesizerConfiguration,
    );
    if (enableChecking) {
      expect(result, true);
    }
  }

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
    SystemVerilogSynthesizerConfiguration synthesizerConfiguration =
        const SystemVerilogSynthesizerConfiguration(),
  }) {
    if (kIsWeb) {
      // if running in web mode, then we can't run icarus verilog
      return true;
    }

    String signalDeclaration(
      String signalName, {
      String Function(String original)? adjust,
      String? signalTypeOverride,
    }) {
      final signal = module.signals.firstWhere((e) => e.name == signalName);

      final signalType = signalTypeOverride ??
          ((signal is LogicNet || (signal is LogicArray && signal.isNet))
              ? 'wire'
              : 'logic');

      if (adjust != null) {
        signalName = adjust(signalName);
      }

      if (signal is LogicArray) {
        final unpackedDims = signal.dimensions.getRange(
          0,
          signal.numUnpackedDimensions,
        );
        final packedDims = signal.dimensions.getRange(
          signal.numUnpackedDimensions,
          signal.dimensions.length,
        );
        // ignore: prefer_interpolation_to_compose_strings
        return signalType +
            ' ' +
            // ignore: prefer_interpolation_to_compose_strings
            packedDims.map((d) => '[${d - 1}:0]').join() +
            ' [${signal.elementWidth - 1}:0] $signalName' +
            unpackedDims.map((d) => '[${d - 1}:0]').join();
      } else if (signal.width != 1) {
        return '$signalType [${signal.width - 1}:0] $signalName';
      } else {
        return '$signalType $signalName';
      }
    }

    final topModule = moduleName ?? module.definitionName;
    final allSignals = <String>{
      for (final v in vectors) ...v.inputValues.keys,
      for (final v in vectors) ...v.expectedOutputValues.keys,
    };

    late final tbWireUniquifier = Uniquifier();
    late final alreadyMappedLogicToWires = <String, String>{};
    String toTbWireName(String name) => alreadyMappedLogicToWires.putIfAbsent(
          name,
          () => tbWireUniquifier.getUniqueName(initialName: 'wire__$name'),
        );

    final logicToWireMapping = Map.fromEntries(
      vectors
          .map((v) => v.inputValues.keys)
          .flattened
          .where((name) => module.tryInOut(name) != null)
          .map((name) => MapEntry(name, toTbWireName(name))),
    );

    final localDeclarations = [
      ...allSignals.map((e) {
        final sigDecl = signalDeclaration(
          e,
          signalTypeOverride:
              logicToWireMapping.containsKey(e) ? 'logic' : null,
        );
        return '$sigDecl;';
      }),
      ...logicToWireMapping.entries.map((e) {
        final logicName = e.key;
        final wireName = e.value;

        final sigDecl = signalDeclaration(
          logicName,
          adjust: toTbWireName,
          signalTypeOverride: 'wire',
        );
        return '$sigDecl; assign $wireName = $logicName;';
      }),
    ].join('\n');

    final moduleConnections =
        allSignals.map((e) => '.$e(${logicToWireMapping[e] ?? e})').join(', ');
    final moduleInstance = '$topModule dut($moduleConnections);';
    final stimulus = vectors.map((e) => e.toTbVerilog(module)).join('\n');
    final generatedVerilog = module.generateSynth(
      configuration: synthesizerConfiguration,
    );

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
    final compileResult = Process.runSync('iverilog', [
      '-g2012',
      '-o',
      tmpOutput,
      ...iverilogExtraArgs,
      tmpTestFile,
    ]);
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
          .nonNulls
          .join('\n');
      if (maskedOutput.isNotEmpty) {
        print(maskedOutput);
      }

      return output.toString().contains(
            RegExp(
              ['error', 'unable', if (!allowWarnings) 'warning'].join('|'),
              caseSensitive: false,
            ),
          );
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
        final outFile = File(tmpOutput);
        if (outFile.existsSync()) {
          outFile.deleteSync();
        }
        final testFile = File(tmpTestFile);
        if (testFile.existsSync()) {
          testFile.deleteSync();
        }
        if (dumpWaves) {
          final vcdFile = File(tmpVcdFile);
          if (vcdFile.existsSync()) {
            vcdFile.deleteSync();
          }
        }
      } on Exception catch (e) {
        print("Couldn't delete: $e");
        return false;
      }
    }
    return true;
  }
}
