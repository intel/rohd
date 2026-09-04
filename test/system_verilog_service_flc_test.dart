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
}
