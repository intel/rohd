// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank_tracer_test.dart
// Smoke-test: run SourceTracer on the FilterBank example and write
// a clickable hierarchy report to build/filter_bank_traces.txt.
//
// 2026 May 6
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../example/filter_bank/filter_bank_modules.dart';

void main() {
  final packageRoot = Directory.current.path;

  tearDown(() async {
    await Simulator.reset();
    SourceTracer.clear();
  });

  test('trace FilterBank and write clickable report', () async {
    const dataWidth = 16;
    const numTaps = 3;

    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final start = Logic(name: 'start');
    final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
    final inputDone = Logic(name: 'inputDone');

    // ── Enable tracing before build ──
    SourceTracer.activate();

    final dut = FilterBank(
      clk,
      reset,
      start,
      samples,
      inputDone,
      numTaps: numTaps,
      dataWidth: dataWidth,
      coefficients: [
        [1, 2, 1],
        [1, -2, 1],
      ],
    );

    await dut.build();

    // ── Generate the clickable report ──
    final report = SourceTracer.hierarchyReport(dut, packageRoot: packageRoot);

    // Write plain-text report for terminal use (path:line:col links)
    final txtFile = File('build/filter_bank_traces.txt');
    txtFile.parent.createSync(recursive: true);
    txtFile.writeAsStringSync(report);

    // Write file:// URI report for VS Code editor use
    final editorReport = SourceTracer.hierarchyReport(
      dut,
      packageRoot: packageRoot,
      useFileUris: true,
    );
    final editorFile = File('build/filter_bank_traces_editor.txt')
      ..writeAsStringSync(editorReport);

    // Write HTML report for scrollable clickable viewing
    final htmlReport = SourceTracer.htmlReport(dut, packageRoot: packageRoot);
    final htmlFile = File('build/filter_bank_traces.html')
      ..writeAsStringSync(htmlReport);

    expect(txtFile.existsSync(), isTrue);
    expect(editorFile.existsSync(), isTrue);
    expect(htmlFile.existsSync(), isTrue);

    // ── Assertions ──
    expect(report, contains('FilterBank.'));
    expect(report, contains('filter_bank/filter_bank.dart'));
    expect(report, contains('Total traced objects:'));

    expect(htmlReport, contains('vscode://file'));
    expect(htmlReport, contains('FilterBank.'));

    // Should NOT contain framework noise
    expect(report, isNot(contains('source_tracer.dart')));
    expect(report, isNot(contains('package:test_api')));
  });

  test('SV output contains trace comments when tracing enabled', () async {
    const dataWidth = 16;
    const numTaps = 3;

    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final start = Logic(name: 'start');
    final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
    final inputDone = Logic(name: 'inputDone');

    SourceTracer.activate();

    final dut = FilterBank(
      clk,
      reset,
      start,
      samples,
      inputDone,
      numTaps: numTaps,
      dataWidth: dataWidth,
      coefficients: [
        [1, 2, 1],
        [1, -2, 1],
      ],
    );

    await dut.build();

    final sv = SystemVerilogService(dut, register: false).synthOutput;

    final svFile = File('build/FilterBank.traced.sv');
    svFile.parent.createSync(recursive: true);
    svFile.writeAsStringSync(sv);
    expect(svFile.existsSync(), isTrue);

    // Should contain file index comments
    expect(sv, contains('// Source files:'));
    expect(sv, contains('//   0:'));

    // Should contain ROHD trace comments on declarations
    expect(sv, contains('// ROHD:'));

    // Delta encoding: repeated traces should produce ^
    expect(sv, contains('// ROHD: ^'));
  });

  test('netlist JSON contains trace attributes when tracing enabled', () async {
    const dataWidth = 16;
    const numTaps = 3;

    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final start = Logic(name: 'start');
    final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
    final inputDone = Logic(name: 'inputDone');

    SourceTracer.activate();

    final dut = FilterBank(
      clk,
      reset,
      start,
      samples,
      inputDone,
      numTaps: numTaps,
      dataWidth: dataWidth,
      coefficients: [
        [1, 2, 1],
        [1, -2, 1],
      ],
    );

    await dut.build();

    // ── Synthesize with packageRoot to inject traces ──
    final json = NetlistSynthesizer().synthesizeToJson(
      dut,
      packageRoot: packageRoot,
    );

    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final modules = decoded['modules'] as Map<String, dynamic>;

    // Write for inspection
    final file = File('build/FilterBank.traced.rohd.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(json);
    expect(file.existsSync(), isTrue);

    // The netlist-wide file dictionary lives at the top level, shared by
    // every module's rohd.src_trace attribute (see
    // doc/netlist_json_format.md) — not embedded per module.
    expect(decoded, contains('files'));
    final files = decoded['files'] as List<dynamic>;
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(f, isA<String>());
      // Should be relative paths, not absolute
      expect(
        f.toString().startsWith('/'),
        isFalse,
        reason: 'File paths should be relative: $f',
      );
    }

    // At least one module should have trace attributes
    final modulesWithTraces = modules.values
        .cast<Map<String, dynamic>>()
        .where(
          (m) =>
              (m['attributes'] as Map<String, dynamic>?)?.containsKey(
                'rohd.src_trace',
              ) ??
              false,
        )
        .toList();
    expect(
      modulesWithTraces,
      isNotEmpty,
      reason: 'At least one module should have rohd.src_trace',
    );

    // Check the structure of a trace attribute — no per-module `files`
    // key: frame file indices resolve against the shared top-level list.
    final firstAttrs =
        modulesWithTraces.first['attributes'] as Map<String, dynamic>;
    final traceAttr = firstAttrs['rohd.src_trace'] as Map<String, dynamic>;
    expect(
      traceAttr,
      isNot(contains('files')),
      reason: 'Per-module files list is replaced by the shared top-level '
          'dictionary',
    );
    expect(
      traceAttr.keys.any((k) => k == 'signals' || k == 'instances'),
      isTrue,
      reason: 'Trace should have signals and/or instances',
    );

    // Verify frame structure: each frame is "fileIndex:line[:col]", where
    // fileIndex resolves against the shared top-level `files` list.
    final section = (traceAttr['signals'] ?? traceAttr['instances'])
        as Map<String, dynamic>;
    final firstEntry = section.values.first as List;
    final firstFrame = firstEntry.first as String;
    final parts = firstFrame.split(':');
    expect(
      parts.length,
      greaterThanOrEqualTo(2),
      reason: 'Frame should have at least fileIndex:line',
    );
    final fileIndex = int.tryParse(parts[0]);
    expect(fileIndex, isNotNull, reason: 'First field should be a file index');
    expect(
      fileIndex,
      lessThan(files.length),
      reason: 'File index should resolve into the shared top-level files '
          'list',
    );
    expect(
      int.tryParse(parts[1]),
      isNotNull,
      reason: 'Second field should be a line number',
    );
  });

  test('NetlistService with trace option embeds FLC attributes', () async {
    const dataWidth = 16;
    const numTaps = 3;

    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final start = Logic(name: 'start');
    final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
    final inputDone = Logic(name: 'inputDone');

    SourceTracer.activate();

    final dut = FilterBank(
      clk,
      reset,
      start,
      samples,
      inputDone,
      numTaps: numTaps,
      dataWidth: dataWidth,
      coefficients: [
        [1, 2, 1],
        [1, -2, 1],
      ],
    );

    await dut.build();

    // ── Use NetlistService with trace option ──
    final netlist = NetlistService(
      dut,
      configuration: const NetlistSynthesizerConfiguration(trace: true),
      register: false,
    );

    final decoded = jsonDecode(netlist.json) as Map<String, dynamic>;
    final modules = decoded['modules'] as Map<String, dynamic>;

    // The netlist-wide file dictionary is at the top level, shared by
    // every module's rohd.src_trace attribute.
    expect(decoded, contains('files'));
    expect(decoded['files'], isA<List<dynamic>>());
    expect(decoded['files'], isNotEmpty);

    // At least one module should have rohd.src_trace attributes.
    final modulesWithTraces = modules.values
        .cast<Map<String, dynamic>>()
        .where(
          (m) =>
              (m['attributes'] as Map<String, dynamic>?)?.containsKey(
                'rohd.src_trace',
              ) ??
              false,
        )
        .toList();
    expect(
      modulesWithTraces,
      isNotEmpty,
      reason: 'At least one module should have rohd.src_trace',
    );

    // FLC hierarchy should be available via the service.
    // ignore: deprecated_member_use_from_same_package
    final flcHierarchy = netlist.flcHierarchy;
    expect(flcHierarchy, isNotNull);
    expect(flcHierarchy!['version'], equals(5));
    expect(flcHierarchy['files'], isA<List<dynamic>>());
    expect(flcHierarchy['modules'], isA<Map<String, dynamic>>());

    // Per-module querying should work, and standalone per-module JSON
    // should re-embed the shared files dictionary so the module's
    // rohd.src_trace frames remain resolvable on their own.
    for (final name in netlist.moduleNames) {
      final moduleJson = netlist.moduleJson(name);
      final modDecoded = jsonDecode(moduleJson) as Map<String, dynamic>;
      final modules = modDecoded['modules'] as Map<String, dynamic>?;
      expect(
        modules,
        isNotNull,
        reason: 'moduleJson output should have a "modules" key.',
      );
      expect(
        modules!.containsKey(name),
        isTrue,
        reason: '"modules" should contain the queried module "$name".',
      );
      final modAttrs = (modules[name] as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>?;
      if (modAttrs?.containsKey('rohd.src_trace') ?? false) {
        expect(
          modDecoded,
          contains('files'),
          reason: 'moduleJson for a traced module must re-embed the '
              'shared files dictionary so its trace frames remain '
              'resolvable standalone.',
        );
      }
    }
  });
}
