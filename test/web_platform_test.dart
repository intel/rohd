// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// web_platform_test.dart
// Cross-platform web detection and integer behavior tests.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/web.dart';
import 'package:test/test.dart';

class _Inverter extends Module {
  _Inverter(Logic input) {
    input = addInput('a', input);
    addOutput('out') <= ~input;
  }
}

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
    WaveformDataService.instance.clear();
  });

  test('web targets retain correct integer behavior', () {
    // The test checks the compiler's platform declaration.
    // ignore: do_not_use_environment
    expect(kIsWeb, const bool.fromEnvironment('dart.library.js_interop'));
    expect(INT_BITS, kIsJs ? 32 : 64);
    expect(oneSllBy(40), 1099511627776);

    final value = (BigInt.one << 63) | BigInt.from(42);
    expect(LogicValue.ofBigInt(value, 64).toBigInt(), value);
  });

  test('package configuration file access is explicit on web', () {
    if (kIsWeb) {
      expect(() => SourceTracer.loadPackageMap('.'), throwsUnsupportedError);
    } else {
      expect(SourceTracer.loadPackageMap('.'), contains('rohd'));
      expect(SourceTracer.loadPackageMap('missing-package-root'), isEmpty);
    }
  });

  test('web rejects file capture but supports in-memory waveforms', () async {
    final input = Logic();
    final module = _Inverter(input);
    await module.build();

    if (kIsWeb) {
      expect(
        () => WaveformService(module, writeToFile: true),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('File-backed waveform capture is unavailable'),
          ),
        ),
      );
    }

    final waves = WaveformService(
      module,
      register: false,
      enableDevToolsStreaming: true,
    );
    input.inject(1);
    await Simulator.run();
    expect(module.output('out').value, LogicValue.zero);
    expect(waves.inMemoryOutput, contains(r'$enddefinitions'));
    expect(module.dumpSystemVerilog(), contains('module'));
  });
}
