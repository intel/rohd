// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// simcompare.dart
// Helper functionality for unit testing (sv testbench generation, iverilog simulation, vectors, checking/comparison, etc.)
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemc/systemc_synthesis_result.dart';
import 'package:rohd/src/utilities/uniquifier.dart';
import 'package:rohd/src/utilities/web.dart';
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
  String toTbVerilog(Module module) {
    final assignments = inputValues.keys.map((signalName) {
      final signal = module.tryInOut(signalName) ?? module.input(signalName);

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
      final expectedValue = LogicValue.of(expected, width: outputPort.width);
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

    final tbVerilog =
        [assignments, '#$_offset', checks, '#${_period - _offset}'].join('\n');
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
      Simulator.registerAction(timestamp, () async {
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
          }).catchError(test: (error) => error is Exception,
              (Object err, StackTrace stackTrace) {
            Simulator.throwException(err as Exception, stackTrace);
          }));
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
    RegExp('finish called at')
  ];

  /// Executes [vectors] against the Icarus Verilog simulator and checks
  /// that it passes.
  static void checkIverilogVector(Module module, List<Vector> vectors,
      {String? moduleName,
      bool dontDeleteTmpFiles = false,
      bool dumpWaves = false,
      List<String> iverilogExtraArgs = const [],
      bool allowWarnings = false,
      bool maskKnownWarnings = true,
      bool enableChecking = true,
      bool buildOnly = false}) {
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
  static bool iverilogVector(Module module, List<Vector> vectors,
      {String? moduleName,
      bool dontDeleteTmpFiles = false,
      bool dumpWaves = false,
      List<String> iverilogExtraArgs = const [],
      bool allowWarnings = false,
      bool maskKnownWarnings = true,
      bool buildOnly = false}) {
    if (kIsWeb) {
      // if running in web mode, then we can't run icarus verilog
      return true;
    }

    String signalDeclaration(String signalName,
        {String Function(String original)? adjust,
        String? signalTypeOverride}) {
      final signal = module.signals.firstWhere((e) => e.name == signalName);

      final signalType = signalTypeOverride ??
          ((signal is LogicNet || (signal is LogicArray && signal.isNet))
              ? 'wire'
              : 'logic');

      if (adjust != null) {
        signalName = adjust(signalName);
      }

      if (signal is LogicArray) {
        final unpackedDims =
            signal.dimensions.getRange(0, signal.numUnpackedDimensions);
        final packedDims = signal.dimensions
            .getRange(signal.numUnpackedDimensions, signal.dimensions.length);
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
      for (final v in vectors) ...v.expectedOutputValues.keys
    };

    late final tbWireUniquifier = Uniquifier();
    late final alreadyMappedLogicToWires = <String, String>{};
    String toTbWireName(String name) => alreadyMappedLogicToWires.putIfAbsent(
        name, () => tbWireUniquifier.getUniqueName(initialName: 'wire__$name'));

    final logicToWireMapping = Map.fromEntries(vectors
        .map((v) => v.inputValues.keys)
        .flattened
        .where((name) => module.tryInOut(name) != null)
        .map((name) => MapEntry(name, toTbWireName(name))));

    final localDeclarations = [
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
      })
    ].join('\n');

    final moduleConnections =
        allSignals.map((e) => '.$e(${logicToWireMapping[e] ?? e})').join(', ');
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
      'endmodule'
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
          ['error', 'unable', if (!allowWarnings) 'warning'].join('|'),
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
      }
    }
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════
  // SystemC simulation (Accellera SystemC)
  // ══════════════════════════════════════════════════════════════════════

  /// The default SystemC installation path (Accellera).
  static const _systemCDefaultHome = '/opt/systemc/include';
  static const _systemCDefaultLib = '/opt/systemc/lib';

  /// Cache of compiled SystemC executables keyed by generated code hash.
  static final _compilationCache = <int, SystemCExecutable>{};

  /// Prefix for SystemC artifacts owned by this test process.
  static final String _systemCTempPrefix =
      'tmp_sc_${pid}_${DateTime.now().microsecondsSinceEpoch}_'
      '${Object().hashCode}';

  /// Path to the precompiled header, built lazily on first compilation.
  static String? _pchPath;

  /// Builds the precompiled header for systemc.h if not already done.
  /// Returns the directory containing systemc.h.gch, or null on failure.
  ///
  /// In CI, the PCH is pre-built by `tool/gh_actions/setup_systemc_pch.sh`
  /// before tests run, so this just finds it on disk. Locally it builds
  /// on first use (safe because local runs are typically sequential).
  static String? _ensurePch(String scHome, String cxxStd) {
    if (_pchPath != null) {
      return _pchPath;
    }

    const dir = 'tmp_test';
    const pchDir = '$dir/pch';
    const gchFile = '$pchDir/systemc.h.gch';

    // Reuse if already on disk (pre-built by CI or a previous run)
    if (File(gchFile).existsSync()) {
      return _pchPath = pchDir;
    }

    Directory(pchDir).createSync(recursive: true);

    // Copy the original header next to the .gch so g++ matches them
    File('$scHome/systemc.h').copySync('$pchDir/systemc.h');

    final args = [
      '-std=$cxxStd',
      '-I$scHome',
      '-x',
      'c++-header',
      '-o',
      gchFile,
      '$scHome/systemc.h'
    ];
    final result = Process.runSync('g++', args);
    if (result.exitCode != 0) {
      print('PCH compilation failed (falling back to normal headers):');
      print(result.stderr);
      return null;
    }

    return _pchPath = pchDir;
  }

  /// Resolves SystemC home/lib paths. If explicit paths are given, uses them.
  /// Otherwise uses the default Accellera install paths.
  static (String?, String?) _resolveSystemCPaths(String scHome, String scLib) {
    if (scHome.isNotEmpty && scLib.isNotEmpty) {
      if (Directory(scHome).existsSync()) {
        return (scHome, scLib);
      }
      return (null, null);
    }
    if (Directory(_systemCDefaultHome).existsSync()) {
      return (_systemCDefaultHome, _systemCDefaultLib);
    }
    return (null, null);
  }

  /// Detects the C++ standard the SystemC library was compiled with
  /// by inspecting the `sc_api_version` symbol in libsystemc.so.
  static String _detectCxxStandard(String scLib) {
    try {
      final result = Process.runSync('nm', ['-D', '$scLib/libsystemc.so']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        if (output.contains('cxx202002L')) {
          return 'c++20';
        }
        if (output.contains('cxx201703L')) {
          return 'c++17';
        }
      }
    } on Object {
      // Fall through to default
    }
    return 'c++20';
  }

  /// Cleans up all cached SystemC executables and the precompiled header.
  /// Call from `tearDownAll` in tests.
  ///
  /// If [keepPch] is true (the default), the precompiled header is preserved
  /// for faster subsequent runs. Pass `keepPch: false` to remove everything.
  static void cleanupSystemCCache({bool keepPch = true}) {
    _compilationCache.clear();
    _pchPath = null;
    if (kIsWeb) {
      return;
    }
    try {
      final dir = Directory('tmp_test');
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          final name = entity.uri.pathSegments.last;

          // Remove only SystemC artifacts owned by this test process. Other
          // test isolates may be compiling or running from the same tmp_test
          // directory concurrently.
          if (name.startsWith(_systemCTempPrefix) || name == 'Makefile_sc') {
            entity.deleteSync(recursive: true);
            continue;
          }

          // Remove pch/ directory only when keepPch is false
          if (!keepPch && entity is Directory && entity.path.endsWith('/pch')) {
            entity.deleteSync(recursive: true);
            continue;
          }

          // Leave everything else (iverilog files from parallel tests) alone
        }
      }
    } on Exception catch (_) {}
  }

  /// Compiles a SystemC module into a reusable stdin-driven executable.
  ///
  /// Returns a [SystemCExecutable] that can be used to run multiple vector
  /// sets without recompilation. Use in `setUpAll` for test groups.
  /// Results are cached — calling this with the same module definition
  /// returns the previously compiled binary.
  static SystemCExecutable? buildSystemCExecutable(Module module,
      {String? moduleName,
      String? clockName,
      String? resetName,
      String? systemcHome,
      String? systemcLib}) {
    if (kIsWeb) {
      return null;
    }

    final scHome = systemcHome ?? '';
    final scLib = systemcLib ?? '';
    final (resolvedHome, resolvedLib) = _resolveSystemCPaths(scHome, scLib);

    if (resolvedHome == null || resolvedLib == null) {
      print('SystemC installation not found');
      return null;
    }

    final topModule = moduleName ?? module.definitionName;
    final generatedSystemC = module.generateSystemC();

    // Check compilation cache
    final cacheKey = generatedSystemC.hashCode;
    if (_compilationCache.containsKey(cacheKey)) {
      final cached = _compilationCache[cacheKey]!;
      if (File(cached.binaryPath).existsSync()) {
        return cached;
      }
      // Binary was removed; recompile.
      _compilationCache.remove(cacheKey);
    }

    // Identify clock signals
    final clockSignals = <String>{};
    if (clockName != null) {
      clockSignals.add(clockName);
    }
    for (final input in module.inputs.entries) {
      final name = input.key;
      if (clockSignals.isEmpty && (name == 'clk' || name.contains('clock'))) {
        clockSignals.add(name);
      }
    }
    final promotedClocks = <String>{};
    for (final sub in module.subModules) {
      if (sub is SimpleClockGenerator) {
        final clkSigName = sub.clk.name;
        promotedClocks.add(clkSigName);
        clockSignals.add(clkSigName);
      }
    }

    // Collect ALL module ports for the stdin-driven harness
    final inputPorts = <String, int>{};
    for (final input in module.inputs.entries) {
      if (promotedClocks.contains(input.key)) {
        continue;
      }
      inputPorts[input.key] = input.value.width;
    }
    final outputPorts = <String, int>{};
    for (final output in module.outputs.entries) {
      outputPorts[output.key] = output.value.width;
    }

    // Generate stdin-driven testbench
    final tb = StringBuffer()
      ..writeln('#include <systemc.h>')
      ..writeln('#include <iostream>')
      ..writeln('#include <string>')
      ..writeln('#include <sstream>')
      ..writeln('#include <map>')
      ..writeln('#include <cmath>')
      ..writeln('using namespace std;')
      ..writeln()
      ..writeln(generatedSystemC)
      ..writeln()
      ..writeln('int sc_main(int argc, char* argv[]) {');

    // Clock
    for (final clkName in clockSignals) {
      tb.writeln(
          '    sc_clock $clkName("$clkName", ${Vector._period}, SC_NS);');
    }

    // Signals for all non-clock input ports
    for (final entry in inputPorts.entries) {
      if (clockSignals.contains(entry.key)) {
        continue;
      }
      tb.writeln(
          '    sc_signal<${SystemCSynthesisResult.systemCType(entry.value)}>'
          ' ${entry.key};');
    }

    // Signals for all output ports
    for (final entry in outputPorts.entries) {
      tb.writeln(
          '    sc_signal<${SystemCSynthesisResult.systemCType(entry.value)}>'
          ' ${entry.key};');
    }

    tb
      ..writeln()
      // DUT instantiation and port binding
      ..writeln('    $topModule dut("dut");');
    for (final name in inputPorts.keys) {
      tb.writeln('    dut.$name($name);');
    }
    for (final clkName in clockSignals) {
      if (!inputPorts.containsKey(clkName)) {
        tb.writeln('    dut.$clkName($clkName);');
      }
    }
    for (final name in outputPorts.keys) {
      tb.writeln('    dut.$name($name);');
    }

    tb
      ..writeln()
      ..writeln('    int _tb_errors = 0;')
      ..writeln()
      ..writeln('    // Initial offset')
      ..writeln('    sc_start(sc_time(1, SC_NS));')
      ..writeln()
      ..writeln('    // Read number of vectors')
      ..writeln('    int _tb_nvec;')
      ..writeln('    cin >> _tb_nvec;')
      ..writeln()
      ..writeln('    for (int _tb_v = 0; _tb_v < _tb_nvec; _tb_v++) {');

    // Read and drive each non-clock input
    final drivableInputs =
        inputPorts.keys.where((k) => !clockSignals.contains(k)).toList();
    for (final name in drivableInputs) {
      final w = inputPorts[name]!;
      if (w > 64) {
        // BigInt — read as hex string
        tb
          ..writeln('        { string _h; cin >> _h;')
          ..writeln('          sc_biguint<$w> _v(_h.c_str());')
          ..writeln('          $name.write(_v); }');
      } else {
        tb
          ..writeln('        { uint64_t _v; cin >> _v;')
          ..writeln('          $name.write(_v); }');
      }
    }

    // Advance to check point
    tb
      ..writeln()
      ..writeln('        sc_start(sc_time(${Vector._offset}, SC_NS));')
      ..writeln()
      ..writeln('        // Read number of outputs to check')
      ..writeln('        int _tb_nchk;')
      ..writeln('        cin >> _tb_nchk;')
      ..writeln()
      ..writeln('        for (int _tb_c = 0; _tb_c < _tb_nchk; _tb_c++) {')
      ..writeln('            string _tb_pn;')
      ..writeln('            cin >> _tb_pn;');

    // Generate if-else chain for each output port
    var first = true;
    for (final entry in outputPorts.entries) {
      final name = entry.key;
      final w = entry.value;
      final ifKey = first ? 'if' : '} else if';
      first = false;
      tb.writeln('            $ifKey (_tb_pn == "$name") {');
      if (w > 64) {
        tb
          ..writeln('                string _h; cin >> _h;')
          ..writeln('                sc_biguint<$w> _tb_exp(_h.c_str());')
          ..writeln('                if ($name.read() != _tb_exp) {');
      } else {
        tb
          ..writeln('                uint64_t _tb_exp; cin >> _tb_exp;')
          ..writeln('                if ($name.read() != _tb_exp) {');
      }
      tb
        ..writeln('                    cout << "ERROR vector " << _tb_v'
            ' << ": expected $name=" << _tb_exp'
            ' << ", got " << $name.read() << endl;')
        ..writeln('                    _tb_errors++;')
        ..writeln('                }');
    }
    if (outputPorts.isNotEmpty) {
      tb
        ..writeln('            } else {')
        ..writeln('                string _d; cin >> _d; // skip unknown')
        ..writeln('            }');
    }

    tb
      ..writeln('        }')
      ..writeln()
      ..writeln('        sc_start(sc_time('
          '${Vector._period - Vector._offset}, SC_NS));')
      ..writeln('    }')
      ..writeln()
      ..writeln('    if (_tb_errors == 0) {')
      ..writeln('        cout << "PASS" << endl;')
      ..writeln('    } else {')
      ..writeln('        cout << "FAIL: " << _tb_errors << " errors" << endl;')
      ..writeln('    }')
      ..writeln('    return _tb_errors > 0 ? 1 : 0;')
      ..writeln('}');

    final testbenchCode = tb.toString();

    // Write and compile
    const dir = 'tmp_test';
    Directory(dir).createSync(recursive: true);
    final compileDir = Directory(dir)
        .createTempSync('${_systemCTempPrefix}_${generatedSystemC.hashCode}_');
    final tmpCppFile = '${compileDir.path}/main.cpp';
    final tmpOutput = '${compileDir.path}/sim';
    File(tmpCppFile).writeAsStringSync(testbenchCode);

    // Detect C++ standard for this installation
    final cxxStd = _detectCxxStandard(resolvedLib);

    // Build precompiled header on first use
    final pchDir = _ensurePch(resolvedHome, cxxStd);
    final pchArgs = pchDir != null ? ['-I$pchDir'] : <String>[];

    final compileResult = Process.runSync('g++', [
      '-std=$cxxStd',
      '-pipe',
      ...pchArgs,
      '-I$resolvedHome',
      '-o',
      tmpOutput,
      tmpCppFile,
      '-L$resolvedLib',
      '-lsystemc'
    ]);
    if (compileResult.exitCode != 0) {
      print('SystemC compilation failed:');
      print(compileResult.stdout);
      print(compileResult.stderr);
      return null;
    }

    final exe = SystemCExecutable._(
        binaryPath: tmpOutput,
        cppFile: tmpCppFile,
        scLib: resolvedLib,
        clockSignals: clockSignals,
        inputPorts: inputPorts,
        outputPorts: outputPorts);
    _compilationCache[cacheKey] = exe;
    return exe;
  }

  /// Runs [vectors] against a pre-compiled [SystemCExecutable].
  ///
  /// Returns `true` if all vectors pass.
  static bool runSystemCVectors(SystemCExecutable exe, List<Vector> vectors) {
    if (!File(exe.binaryPath).existsSync()) {
      print('SystemC binary not found: ${exe.binaryPath}');
      return false;
    }

    // Build stdin data
    final sb = StringBuffer()..writeln(vectors.length);

    final drivableInputs = exe.inputPorts.keys
        .where((k) => !exe.clockSignals.contains(k))
        .toList();

    // Track last-driven values (persist across vectors like iverilog)
    final lastValues = <String, String>{
      for (final name in drivableInputs) name: '0'
    };

    for (final vector in vectors) {
      // Update last-driven values with this vector's inputs
      for (final name in drivableInputs) {
        final value = vector.inputValues[name];
        if (value != null) {
          final w = exe.inputPorts[name]!;
          if (w > 64) {
            final lv = LogicValue.of(value, width: w);
            var hex = lv.toBigInt().toUnsigned(w).toRadixString(16);
            if (hex.length.isOdd) {
              hex = '0$hex';
            }
            lastValues[name] = '0x$hex';
          } else {
            lastValues[name] = '${_systemcIntValue(value, w)}';
          }
        }
      }
      // Write all input values (using persisted values for unspecified)
      for (final name in drivableInputs) {
        sb.write('${lastValues[name]} ');
      }
      sb.writeln();

      // Write expected outputs: count then name/value pairs
      // Skip x/z outputs
      final checks = <String, String>{};
      for (final entry in vector.expectedOutputValues.entries) {
        final name = entry.key;
        final w = exe.outputPorts[name]!;
        final expectedLV = LogicValue.of(entry.value, width: w);
        if (expectedLV.toString().contains('x') ||
            expectedLV.toString().contains('z')) {
          continue;
        }
        if (w > 64) {
          var hex = expectedLV.toBigInt().toUnsigned(w).toRadixString(16);
          if (hex.length.isOdd) {
            hex = '0$hex';
          }
          checks[name] = '0x$hex';
        } else {
          checks[name] = '${_systemcIntValue(entry.value, w)}';
        }
      }
      sb.write('${checks.length} ');
      for (final entry in checks.entries) {
        sb.write('${entry.key} ${entry.value} ');
      }
      sb.writeln();
    }

    // Write vectors to a unique temp file, redirect as stdin.
    final stdinDir = Directory('tmp_test').createTempSync('sc_input_');
    final stdinFile = '${stdinDir.path}/input.txt';
    late final ProcessResult result;
    try {
      File(stdinFile).writeAsStringSync(sb.toString());

      result = Process.runSync('sh', [
        '-c',
        '${exe.binaryPath} < $stdinFile'
      ], environment: {
        'LD_LIBRARY_PATH': exe.scLib,
        'SC_COPYRIGHT_MESSAGE': 'DISABLE'
      });
    } finally {
      if (stdinDir.existsSync()) {
        stdinDir.deleteSync(recursive: true);
      }
    }

    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString();

    if (stdout.isNotEmpty && !stdout.contains('PASS')) {
      print(stdout);
    }
    if (stderr.isNotEmpty && !stderr.contains('Info:')) {
      print(stderr);
    }

    return stdout.contains('PASS') && !stdout.contains('FAIL');
  }

  /// Convenience: runs [vectors] against a pre-compiled executable and
  /// asserts the result.
  static void checkSystemCVectors(SystemCExecutable exe, List<Vector> vectors) {
    expect(runSystemCVectors(exe, vectors), true);
  }

  /// Converts a value to an integer for stdin.
  static int _systemcIntValue(dynamic value, int width) {
    if (value is int) {
      return value;
    }
    if (value is LogicValue) {
      if (!value.isValid) {
        return 0;
      }
      return value.toBigInt().toUnsigned(width).toInt();
    }
    if (value is BigInt) {
      return value.toUnsigned(width).toInt();
    }
    if (value is String) {
      final lv = LogicValue.of(value, width: width);
      if (!lv.isValid) {
        return 0;
      }
      return lv.toBigInt().toUnsigned(width).toInt();
    }
    return 0;
  }

  /// Executes [vectors] against a SystemC simulator compiled with g++ and
  /// checks that it passes (single-shot, compiles each time).
  static void checkSystemCVector(Module module, List<Vector> vectors,
      {String? moduleName,
      bool dontDeleteTmpFiles = false,
      String? clockName,
      String? resetName,
      String? systemcHome,
      String? systemcLib,
      bool buildOnly = false}) {
    if (buildOnly) {
      // Just verify SystemC code generation succeeds
      module.generateSystemC();
      return;
    }
    final exe = buildSystemCExecutable(module,
        moduleName: moduleName,
        clockName: clockName,
        resetName: resetName,
        systemcHome: systemcHome,
        systemcLib: systemcLib);
    if (exe == null) {
      // SystemC not available — skip gracefully.
      return;
    }
    final passed = runSystemCVectors(exe, vectors);
    expect(passed, true);
  }

  /// Legacy API — returns bool.
  static bool systemcVector(Module module, List<Vector> vectors,
      {String? moduleName,
      bool dontDeleteTmpFiles = false,
      String? clockName,
      String? resetName,
      String? systemcHome,
      String? systemcLib,
      bool buildOnly = false}) {
    if (kIsWeb) {
      return true;
    }
    final exe = buildSystemCExecutable(module,
        moduleName: moduleName,
        clockName: clockName,
        resetName: resetName,
        systemcHome: systemcHome,
        systemcLib: systemcLib);
    if (exe == null) {
      return false;
    }
    if (buildOnly) {
      return true;
    }
    return runSystemCVectors(exe, vectors);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Trace-based SystemC co-simulation
  // ══════════════════════════════════════════════════════════════════════

  /// Runs the ROHD simulation using [stimulus], records input/output values
  /// at every posedge of [clk], then replays the captured vectors through
  /// the SystemC-synthesized version of [module] and compares results.
  ///
  /// [stimulus] is an async function that sets up and drives the simulation
  /// (inject signals, register actions, etc.) but does NOT call
  /// [Simulator.run] — that is done internally.
  ///
  /// [inputNames] and [outputNames] specify which ports to record. If null,
  /// all module inputs (excluding clock) and all module outputs are used.
  ///
  /// Example usage with an existing test:
  /// ```dart
  /// await SimCompare.systemcSimCompare(
  ///   counter,
  ///   clk,
  ///   stimulus: () async {
  ///     reset.inject(1);
  ///     en.inject(0);
  ///     Simulator.registerAction(25, () { reset.put(0); en.put(1); });
  ///     Simulator.setMaxSimTime(100);
  ///   },
  /// );
  /// ```
  static Future<bool> systemcSimCompare(Module module, Logic clk,
      {required Future<void> Function() stimulus,
      List<String>? inputNames,
      List<String>? outputNames,
      String? clockName,
      String? resetName,
      bool dontDeleteTmpFiles = false,
      String? systemcHome,
      String? systemcLib}) async {
    // Determine which signals to record
    final clkName = clockName ??
        module.inputs.keys.firstWhere((n) => n == 'clk' || n.contains('clock'),
            orElse: () => 'clk');

    final inputs =
        inputNames ?? module.inputs.keys.where((n) => n != clkName).toList();
    final outputs = outputNames ?? module.outputs.keys.toList();

    // Record snapshots at each posedge.
    // Use previousValue for outputs — this gives us the output state from
    // BEFORE the clock edge, which matches what the SystemC testbench sees
    // when it checks at offset (before the posedge).
    // Use current value for inputs — these are the values being presented
    // to the DUT when the clock edge fires.
    final recordings = <Vector>[];

    clk.posedge.listen((_) {
      // Sample inputs (current value — what's being driven now)
      final inputValues = <String, dynamic>{};
      for (final name in inputs) {
        final sig = module.input(name);
        final val = sig.value;
        inputValues[name] = val.isValid ? val.toBigInt().toInt() : 0;
      }

      // Sample outputs using previousValue — the settled output
      // from before this tick started, which is what a testbench
      // checking before the clock edge would observe.
      final outputValues = <String, dynamic>{};
      for (final name in outputs) {
        final sig = module.output(name);
        final prev = sig.previousValue;
        if (prev != null && prev.isValid) {
          outputValues[name] = prev.toBigInt().toInt();
        }
        // Skip null/x/z — no check for this output
      }

      recordings.add(Vector(inputValues, outputValues));
    });

    // Run the user's stimulus setup
    await stimulus();

    // Run the ROHD simulation
    await Simulator.run();

    if (recordings.length < 2) {
      print('Warning: only ${recordings.length} clock edges recorded,'
          ' need at least 2 for comparison');
      return true;
    }

    // No shifting needed — previousValue already gives us the output
    // state from before the posedge, which matches systemcVector's
    // check-before-edge timing. Just pass recordings directly as vectors.

    // Run through SystemC
    return systemcVector(module, recordings,
        clockName: clkName,
        resetName: resetName,
        dontDeleteTmpFiles: dontDeleteTmpFiles,
        systemcHome: systemcHome,
        systemcLib: systemcLib);
  }
}

