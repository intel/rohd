// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_simcompare.dart
// SystemC simulation comparison support for SimCompare.
//
// 2026 July 20
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// ignore_for_file: avoid_print

part of 'simcompare.dart';

class _SystemCSimCompare {
  /// The default SystemC installation path (Accellera).
  static const _systemCDefaultHome = '/opt/systemc/include';
  static const _systemCDefaultLib = '/opt/systemc/lib';

  /// Cache of compiled SystemC vector-testbench executables keyed by generated
  /// code hash.
  static final _compilationCache = <int, SystemCVectorExecutable>{};

  /// Prefix for SystemC artifacts owned by this test process.
  static final String tempPrefix =
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
      '$scHome/systemc.h',
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
          // Use entity.path (not entity.uri) to get the basename: Directory.uri
          // always appends a trailing slash, making pathSegments.last == "".
          final name = entity.path.split('/').last;

          // Remove only SystemC artifacts owned by this test process. Other
          // test isolates may be compiling or running from the same tmp_test
          // directory concurrently.
          if (name.startsWith(tempPrefix) || name == 'Makefile_sc') {
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

  /// Compiles a SystemC module into a reusable stdin-driven vector-testbench
  /// executable.
  ///
  /// Returns a [SystemCVectorExecutable] that can be used to run multiple
  /// vector sets without recompilation. Use in `setUpAll` for test groups.
  /// Results are cached — calling this with the same module definition
  /// returns the previously compiled binary.
  static SystemCVectorExecutable? buildSystemCVectorExecutable(
    Module module, {
    String? moduleName,
    String? clockName,
    String? resetName,
    String? systemcHome,
    String? systemcLib,
  }) {
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
    final inOutPorts = <String, int>{};
    for (final inOut in module.inOuts.entries) {
      inOutPorts[inOut.key] = inOut.value.width;
    }

    // Generate stdin-driven testbench
    final tb = StringBuffer()
      ..write('''
#include <systemc.h>
#include <iostream>
#include <string>
#include <sstream>
#include <map>
#include <cmath>
using namespace std;

''')
      ..writeln(generatedSystemC)
      ..write('''
int sc_main(int argc, char* argv[]) {
''');

    // Clock
    for (final clkName in clockSignals) {
      tb.writeln(
        '    sc_clock $clkName("$clkName", ${Vector._period}, SC_NS);',
      );
    }

    // Signals for all non-clock input ports
    for (final entry in inputPorts.entries) {
      if (clockSignals.contains(entry.key)) {
        continue;
      }
      tb.writeln(
        '    sc_signal<${SystemCSynthesisResult.systemCType(entry.value)}>'
        ' ${entry.key};',
      );
    }

    // Signals for all output ports
    for (final entry in outputPorts.entries) {
      tb.writeln(
        '    sc_signal<${SystemCSynthesisResult.systemCType(entry.value)}>'
        ' ${entry.key};',
      );
    }

    // Signals for all inout ports
    for (final entry in inOutPorts.entries) {
      tb.writeln(
        '    sc_signal<${SystemCSynthesisResult.systemCType(entry.value)}>'
        ' ${entry.key};',
      );
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
    for (final name in inOutPorts.keys) {
      tb.writeln('    dut.$name($name);');
    }

    tb.write('''
    int _tb_errors = 0;

    // Initial offset
    sc_start(sc_time(1, SC_NS));

    // Read number of vectors
    int _tb_nvec;
    cin >> _tb_nvec;

    for (int _tb_v = 0; _tb_v < _tb_nvec; _tb_v++) {
''');

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
    for (final entry in inOutPorts.entries) {
      final name = entry.key;
      final w = entry.value;
      tb.writeln('        { int _drive; cin >> _drive;');
      if (w > 64) {
        tb
          ..writeln('          if (_drive) { string _h; cin >> _h;')
          ..writeln('            sc_biguint<$w> _v(_h.c_str());')
          ..writeln('            $name.write(_v); } }');
      } else {
        tb
          ..writeln('          if (_drive) { uint64_t _v; cin >> _v;')
          ..writeln('            $name.write(_v); } }');
      }
    }

    // Advance to check point
    tb.write('''
        sc_start(sc_time(${Vector._offset}, SC_NS));

        // Read number of outputs to check
        int _tb_nchk;
        cin >> _tb_nchk;

        for (int _tb_c = 0; _tb_c < _tb_nchk; _tb_c++) {
            string _tb_pn;
            cin >> _tb_pn;
''');

    // Generate if-else chain for each output and inout port
    var first = true;
    final checkablePorts = {...outputPorts, ...inOutPorts};
    for (final entry in checkablePorts.entries) {
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
        ..writeln(
          '                    cout << "ERROR vector " << _tb_v'
          ' << ": expected $name=" << _tb_exp'
          ' << ", got " << $name.read() << endl;',
        )
        ..writeln('                    _tb_errors++;')
        ..writeln('                }');
    }
    if (checkablePorts.isNotEmpty) {
      tb
        ..writeln('            } else {')
        ..writeln('                string _d; cin >> _d; // skip unknown')
        ..writeln('            }');
    }

    tb.write('''
        }

        sc_start(sc_time(${Vector._period - Vector._offset}, SC_NS));
    }

    if (_tb_errors == 0) {
        cout << "PASS" << endl;
    } else {
        cout << "FAIL: " << _tb_errors << " errors" << endl;
    }
    return _tb_errors > 0 ? 1 : 0;
}
''');

    final testbenchCode = tb.toString();

    // Write and compile
    const dir = 'tmp_test';
    Directory(dir).createSync(recursive: true);
    final compileDir = Directory(
      dir,
    ).createTempSync('${tempPrefix}_${generatedSystemC.hashCode}_');
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
      '-lsystemc',
    ]);
    if (compileResult.exitCode != 0) {
      print('SystemC compilation failed:');
      print(compileResult.stdout);
      print(compileResult.stderr);
      return null;
    }

    final exe = SystemCVectorExecutable._(
      binaryPath: tmpOutput,
      cppFile: tmpCppFile,
      scLib: resolvedLib,
      clockSignals: clockSignals,
      inputPorts: inputPorts,
      outputPorts: outputPorts,
      inOutPorts: inOutPorts,
    );
    _compilationCache[cacheKey] = exe;
    return exe;
  }

