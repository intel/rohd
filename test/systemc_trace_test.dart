// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_trace_test.dart
// Validates SystemC + SystemVerilog co-tracing: FLC v6 output emits both
// `sv:` and `sc:` per-language groups in symbol positions and
// `outputFiles`.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _Adder extends Module {
  _Adder(Logic a, Logic b) : super(name: 'adder', definitionName: 'Adder') {
    a = addInput('a', a, width: 8);
    b = addInput('b', b, width: 8);
    addOutput('y', width: 8) <= a + b;
  }
}

class _Top extends Module {
  _Top(Logic a, Logic b) : super(name: 'top', definitionName: 'Top') {
    a = addInput('a', a, width: 8);
    b = addInput('b', b, width: 8);
    final adder = _Adder(a, b);
    addOutput('y', width: 8) <= adder.output('y');
  }
}

void main() {
  tearDown(() {
    SourceTracer.clear();
    ModuleServices.instance.reset();
  });

  test(
    'TraceService aggregates SV + SC line maps into v6 FLC output',
    () async {
      // Tracer must be installed BEFORE module construction so that the
      // construction-site stack traces are captured.
      SourceTracer.activate();

      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final top = _Top(a, b);
      await top.build();

      final sv = SystemVerilogService(top, register: false);
      final sc = SystemCService(top, register: false);

      final trace = TraceService(
        top,
        svService: sv,
        scService: sc,
        register: false,
      );

      final hierarchy = trace.flcHierarchy;
      expect(
        hierarchy,
        isNotNull,
        reason: 'Tracer should have recorded construction stacks.',
      );

      expect(hierarchy!['version'], equals(6));

      final modules = hierarchy['modules']! as Map<String, Object>;
      expect(
        modules,
        isNotEmpty,
        reason: 'Hierarchy must include at least one module entry.',
      );

      // At least one module advertises outputFiles for both `sv` and `sc`.
      var sawCombined = false;
      for (final entry in modules.entries) {
        final mod = entry.value as Map<String, Object>;
        final outputFiles = mod['outputFiles'] as Map<String, Object>?;
        if (outputFiles == null) {
          continue;
        }
        if (outputFiles.containsKey('sv') && outputFiles.containsKey('sc')) {
          final svFiles = (outputFiles['sv']! as List).cast<String>();
          final scFiles = (outputFiles['sc']! as List).cast<String>();
          expect(svFiles, isNotEmpty);
          expect(scFiles, isNotEmpty);
          expect(scFiles, everyElement(endsWith('.sc')));
          sawCombined = true;
        }
      }
      expect(
        sawCombined,
        isTrue,
        reason: 'At least one module must list both sv and sc outputFiles.',
      );

      // At least one symbol carries both `sv:` and `sc:` groups in its
      // position string (e.g. `name@sv:L:C;sc:L:C`).
      final jsonStr = trace.flcJson;
      expect(
        jsonStr,
        contains('@'),
        reason: 'Symbol strings should carry @-encoded positions.',
      );
      expect(
        jsonStr,
        contains('sv:'),
        reason: 'Symbol strings should include the sv: language group.',
      );
      expect(
        jsonStr,
        contains('sc:'),
        reason: 'Symbol strings should include the sc: language group.',
      );

      // At least one symbol literally contains the combined group separator.
      expect(
        RegExp(r'@[^"\\]*sv:[^"\\;]+;[^"\\;]*sc:').hasMatch(jsonStr),
        isTrue,
        reason: 'At least one symbol must carry both sv and sc groups.',
      );
    },
  );

  test(
      'TraceService uses SystemVerilogService outputPath '
      'for single-file SV output', () async {
    SourceTracer.activate();

    final a = Logic(name: 'a', width: 8);
    final b = Logic(name: 'b', width: 8);
    final top = _Top(a, b);
    await top.build();

    final dir = Directory.systemTemp.createTempSync('flc_sv_path_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    final svPath = '${dir.path}/${top.definitionName}.sv';
    final sv = SystemVerilogService(
      top,
      register: false,
      outputDirectory: dir.path,
    )..write(svPath);
    final trace = TraceService(top, svService: sv, register: false);

    final hierarchy = trace.flcHierarchy;
    expect(hierarchy, isNotNull);
    final modules = hierarchy!['modules']! as Map<String, Object>;
    final topModule = modules['Top']! as Map<String, Object>;
    final outputFiles = topModule['outputFiles']! as Map<String, Object>;
    final svFiles = (outputFiles['sv']! as List).cast<String>();
    expect(svFiles, contains(File(svPath).absolute.path));
  });

  test('TraceService writes an exact JSON output path', () async {
    SourceTracer.activate();

    final a = Logic(name: 'a', width: 8);
    final b = Logic(name: 'b', width: 8);
    final top = _Top(a, b);
    await top.build();

    final dir = Directory.systemTemp.createTempSync('flc_exact_path_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    final flcPath = '${dir.path}/custom.flc.json';
    final trace = TraceService(top, register: false)..write(flcPath);

    expect(File(flcPath).existsSync(), isTrue);
    expect(trace.writtenPath, File(flcPath).absolute.path);
    expect(
      File('${dir.path}/${top.definitionName}.flc.json').existsSync(),
      isFalse,
    );
  });

  test(
    'SC line map records submodule output-port bindings as driver locations',
    () async {
      SourceTracer.activate();

      final a = Logic(name: 'a', width: 8);
      final b = Logic(name: 'b', width: 8);
      final top = _MidTop(a, b);
      await top.build();

      final sc = SystemCService(top, register: false);
      final lineMap = sc.scLineMaps['MidTop']!;

      // `mid` is driven solely by the adder's output port binding
      // (`adder.y(mid);`). Its line map must carry both the declaration and
      // the binding site — not just the declaration.
      final midPositions = lineMap['mid'];
      expect(midPositions, isNotNull);
      expect(
        midPositions!.length,
        greaterThanOrEqualTo(2),
        reason: 'mid should record its declaration and the submodule '
            'output-port binding site.',
      );

      // The submodule input bindings (`adder.a(a);`, `adder.b(b);`) must NOT
      // be recorded as drivers of the input ports `a`/`b`.
      expect(lineMap['a'], hasLength(1));
      expect(lineMap['b'], hasLength(1));
    },
  );
}

class _MidTop extends Module {
  _MidTop(Logic a, Logic b) : super(name: 'mid_top', definitionName: 'MidTop') {
    a = addInput('a', a, width: 8);
    b = addInput('b', b, width: 8);
    final adder = _Adder(a, b);
    final mid = Logic(name: 'mid', width: 8);
    mid <= adder.output('y');
    addOutput('y', width: 8) <= mid;
  }
}
