// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// simcompare.dart
// Helper functionality for unit testing (sv testbench generation, iverilog simulation, vectors, checking/comparison, etc.)
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>
// ignore_for_file: avoid_print - testing lib, printing important for debug

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/signals/signals.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesis_result.dart';
import 'package:rohd/src/utilities/uniquifier.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

part 'systemverilog_simcompare.dart';
part 'systemc_simcompare.dart';

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
    if (expected is! int &&
        expected is! LogicValue &&
        expected is! BigInt &&
        expected is! String) {
      throw NonSupportedTypeException(expected);
    }

    String expectedHexStr;
    if (expected is int) {
      expectedHexStr =
          BigInt.from(expected).toUnsigned(expectedVal.width).toRadixString(16);
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

  /// Converts this vector into a SystemVerilog check.
  String toTbVerilog(Module module) => _toTbVerilog(module);

  String _toTbVerilog(Module module,
      {Map<String, String> packedInputDrivers = const {}}) {
    final assignments = inputValues.keys.map((signalName) {
      final signal = module.tryInOut(signalName) ?? module.input(signalName);

      if (packedInputDrivers.containsKey(signalName)) {
        final value =
            LogicValue.of(inputValues[signalName], width: signal.width);
        return '${packedInputDrivers[signalName]} = $value;';
      } else if (signal is BaseLogicArray) {
        final arrAssigns = StringBuffer();
        var index = 0;
        final fullVal =
            LogicValue.of(inputValues[signalName], width: signal.width);
        for (final element in signal.arrayElements) {
          final subVal = fullVal.getRange(index, index + element.width);
          arrAssigns.writeln('${element.structureName} = $subVal;');
          index += element.width;
        }
        return arrAssigns.toString();
      } else {
        final signalVal =
            LogicValue.of(inputValues[signalName], width: signal.width);
        return '$signalName = $signalVal;';
      }
    }).join('\n');

    final checksList = <String>[];
    for (final expectedOutput in expectedOutputValues.entries) {
      final outputName = expectedOutput.key;
      final outputPort =
          module.tryInOut(outputName) ?? module.output(outputName);
      final expected = expectedOutput.value;
      final expectedValue = LogicValue.of(
        expected,
        width: outputPort.width,
      );
      final inputStimulus = inputValues.toString();

      if (outputPort is BaseLogicArray) {
        var index = 0;
        for (final element in outputPort.arrayElements) {
          final subVal = expectedValue.getRange(index, index + element.width);
          checksList.add(_errorCheckString(
              element.structureName, subVal, subVal, inputStimulus));
          index += element.width;
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

/// A simulation backend available to [SimCompare.checkVectors].
enum SimCompareBackend {
  /// ROHD's native simulator.
  rohd,

  /// Icarus Verilog.
  iverilog,

  /// Verilator.
  verilator,

  /// Native SystemC.
  systemc,
}

/// The outcome of one backend in a shared vector comparison.
enum SimCompareBackendStatus {
  /// The backend executed and all checks passed.
  passed,

  /// The backend tool was unavailable in an optional environment.
  skipped,

  /// The caller explicitly excluded the backend with a reason.
  excluded,

  /// The backend failed to compile, execute, or compare the vectors.
  failed,
}

/// The result for one backend in a shared vector comparison.
class SimCompareBackendResult {
  /// The backend that produced this result.
  final SimCompareBackend backend;

  /// The outcome of the backend check.
  final SimCompareBackendStatus status;

  /// Why the backend was skipped, excluded, or failed.
  final String? reason;

  const SimCompareBackendResult._(this.backend, this.status, [this.reason]);
}

/// Results from a shared vector comparison.
class SimCompareReport {
  /// Results keyed by every selected backend.
  final Map<SimCompareBackend, SimCompareBackendResult> results;

  SimCompareReport._(Map<SimCompareBackend, SimCompareBackendResult> results)
      : results = Map.unmodifiable(results);

  /// The result for [backend], or `null` if it was not selected.
  SimCompareBackendResult? operator [](SimCompareBackend backend) =>
      results[backend];
}

/// A utility class for checking a collection of [Vector]s against
/// different simulators.
abstract class SimCompare {
  /// Backends exercised by ordinary shared vector checks.
  ///
  /// Verilator remains available for focused checks through [checkVectors] or
  /// [checkVerilatorVector], but is not duplicated in the default matrix
  /// because Icarus already exercises generated SystemVerilog behavior.
  static const defaultVectorBackends = {
    SimCompareBackend.rohd,
    SimCompareBackend.iverilog,
    SimCompareBackend.systemc,
  };

  /// Checks [vectors] against the selected simulation backends.
  ///
  /// When [backends] is omitted, [defaultVectorBackends] is used. Ordinary
  /// functional tests should use that default rather than list backends.
  /// Focused backend tests may pass an explicit set.
  ///
  /// [excludedBackends] must provide a non-empty reason for every explicit
  /// exclusion. An exclusion is reported separately from an unavailable-tool
  /// skip and from a pass. Backend failures are collected and reported
  /// together with the backend that failed. [allowIverilogWarnings] and
  /// [dontDeleteSystemCTmpFiles] support existing specialized test fixtures
  /// without requiring separate ordinary backend calls.
  static Future<SimCompareReport> checkVectors(
    Module module,
    List<Vector> vectors, {
    Set<SimCompareBackend>? backends,
    Map<SimCompareBackend, String> excludedBackends = const {},
    bool? requireSystemC,
    String? systemcHome,
    String? systemcLib,
    bool? requireVerilator,
    String verilatorExecutable = 'verilator',
    bool allowIverilogWarnings = false,
    bool dontDeleteSystemCTmpFiles = false,
  }) async {
    final selected = backends ?? defaultVectorBackends;
    if (selected.isEmpty) {
      throw ArgumentError.value(backends, 'backends', 'Must not be empty.');
    }
    for (final entry in excludedBackends.entries) {
      if (!selected.contains(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'excludedBackends',
          'Excluded backends must also be selected.',
        );
      }
      if (entry.value.trim().isEmpty) {
        throw ArgumentError.value(
          entry.value,
          'excludedBackends',
          'Every backend exclusion must include a reason.',
        );
      }
    }

    final results = <SimCompareBackend, SimCompareBackendResult>{};
    for (final backend in SimCompareBackend.values) {
      if (!selected.contains(backend)) {
        continue;
      }

      final exclusionReason = excludedBackends[backend];
      if (exclusionReason != null) {
        results[backend] = SimCompareBackendResult._(
          backend,
          SimCompareBackendStatus.excluded,
          exclusionReason,
        );
        continue;
      }

      try {
        switch (backend) {
          case SimCompareBackend.rohd:
            await checkFunctionalVector(module, vectors);
          case SimCompareBackend.iverilog:
            if (kIsWeb) {
              results[backend] = SimCompareBackendResult._(
                backend,
                SimCompareBackendStatus.skipped,
                'Icarus checks require the Dart VM.',
              );
              continue;
            }
            checkIverilogVector(
              module,
              vectors,
              allowWarnings: allowIverilogWarnings,
            );
          case SimCompareBackend.verilator:
            String? skipReason;
            final passed = checkVerilatorVector(
              module,
              vectors,
              requireTool: requireVerilator,
              verilatorExecutable: verilatorExecutable,
              onSkip: (reason) => skipReason = reason,
            );
            if (!passed) {
              if (skipReason == null) {
                throw StateError(
                  'Verilator returned without passing or reporting a skip.',
                );
              }
              results[backend] = SimCompareBackendResult._(
                backend,
                SimCompareBackendStatus.skipped,
                skipReason,
              );
              continue;
            }
          case SimCompareBackend.systemc:
            String? skipReason;
            final passed = checkSystemCVector(
              module,
              vectors,
              systemcHome: systemcHome,
              systemcLib: systemcLib,
              requireTool: requireSystemC,
              dontDeleteTmpFiles: dontDeleteSystemCTmpFiles,
              onSkip: (reason) => skipReason = reason,
            );
            if (!passed) {
              if (skipReason == null) {
                throw StateError(
                  'SystemC returned without passing or reporting a skip.',
                );
              }
              results[backend] = SimCompareBackendResult._(
                backend,
                SimCompareBackendStatus.skipped,
                skipReason,
              );
              continue;
            }
        }
        results[backend] = SimCompareBackendResult._(
          backend,
          SimCompareBackendStatus.passed,
        );
      } on Object catch (error) {
        results[backend] = SimCompareBackendResult._(
          backend,
          SimCompareBackendStatus.failed,
          error.toString(),
        );
      }
    }

    for (final result in results.values.where(
      (result) =>
          result.status == SimCompareBackendStatus.skipped ||
          result.status == SimCompareBackendStatus.excluded,
    )) {
      print(
        'SimCompare ${result.backend.name} ${result.status.name}: '
        '${result.reason}',
      );
    }

    final failures = results.values
        .where((result) => result.status == SimCompareBackendStatus.failed)
        .toList();
    if (failures.isNotEmpty) {
      fail(
        'Vector comparison failed for ${module.definitionName}:\n'
        '${failures.map(
              (result) => '[${result.backend.name}] ${result.reason}',
            ).join('\n')}',
      );
    }

    return SimCompareReport._(results);
  }

  static bool _verilatorExecutableExists(String executable) {
    final names = [
      executable,
      if (Platform.isWindows)
        for (final extension
            in (Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD;.COM')
                .split(';'))
          '$executable$extension',
    ];
    final paths = [
      '',
      ...(Platform.environment['PATH'] ?? '')
          .split(Platform.isWindows ? ';' : ':'),
    ];
    return paths.any((path) => names.any((name) =>
        FileSystemEntity.typeSync(
            path.isEmpty ? name : '$path${Platform.pathSeparator}$name',
            followLinks: false) !=
        FileSystemEntityType.notFound));
  }

  /// Checks [vectors] using Verilator, building and running a timed testbench.
  ///
  /// With [buildOnly], only performs front-end compilation and elaboration:
  /// no C++ compiler is needed and no simulation is run. If [vectors] is empty
  /// in this mode, checks the design without a testbench.
  ///
  /// Simulation requires Verilator with timing support, a C++ compiler, and
  /// Make. Input and expected output values containing X or Z are rejected
  /// because Verilator does not provide four-state simulation. Use ROHD or
  /// Icarus for four-state checks; [buildOnly] permits four-state vectors.
  ///
  /// [dumpWaves] enables VCD tracing in the temporary directory. Set
  /// [dontDeleteTmpFiles] to retain the generated source, binary, and waves.
  /// [moduleName] overrides the DUT definition name. [verilatorExtraArgs] and
  /// [synthesizerConfiguration] control compilation and synthesis respectively.
  ///
  /// Returns true on success, or false when the test is explicitly skipped.
  /// Web tests always skip. If [verilatorExecutable] is absent, skips unless
  /// [requireTool] is true (defaulting to `ROHD_REQUIRE_VERILATOR=1`).
  /// [onSkip] reports the reason, marking the current test skipped by default.
  /// Execution, compilation, and simulation failures always fail the test.
  /// Warnings are visible but nonfatal by default.
  static bool checkVerilatorVector(
    Module module,
    List<Vector> vectors, {
    String? moduleName,
    bool? requireTool,
    void Function(String) onSkip = markTestSkipped,
    String verilatorExecutable = 'verilator',
    List<String> verilatorExtraArgs = const [],
    bool dontDeleteTmpFiles = false,
    bool dumpWaves = false,
    bool buildOnly = false,
    SystemVerilogSynthesizerConfiguration synthesizerConfiguration =
        const SystemVerilogSynthesizerConfiguration(),
  }) {
    if (kIsWeb) {
      onSkip('Verilator checks require the Dart VM.');
      return false;
    }

    if (!buildOnly) {
      for (final vector in vectors) {
        for (final values in [
          vector.inputValues,
          vector.expectedOutputValues
        ]) {
          for (final entry in values.entries) {
            final signal = identical(values, vector.inputValues)
                ? module.tryInOut(entry.key) ?? module.input(entry.key)
                : module.tryInOut(entry.key) ?? module.output(entry.key);
            if (!LogicValue.of(entry.value, width: signal.width).isValid) {
              throw ArgumentError('Verilator simulation requires two-state '
                  'vectors; ${entry.key} contains X or Z in $vector.');
            }
          }
        }
      }
    }

    final required =
        requireTool ?? Platform.environment['ROHD_REQUIRE_VERILATOR'] == '1';
    ProcessResult version;
    try {
      version = Process.runSync(verilatorExecutable, ['--version']);
    } on ProcessException catch (error) {
      if (error.errorCode != 2 &&
          !(Platform.isWindows && error.errorCode == 3)) {
        rethrow;
      }
      if (_verilatorExecutableExists(verilatorExecutable)) {
        rethrow;
      }
      final message = 'Verilator executable "$verilatorExecutable" not found. '
          'Install Verilator to run SystemVerilog checks.';
      if (required) {
        fail(message);
      }
      onSkip(message);
      return false;
    }
    expect(version.exitCode, 0,
        reason: 'Could not run $verilatorExecutable --version:\n'
            '${version.stdout}\n${version.stderr}');

    final generatedVerilog = module.dumpSystemVerilog(
      configuration: synthesizerConfiguration,
    );
    final withTestbench = !buildOnly || vectors.isNotEmpty;
    const completionMarker = 'ROHD_VERILATOR_VECTORS_PASSED';
    final testbenchName = Uniquifier(reservedNames: {
      moduleName ?? module.definitionName,
      ...module.subModules.map((child) => child.definitionName),
    }).getUniqueName(initialName: 'rohd_verilator_tb');
    var verilog = generatedVerilog;
    if (withTestbench) {
      final contents = _vectorTestbenchContents(module, vectors,
          moduleName: moduleName, usePackedInputDrivers: true);
      verilog = [
        generatedVerilog,
        'module $testbenchName;',
        contents.declarations,
        contents.instance,
        'initial begin',
        if (dumpWaves) ...[
          r'$dumpfile("waves.vcd");',
          r'$dumpvars(0,dut);',
        ],
        '#1',
        contents.stimulus,
        '\$display("$completionMarker");',
        r'$finish;',
        'end',
        'endmodule',
      ].join('\n');
    }
    final directory = (Directory('tmp_test')..createSync(recursive: true))
        .createTempSync('verilator_')
        .absolute;
    try {
      final source = File('${directory.path}/design.sv')
        ..writeAsStringSync(verilog);
      final arguments = [
        if (buildOnly) '--lint-only' else '--binary',
        if (withTestbench) '--timing',
        if (!buildOnly) ...[
          '--assert',
          '-j',
          '1',
          '-o',
          'rohd_sim',
        ],
        if (dumpWaves) '--trace',
        '-Wno-fatal',
        '--top-module',
        if (withTestbench)
          testbenchName
        else
          moduleName ?? module.definitionName,
        '--Mdir',
        '${directory.path}/obj_dir',
        ...verilatorExtraArgs,
        source.path,
      ];
      final result = Process.runSync(verilatorExecutable, arguments);
      final diagnostics = '${result.stdout}\n${result.stderr}'.trim();
      expect(result.exitCode, 0,
          reason: 'Verilator compilation failed.\n'
              'Command: $verilatorExecutable ${arguments.join(' ')}\n'
              '$diagnostics');
      final warnings =
          buildOnly ? diagnostics : result.stderr.toString().trim();
      if (warnings.isNotEmpty) {
        print(warnings);
      }
      if (!buildOnly) {
        final executable = '${directory.path}/obj_dir/rohd_sim';
        final simulation = Process.runSync(executable, const [],
            workingDirectory: directory.path);
        final output = '${simulation.stdout}\n${simulation.stderr}'.trim();
        expect(simulation.exitCode, 0,
            reason: 'Verilator simulation failed.\n'
                'Command: $executable\n$output');
        expect(simulation.stdout.toString(), contains(completionMarker),
            reason: 'Verilator simulation exited before completing the vectors.'
                '\nCommand: $executable\n$output');
      }
      return true;
    } finally {
      if (dontDeleteTmpFiles) {
        print('Verilator files retained in ${directory.path}');
      } else {
        directory.deleteSync(recursive: true);
      }
    }
  }

  /// Runs a ROHD simulation where each of the [vectors] is executed per
  /// clock cycle sequentially.
  ///
  /// If [enableChecking] is set to false, then it will drive the simulation
  /// but not check that the outputs match.
  static Future<void> checkFunctionalVector(Module module, List<Vector> vectors,
      {bool enableChecking = true}) async {
    var timestamp = 1;

    final ioInputDrivers = <String, Logic>{};
    Logic getIoInputDriver(String signalName) {
      if (ioInputDrivers.containsKey(signalName)) {
        return ioInputDrivers[signalName]!;
      }

      final signal = module.inOutSource(signalName);
      final driver = Logic(name: 'driver_of_$signalName', width: signal.width);
      signal <= driver;
      ioInputDrivers[signalName] = driver;
      return driver;
    }

    for (final vector in vectors) {
      Simulator.registerAction(timestamp, () {
        for (final signalName in vector.inputValues.keys) {
          final value = vector.inputValues[signalName];
          (module.tryInput(signalName) ?? getIoInputDriver(signalName))
              .put(value);
        }

        if (enableChecking) {
          unawaited(Simulator.postTick.first.then((value) {
            for (final signalName in vector.expectedOutputValues.keys) {
              final value = vector.expectedOutputValues[signalName];
              final o =
                  module.tryOutput(signalName) ?? module.inOut(signalName);

              final errorReason =
                  'For vector #${vectors.indexOf(vector)} $vector,'
                  ' expected $o to be $value, but it was ${o.value}.';
              if (value is int) {
                expect(o.value.isValid, isTrue, reason: errorReason);
                expect(o.value.toBigInt(),
                    equals(BigInt.from(value).toUnsigned(o.width)),
                    reason: errorReason);
              } else if (value is BigInt) {
                expect(o.value.isValid, isTrue, reason: errorReason);
                expect(o.value.toBigInt(), equals(value), reason: errorReason);
              } else if (value is LogicValue) {
                if (o.width > 1 &&
                    (value == LogicValue.x || value == LogicValue.z)) {
                  for (final oBit in o.value.toList()) {
                    expect(oBit, equals(value), reason: errorReason);
                  }
                } else {
                  expect(o.value, equals(value), reason: errorReason);
                }
              } else if (value is String) {
                expect(o.value, LogicValue.of(value, width: o.width),
                    reason: errorReason);
              } else {
                throw NonSupportedTypeException(value);
              }
            }
          }).catchError(
            test: (error) => error is Exception,
            (Object err, StackTrace stackTrace) {
              Simulator.throwException(err as Exception, stackTrace);
            },
          ));
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
    RegExp('finish called at'),
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
    SystemVerilogSynthesizerConfiguration synthesizerConfiguration =
        const SystemVerilogSynthesizerConfiguration(),
  }) {
    final result = iverilogVector(module, vectors,
        moduleName: moduleName,
        dontDeleteTmpFiles: dontDeleteTmpFiles,
        dumpWaves: dumpWaves,
        iverilogExtraArgs: iverilogExtraArgs,
        allowWarnings: allowWarnings,
        maskKnownWarnings: maskKnownWarnings,
        buildOnly: buildOnly,
        synthesizerConfiguration: synthesizerConfiguration);
    if (enableChecking) {
      expect(result, true);
    }
  }

  static ({String declarations, String instance, String stimulus})
      _vectorTestbenchContents(Module module, List<Vector> vectors,
          {String? moduleName, bool usePackedInputDrivers = false}) {
    String signalDeclaration(String signalName,
        {String Function(String original)? adjust,
        String? signalTypeOverride}) {
      final signal = module.signals.firstWhere((e) => e.name == signalName);
      final isOutput = module.tryOutput(signalName) != null;

      final signalType = signalTypeOverride ??
          ((isOutput ||
                  signal is LogicNet ||
                  (signal is BaseLogicArray && signal.isNet))
              ? 'wire'
              : 'logic');

      if (adjust != null) {
        signalName = adjust(signalName);
      }

      if (signal is BaseLogicArray) {
        final unpackedDims =
            signal.dimensions.getRange(0, signal.numUnpackedDimensions);
        final packedDims = signal.dimensions
            .getRange(signal.numUnpackedDimensions, signal.dimensions.length);
        final packedDimensions =
            packedDims.map((dimension) => '[${dimension - 1}:0]').join();
        final unpackedDimensions =
            unpackedDims.map((dimension) => '[${dimension - 1}:0]').join();

        return '$signalType $packedDimensions'
            ' [${signal.elementWidth - 1}:0] $signalName'
            '$unpackedDimensions';
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

    late final tbWireUniquifier = Uniquifier(reservedNames: allSignals);
    late final alreadyMappedLogicToWires = <String, String>{};
    String toTbWireName(String name) => alreadyMappedLogicToWires.putIfAbsent(
        name, () => tbWireUniquifier.getUniqueName(initialName: 'wire__$name'));

    final logicToWireMapping = Map.fromEntries(vectors
        .map((v) => v.inputValues.keys)
        .flattened
        .where((name) => module.tryInOut(name) != null)
        .map((name) => MapEntry(name, toTbWireName(name))));

    final packedInputDrivers = <String, String>{};
    final packedInputDeclarations = <String>[];
    if (usePackedInputDrivers) {
      for (final signalName in allSignals) {
        final signal = module.tryInput(signalName);
        if (signal is! BaseLogicArray) {
          continue;
        }
        final driver =
            tbWireUniquifier.getUniqueName(initialName: 'driver__$signalName');
        packedInputDrivers[signalName] = driver;
        packedInputDeclarations.add('logic [${signal.width - 1}:0] $driver;');
        var offset = 0;
        for (final element in signal.arrayElements) {
          packedInputDeclarations.add('assign ${element.structureName} = '
              '$driver[${offset + element.width - 1}:$offset];');
          offset += element.width;
        }
      }
    }

    final localDeclarations = [
      ...packedInputDeclarations,
      ...allSignals.map((e) {
        final sigDecl = signalDeclaration(e,
            signalTypeOverride:
                logicToWireMapping.containsKey(e) ? 'logic' : null);
        return '$sigDecl;';
      }),
      ...logicToWireMapping.entries.map((e) {
        final logicName = e.key;
        final wireName = e.value;

        final sigDecl = signalDeclaration(logicName,
            adjust: toTbWireName, signalTypeOverride: 'wire');
        return '$sigDecl; assign $wireName = $logicName;';
      }),
    ].join('\n');

    final moduleConnections =
        allSignals.map((e) => '.$e(${logicToWireMapping[e] ?? e})').join(', ');
    final moduleInstance = '$topModule dut($moduleConnections);';
    final stimulus = vectors
        .map((vector) =>
            vector._toTbVerilog(module, packedInputDrivers: packedInputDrivers))
        .join('\n');
    return (
      declarations: localDeclarations,
      instance: moduleInstance,
      stimulus: stimulus,
    );
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
    SystemVerilogSynthesizerConfiguration synthesizerConfiguration =
        const SystemVerilogSynthesizerConfiguration(),
  }) {
    if (kIsWeb) {
      // if running in web mode, then we can't run icarus verilog
      return true;
    }

    final (
      declarations: localDeclarations,
      instance: moduleInstance,
      :stimulus,
    ) = _vectorTestbenchContents(module, vectors, moduleName: moduleName);
    final generatedVerilog = module.dumpSystemVerilog(
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
          .nonNulls
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

  /// Removes cached SystemC build artifacts, optionally preserving PCH files.
  static void cleanupSystemCCache({bool keepPch = true}) =>
      _SystemCSimCompare.cleanupSystemCCache(keepPch: keepPch);

  /// Builds a SystemC executable for [module] using the supplied options.
  ///
  /// Clocks in [drivenClockNames] are driven by vectors instead of generated
  /// automatically and must be one-bit module inputs. Other detected clocks
  /// retain their automatic behavior. Supplying explicit values for an
  /// automatic clock to the built executable throws an [ArgumentError].
  static SystemCVectorExecutable? buildSystemCVectorExecutable(Module module,
          {String? moduleName,
          String? clockName,
          Set<String> drivenClockNames = const {},
          String? resetName,
          String? systemcHome,
          String? systemcLib,
          bool? requireTool,
          void Function(String) onSkip = markTestSkipped,
          String cxxExecutable = 'g++',
          bool usePrecompiledHeader = true,
          SystemCSynthesizerConfiguration synthesizerConfiguration =
              const SystemCSynthesizerConfiguration()}) =>
      _SystemCSimCompare.buildSystemCVectorExecutable(module,
          moduleName: moduleName,
          clockName: clockName,
          drivenClockNames: drivenClockNames,
          resetName: resetName,
          systemcHome: systemcHome,
          systemcLib: systemcLib,
          requireTool: requireTool,
          onSkip: onSkip,
          cxxExecutable: cxxExecutable,
          usePrecompiledHeader: usePrecompiledHeader,
          synthesizerConfiguration: synthesizerConfiguration);

  /// Runs [vectors] against a built SystemC [executable].
  static bool runSystemCVectors(
          SystemCVectorExecutable executable, List<Vector> vectors) =>
      _SystemCSimCompare.runSystemCVectors(executable, vectors);

  /// Checks [vectors] against a built SystemC [executable].
  static void checkSystemCVectors(
          SystemCVectorExecutable executable, List<Vector> vectors) =>
      _SystemCSimCompare.checkSystemCVectors(executable, vectors);

  /// Checks SystemC vectors generated from [module].
  ///
  /// Explicit clock values in [vectors] take precedence over automatic clocks.
  /// Detected clocks omitted from every vector are generated automatically.
  static bool checkSystemCVector(Module module, List<Vector> vectors,
          {String? moduleName,
          bool dontDeleteTmpFiles = false,
          String? clockName,
          String? resetName,
          String? systemcHome,
          String? systemcLib,
          bool buildOnly = false,
          bool? requireTool,
          void Function(String) onSkip = markTestSkipped,
          String cxxExecutable = 'g++',
          bool usePrecompiledHeader = true,
          SystemCSynthesizerConfiguration synthesizerConfiguration =
              const SystemCSynthesizerConfiguration()}) =>
      _SystemCSimCompare.checkSystemCVector(module, vectors,
          moduleName: moduleName,
          dontDeleteTmpFiles: dontDeleteTmpFiles,
          clockName: clockName,
          resetName: resetName,
          systemcHome: systemcHome,
          systemcLib: systemcLib,
          buildOnly: buildOnly,
          requireTool: requireTool,
          onSkip: onSkip,
          cxxExecutable: cxxExecutable,
          usePrecompiledHeader: usePrecompiledHeader,
          synthesizerConfiguration: synthesizerConfiguration);

  /// Compares [module] behavior with SystemC using [stimulus].
  static Future<bool> systemcSimCompare(Module module, Logic clk,
          {required Future<void> Function() stimulus,
          List<String>? inputNames,
          List<String>? outputNames,
          String? clockName,
          String? resetName,
          bool dontDeleteTmpFiles = false,
          String? systemcHome,
          String? systemcLib,
          bool? requireTool,
          void Function(String) onSkip = markTestSkipped,
          String cxxExecutable = 'g++',
          bool usePrecompiledHeader = true,
          SystemCSynthesizerConfiguration synthesizerConfiguration =
              const SystemCSynthesizerConfiguration()}) =>
      _SystemCSimCompare.systemcSimCompare(module, clk,
          stimulus: stimulus,
          inputNames: inputNames,
          outputNames: outputNames,
          clockName: clockName,
          resetName: resetName,
          dontDeleteTmpFiles: dontDeleteTmpFiles,
          systemcHome: systemcHome,
          systemcLib: systemcLib,
          requireTool: requireTool,
          onSkip: onSkip,
          cxxExecutable: cxxExecutable,
          usePrecompiledHeader: usePrecompiledHeader,
          synthesizerConfiguration: synthesizerConfiguration);
}