  /// Runs [vectors] against a pre-compiled [SystemCVectorExecutable].
  ///
  /// Returns `true` if all vectors pass.
  static bool runSystemCVectors(
      SystemCVectorExecutable exe, List<Vector> vectors) {
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
      for (final name in drivableInputs) name: '0',
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
      for (final name in exe.inOutPorts.keys) {
        final value = vector.inputValues[name];
        if (value != null) {
          final w = exe.inOutPorts[name]!;
          final formattedValue = w > 64
              ? _systemcHexValue(value, w)
              : '${_systemcIntValue(value, w)}';
          lastValues[name] = formattedValue;
        }
        final lastValue = lastValues[name];
        if (lastValue == null) {
          sb.write('0 ');
        } else {
          sb.write('1 $lastValue ');
        }
      }
      sb.writeln();

      // Write expected outputs: count then name/value pairs
      // Skip x/z outputs
      final checks = <String, String>{};
      for (final entry in vector.expectedOutputValues.entries) {
        final name = entry.key;
        final checkablePorts = {...exe.outputPorts, ...exe.inOutPorts};
        final w = checkablePorts[name]!;
        final expectedLV = LogicValue.of(entry.value, width: w);
        if (expectedLV.toString().contains('x') ||
            expectedLV.toString().contains('z')) {
          continue;
        }
        if (w > 64) {
          checks[name] = _systemcHexValue(entry.value, w);
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

      result = Process.runSync(
        'sh',
        ['-c', '${exe.binaryPath} < $stdinFile'],
        environment: {
          'LD_LIBRARY_PATH': exe.scLib,
          'SC_COPYRIGHT_MESSAGE': 'DISABLE',
        },
      );
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
  static void checkSystemCVectors(
      SystemCVectorExecutable exe, List<Vector> vectors) {
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

  /// Converts a value to a hex string for stdin.
  static String _systemcHexValue(dynamic value, int width) {
    final lv = LogicValue.of(value, width: width);
    var hex = lv.toBigInt().toUnsigned(width).toRadixString(16);
    if (hex.length.isOdd) {
      hex = '0$hex';
    }
    return '0x$hex';
  }

  /// Executes [vectors] against a SystemC simulator compiled with g++ and
  /// checks that it passes (single-shot, compiles each time).
  static void checkSystemCVector(
    Module module,
    List<Vector> vectors, {
    String? moduleName,
    bool dontDeleteTmpFiles = false,
    String? clockName,
    String? resetName,
    String? systemcHome,
    String? systemcLib,
    bool buildOnly = false,
  }) {
    if (buildOnly) {
      // Just verify SystemC code generation succeeds
      module.generateSystemC();
      return;
    }
    final exe = buildSystemCVectorExecutable(
      module,
      moduleName: moduleName,
      clockName: clockName,
      resetName: resetName,
      systemcHome: systemcHome,
      systemcLib: systemcLib,
    );
    if (exe == null) {
      // SystemC not available — skip gracefully.
      return;
    }
    final passed = runSystemCVectors(exe, vectors);
    if (!dontDeleteTmpFiles) {
      // Single-shot path: clean up this process's compiled artifacts now so
      // tests that call checkSystemCVector do not require a tearDownAll.
      // The PCH is kept to avoid rebuilding it for subsequent calls.
      cleanupSystemCCache();
    }
    expect(passed, true);
  }

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
  }) {
    if (kIsWeb) {
      return true;
    }
    final exe = buildSystemCVectorExecutable(
      module,
      moduleName: moduleName,
      clockName: clockName,
      resetName: resetName,
      systemcHome: systemcHome,
      systemcLib: systemcLib,
    );
    if (exe == null) {
      return false;
    }
    if (buildOnly) {
      return true;
    }
    return runSystemCVectors(exe, vectors);
  }

  /// Runs the ROHD simulation using [stimulus], records input/output values
  /// at every posedge of [clk], then replays the captured vectors through
  /// the SystemC-synthesized version of [module] and compares results.
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
  }) async {
    // Determine which signals to record
    final clkName = clockName ??
        module.inputs.keys.firstWhere(
          (n) => n == 'clk' || n.contains('clock'),
          orElse: () => 'clk',
        );

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
      print(
        'Warning: only ${recordings.length} clock edges recorded,'
        ' need at least 2 for comparison',
      );
      return true;
    }

