// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// system_verilog_service_flc_test.dart
// Tests FLC line maps across SystemVerilog output layouts.
//
// 2026 July 19
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _FlcLeaf extends Module {
  Logic get y => output('y');

  _FlcLeaf(Logic a) : super(name: 'flcLeaf') {
    a = addInput('a', a);
    addOutput('y') <= ~a;
  }
}

class _FlcTop extends Module {
  _FlcTop(Logic a) : super(name: 'flcTop') {
    a = addInput('a', a);
    addOutput('y') <= _FlcLeaf(a).y;
  }
}

class _FlcWideLeaf extends Module {
  _FlcWideLeaf(Logic data) : super(name: 'flcWideLeaf') {
    data = addInput('data', data, width: 4);
    addOutput('result', width: 4) <= ~data;
  }
}

class _FlcWideTop extends Module {
  _FlcWideTop() : super(name: 'flcWideTop') {
    final data = addInput('data', Logic(width: 4), width: 4);
    final result = _FlcWideLeaf(data).output('result');
    addOutput('low', width: 2) <= result.getRange(0, 2);
    addOutput('high', width: 2) <= result.getRange(2, 4);
  }
}

class _SpecializedVariant extends Module {
  Logic get y => output('y');

  _SpecializedVariant(
    Logic a,
    int variant, {
    required super.name,
  }) : super(definitionName: 'Variant') {
    a = addInput('a', a);
    addOutput('y') <= (variant == 1 ? a : ~a);
  }
}

class _SpecializedVariantTop extends Module {
  late final _SpecializedVariant first;
  late final _SpecializedVariant second;

  _SpecializedVariantTop() : super(name: 'specializedVariantTop') {
    final a = addInput('a', Logic());
    first = _SpecializedVariant(a, 1, name: 'first');
    second = _SpecializedVariant(a, 2, name: 'second');
    addOutput('firstY') <= first.y;
    addOutput('secondY') <= second.y;
  }
}

class _SharedVariant extends Module {
  Logic get y => output('y');

  _SharedVariant(Logic a, {required super.name})
      : super(definitionName: 'SharedVariant') {
    a = addInput('a', a);
    addOutput('y') <= ~a;
  }
}

class _SharedVariantTop extends Module {
  late final _SharedVariant first;
  late final _SharedVariant second;

  _SharedVariantTop() : super(name: 'sharedVariantTop') {
    final a = addInput('a', Logic());
    first = _SharedVariant(a, name: 'first');
    second = _SharedVariant(a, name: 'second');
    addOutput('firstY') <= first.y;
    addOutput('secondY') <= second.y;
  }
}

void _expectLineMapsResolve(
  Map<String, Map<String, List<String>>> lineMaps,
  Map<String, String> contents,
) {
  var positionCount = 0;
  for (final moduleEntry in lineMaps.entries) {
    final lines = contents[moduleEntry.key]!.split('\n');
    for (final symbolEntry in moduleEntry.value.entries) {
      for (final position in symbolEntry.value) {
        final separator = position.indexOf(':');
        final lineNumber = int.parse(position.substring(0, separator));
        final column = int.parse(position.substring(separator + 1));
        expect(lineNumber, inInclusiveRange(1, lines.length));

        final line = lines[lineNumber - 1];
        final columnIndex = column - 1;
        expect(
          (columnIndex >= 0 &&
                  columnIndex < line.length &&
                  line.substring(columnIndex).startsWith(symbolEntry.key)) ||
              line.contains(symbolEntry.key) ||
              line.trimLeft().startsWith('assign '),
          isTrue,
          reason: '${moduleEntry.key}.${symbolEntry.key} at $position: $line',
        );
        positionCount++;
      }
    }
  }
  expect(positionCount, greaterThan(0));
}

Iterable<String> _trieSymbols(Object node) sync* {
  if (node is! List<Object>) {
    return;
  }
  for (final entry in node.skip(1)) {
    if (entry is List<Object>) {
      yield* _trieSymbols(entry);
    } else if (entry is String) {
      yield entry;
    }
  }
}

