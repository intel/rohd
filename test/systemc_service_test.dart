// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_service_test.dart
// Tests SystemC service multi-file output support.

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
  tearDown(ModuleServices.instance.reset);

  test('SystemCService exposes per-module SystemC files', () async {
    final a = Logic(name: 'a', width: 8);
    final b = Logic(name: 'b', width: 8);
    final top = _Top(a, b);
    await top.build();

    final sc = SystemCService(top);

    expect(sc.fileContents, isNotEmpty);
    expect(sc.scFileMap['Top'], contains('Top.sc'));
    expect(sc.scFileMap['Adder'], contains('Adder.sc'));
    expect(sc.contentsByDefinitionName['Top'], contains('SC_MODULE(Top)'));
    expect(sc.contentsByDefinitionName['Adder'], contains('SC_MODULE(Adder)'));

    final outDir = Directory.systemTemp.createTempSync('rohd_systemc_service_');
    try {
      sc.writeFiles(outDir.path);
      expect(File('${outDir.path}/Top.sc').existsSync(), isTrue);
      expect(File('${outDir.path}/Adder.sc').existsSync(), isTrue);
    } finally {
      outDir.deleteSync(recursive: true);
    }
  });

  test('SystemCService is a CodeGenService and registers with ModuleServices',
      () async {
    final top = _Top(Logic(width: 8), Logic(width: 8));
    await top.build();

    final sc = SystemCService(top);
    expect(sc, isA<CodeGenService>());
    expect(ModuleServices.instance.lookup<SystemCService>(), same(sc));
    expect(SystemCService.current, same(sc));
  });

  test('SystemCService output carries the SystemC header and module text',
      () async {
    final top = _Top(Logic(width: 8), Logic(width: 8));
    await top.build();

    final sc = SystemCService(top, register: false);
    expect(sc.output, contains('#include <systemc.h>'));
    expect(sc.output, contains('SC_MODULE(Top)'));
    expect(ModuleServices.instance.lookup<SystemCService>(), isNull);
  });

  test('SystemCService write() emits a directory of .sc files by default',
      () async {
    final top = _Top(Logic(width: 8), Logic(width: 8));
    await top.build();

    final dir = Directory.systemTemp.createTempSync('rohd_systemc_service_');
    try {
      SystemCService(top, register: false, outputPath: dir.path);
      final files = dir.listSync().whereType<File>().toList();
      expect(files.any((f) => f.path.endsWith('.sc')), isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('SystemCService write() with multiFile false emits a single file',
      () async {
    final top = _Top(Logic(width: 8), Logic(width: 8));
    await top.build();

    final sc = SystemCService(top, register: false, multiFile: false);
    final dir = Directory.systemTemp.createTempSync('rohd_systemc_service_');
    try {
      final path = '${dir.path}/out.cpp';
      sc.write(path);
      expect(File(path).readAsStringSync(), equals(sc.output));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