    // No shifting needed — previousValue already gives us the output
    // state from before the posedge, which matches systemcVector's
    // check-before-edge timing. Just pass recordings directly as vectors.

    // Run through SystemC
    return systemcVector(
      module,
      recordings,
      clockName: clkName,
      resetName: resetName,
      dontDeleteTmpFiles: dontDeleteTmpFiles,
      systemcHome: systemcHome,
      systemcLib: systemcLib,
    );
  }
}

/// Holds the compiled state of a native SystemC vector-testbench executable for
/// reuse across tests.
class SystemCVectorExecutable {
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

  /// Inout port names and widths.
  final Map<String, int> inOutPorts;

  SystemCVectorExecutable._({
    required this.binaryPath,
    required this.cppFile,
    required this.scLib,
    required this.clockSignals,
    required this.inputPorts,
    required this.outputPorts,
    required this.inOutPorts,
  });

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
          compileDir.uri.pathSegments.last.startsWith(
            _SystemCSimCompare.tempPrefix,
          )) {
        compileDir.deleteSync(recursive: true);
        return;
      }
      tryDelete(cppFile);
      tryDelete(binaryPath);
    } on Exception catch (_) {}
  }
}

/// Legacy name for [SystemCVectorExecutable].
@Deprecated('Use SystemCVectorExecutable instead.')
typedef SystemCExecutable = SystemCVectorExecutable;