void main() {
  tearDown(() {
    ModuleServices.instance.reset();
    SourceTracer.clear();
  });

  test('FLC line maps resolve for every SV header and file layout', () async {
    SourceTracer.activate();
    final dut = _FlcTop(Logic());
    await dut.build();
    final directory = Directory.systemTemp.createTempSync('sv_flc_layout_');
    try {
      for (final multiFile in [false, true]) {
        for (final includeHeader in [false, true]) {
          final service = SystemVerilogService(
            dut,
            register: false,
            multiFile: multiFile,
            includeHeader: includeHeader,
          );
          final trace = TraceService(
            dut,
            svService: service,
            register: false,
            svOutputMode:
                multiFile ? SvOutputMode.perModule : SvOutputMode.singleFile,
          );
          final outputPath = '${directory.path}/$multiFile-$includeHeader.sv';
          service.write(outputPath);

          final contents = <String, String>{
            for (final result in service.synthesisResults)
              result.module.definitionName: multiFile
                  ? File('$outputPath/${result.instanceTypeName}.sv')
                      .readAsStringSync()
                  : File(outputPath).readAsStringSync(),
          };
          _expectLineMapsResolve(
            multiFile ? trace.svLineMaps : trace.singleFileSvLineMaps,
            contents,
          );
        }
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test('FLC line maps handle split packed submodule outputs', () async {
    SourceTracer.activate();
    final dut = _FlcWideTop();
    await dut.build();

    final service = SystemVerilogService(dut, register: false);
    final trace = TraceService(dut, svService: service, register: false);
    final topLineMap = trace.singleFileSvLineMaps[dut.definitionName]!;

    expect(topLineMap['low']!.length, greaterThan(1));
    expect(topLineMap['high']!.length, greaterThan(1));
    expect(
      SystemCService(dut, register: false).synthesisResults,
      isNotEmpty,
    );
  });

  test(
    'FLC associates duplicate requested names with their specialized '
    'generated implementations',
    () async {
      SourceTracer.activate();
      final dut = _SpecializedVariantTop();
      await dut.build();

      final sv = SystemVerilogService(
        dut,
        register: false,
        multiFile: true,
      );
      final sc = SystemCService(dut, register: false);
      final trace = TraceService(
        dut,
        svService: sv,
        scService: sc,
        register: false,
        svOutputMode: SvOutputMode.perModule,
        scOutputMode: ScOutputMode.perModule,
      );

      final firstType = sv.synthBuilder.instanceTypeOf(dut.first)!;
      final secondType = sv.synthBuilder.instanceTypeOf(dut.second)!;
      final firstScType = sc.instanceTypeOf(dut.first)!;
      final secondScType = sc.instanceTypeOf(dut.second)!;
      expect(firstType, isNot(secondType));
      expect(sv.instanceTypeOutput(firstType),
          isNot(sv.instanceTypeOutput(secondType)));
      expect(trace.svFileMap[firstType], '$firstType.sv');
      expect(trace.svFileMap[secondType], '$secondType.sv');
      expect(trace.svLineMaps[firstType], isNotNull);
      expect(trace.svLineMaps[secondType], isNotNull);

      final hierarchy = trace.flcHierarchy!;
      final modules = hierarchy['modules']! as Map<String, Object>;
      expect(modules.keys, containsAll([firstType, secondType]));

      for (final variant in [
        (
          module: dut.first,
          svType: firstType,
          scType: firstScType,
        ),
        (
          module: dut.second,
          svType: secondType,
          scType: secondScType,
        ),
      ]) {
        final entry = modules[variant.svType]! as Map<String, Object>;
        expect(entry['implementationName'], variant.svType);

        final occurrences = (entry['sourceOccurrences']! as List<Object>)
            .cast<Map<String, Object>>();
        expect(occurrences, hasLength(1));
        expect(occurrences.single['definitionName'], 'Variant');
        expect(occurrences.single['path'], variant.module.hierarchicalName);

        final outputFiles = entry['outputFiles']! as Map<String, Object>;
        expect(
          (outputFiles['sv']! as List<Object>).cast<String>(),
          ['${variant.svType}.sv'],
        );
        expect(
          (outputFiles['sc']! as List<Object>).cast<String>(),
          ['${variant.scType}.sc'],
        );

        _expectLineMapsResolve(
          {variant.svType: trace.svLineMapsByModule[variant.module]!},
          {variant.svType: sv.instanceTypeOutput(variant.svType)!},
        );
      }
    },
  );

  test(
    'FLC retains distinct source occurrences that share an implementation',
    () async {
      SourceTracer.activate();
      final dut = _SharedVariantTop();
      await dut.build();

      final sv = SystemVerilogService(
        dut,
        register: false,
        multiFile: true,
      );
      final trace = TraceService(
        dut,
        svService: sv,
        register: false,
        svOutputMode: SvOutputMode.perModule,
      );

      final firstType = sv.synthBuilder.instanceTypeOf(dut.first)!;
      final secondType = sv.synthBuilder.instanceTypeOf(dut.second)!;
      expect(firstType, secondType);
      expect(trace.svFileMap[firstType], '$firstType.sv');
      expect(
        SourceTracer.moduleTrace(dut.first),
        isNot(equals(SourceTracer.moduleTrace(dut.second))),
      );

      final hierarchy = trace.flcHierarchy!;
      final modules = hierarchy['modules']! as Map<String, Object>;
      final sharedEntry = modules[firstType]! as Map<String, Object>;
      expect(sharedEntry['implementationName'], firstType);

      final occurrences = (sharedEntry['sourceOccurrences']! as List<Object>)
          .cast<Map<String, Object>>();
      expect(
        occurrences.map((occurrence) => occurrence['path']),
        containsAll([dut.first.hierarchicalName, dut.second.hierarchicalName]),
      );

      final outputFiles = sharedEntry['outputFiles']! as Map<String, Object>;
      expect(
        (outputFiles['sv']! as List<Object>).cast<String>(),
        ['$firstType.sv'],
      );
      expect(
        trace.svLineMapsByModule[dut.first],
        equals(trace.svLineMapsByModule[dut.second]),
      );

      final topType = sv.synthBuilder.instanceTypeOf(dut)!;
      final topEntry = modules[topType]! as Map<String, Object>;
      final symbols = <String>[
        for (final root in topEntry['tree']! as List<Object>)
          ..._trieSymbols(root),
      ];
      expect(symbols, contains(startsWith('*${dut.first.uniqueInstanceName}')));
      expect(
          symbols, contains(startsWith('*${dut.second.uniqueInstanceName}')));
    },
  );
}