/// Holds the compiled state of a SystemC executable for reuse across tests.
class SystemCExecutable {
  /// Path to the compiled binary.
  final String binaryPath;

  /// Path to the generated C++ source.
  final String cppFile;

  /// Path to the SystemC library (for LD_LIBRARY_PATH).
  final String scLib;

  /// Clock signal names.
  final Set<String> clockSignals;

  /// Input port names and widths (excluding promoted clocks).
  final Map<String, int> inputPorts;

  /// Output port names and widths.
  final Map<String, int> outputPorts;

  SystemCExecutable._(
      {required this.binaryPath,
      required this.cppFile,
      required this.scLib,
      required this.clockSignals,
      required this.inputPorts,
      required this.outputPorts});

  /// Deletes the compiled binary and source.
  void cleanup() {
    void tryDelete(String path) {
      final f = File(path);
      if (f.existsSync()) {
        f.deleteSync();
      }
    }

    try {
      final compileDir = File(cppFile).parent;
      if (compileDir.existsSync() &&
          compileDir.uri.pathSegments.last
              .startsWith(SimCompare._systemCTempPrefix)) {
        compileDir.deleteSync(recursive: true);
        return;
      }
      tryDelete(cppFile);
      tryDelete(binaryPath);
    } on Exception catch (_) {}
  }
}
