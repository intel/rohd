// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// simcompare.dart
// Helper functionality for unit testing (sv testbench generation,
// iverilog simulation, vectors, checking/comparison, etc.)
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rohd/rohd.dart';
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

  /// Converts this vector into a SystemVerilog check.
  String toTbVerilog(Module module) =>
      _SystemVerilogVectorTestbench(this, module).toTbVerilog();
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
  }) =>
      _SystemVerilogSimCompare.checkIverilogVector(
        module,
        vectors,
        moduleName: moduleName,
        dontDeleteTmpFiles: dontDeleteTmpFiles,
        dumpWaves: dumpWaves,
        iverilogExtraArgs: iverilogExtraArgs,
        allowWarnings: allowWarnings,
        maskKnownWarnings: maskKnownWarnings,
        enableChecking: enableChecking,
        buildOnly: buildOnly,
        synthesizerConfiguration: synthesizerConfiguration,
      );

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
  }) =>
      _SystemVerilogSimCompare.iverilogVector(
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

  /// Cleans up all cached SystemC executables and the precompiled header.
  /// Call from `tearDownAll` in tests.
  ///
  /// If [keepPch] is true (the default), the precompiled header is preserved
  /// for faster subsequent runs. Pass `keepPch: false` to remove everything.
  static void cleanupSystemCCache({bool keepPch = true}) =>
      _SystemCSimCompare.cleanupSystemCCache(keepPch: keepPch);

  /// Compiles a SystemC module into a reusable stdin-driven executable.
  ///
  /// Returns a [SystemCExecutable] that can be used to run multiple vector
  /// sets without recompilation. Use in `setUpAll` for test groups.
  /// Results are cached — calling this with the same module definition
  /// returns the previously compiled binary.
  static SystemCExecutable? buildSystemCExecutable(
    Module module, {
    String? moduleName,
    String? clockName,
    String? resetName,
    String? systemcHome,
    String? systemcLib,
  }) =>
      _SystemCSimCompare.buildSystemCExecutable(
        module,
        moduleName: moduleName,
        clockName: clockName,
        resetName: resetName,
        systemcHome: systemcHome,
        systemcLib: systemcLib,
      );

  /// Runs [vectors] against a pre-compiled [SystemCExecutable].
  ///
  /// Returns `true` if all vectors pass.
  static bool runSystemCVectors(SystemCExecutable exe, List<Vector> vectors) =>
      _SystemCSimCompare.runSystemCVectors(exe, vectors);

  /// Convenience: runs [vectors] against a pre-compiled executable and
  /// asserts the result.
  static void checkSystemCVectors(
          SystemCExecutable exe, List<Vector> vectors) =>
      _SystemCSimCompare.checkSystemCVectors(exe, vectors);

  /// Executes [vectors] against a SystemC simulator compiled with g++ and
  /// checks that it passes (single-shot, compiles each time).
  static void checkSystemCVector(Module module, List<Vector> vectors,
          {String? moduleName,
          bool dontDeleteTmpFiles = false,
          String? clockName,
          String? resetName,
          String? systemcHome,
          String? systemcLib,
          bool buildOnly = false}) =>
      _SystemCSimCompare.checkSystemCVector(module, vectors,
          moduleName: moduleName,
          dontDeleteTmpFiles: dontDeleteTmpFiles,
          clockName: clockName,
          resetName: resetName,
          systemcHome: systemcHome,
          systemcLib: systemcLib,
          buildOnly: buildOnly);

  /// Legacy API — returns bool.
  static bool systemcVector(
    Module module,
    List<Vector> vectors, {
    String? moduleName,
    bool dontDeleteTmpFiles = false,
    String? clockName,
    String? resetName,
    String? systemcHome,
    String? systemcLib,
    bool buildOnly = false,
  }) =>
      _SystemCSimCompare.systemcVector(
        module,
        vectors,
        moduleName: moduleName,
        dontDeleteTmpFiles: dontDeleteTmpFiles,
        clockName: clockName,
        resetName: resetName,
        systemcHome: systemcHome,
        systemcLib: systemcLib,
        buildOnly: buildOnly,
      );

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
  static Future<bool> systemcSimCompare(
    Module module,
    Logic clk, {
    required Future<void> Function() stimulus,
    List<String>? inputNames,
    List<String>? outputNames,
    String? clockName,
    String? resetName,
    bool dontDeleteTmpFiles = false,
    String? systemcHome,
    String? systemcLib,
  }) =>
      _SystemCSimCompare.systemcSimCompare(
        module,
        clk,
        stimulus: stimulus,
        inputNames: inputNames,
        outputNames: outputNames,
        clockName: clockName,
        resetName: resetName,
        dontDeleteTmpFiles: dontDeleteTmpFiles,
        systemcHome: systemcHome,
        systemcLib: systemcLib,
      );
}
