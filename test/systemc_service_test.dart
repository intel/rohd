// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemc_service_test.dart
// Tests SystemC service multi-file output support.

@TestOn('vm')
library;

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/simcompare.dart';
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

class _ExternalLeaf extends ExternalSystemVerilogModule {
  _ExternalLeaf(Logic dataIn, {required super.name})
      : super(definitionName: 'ExternalLeaf') {
    addInput('dataIn', dataIn, width: 8);
    addOutput('dataOut', width: 8);
  }
}

class _UnsupportedTop extends Module {
  _UnsupportedTop() : super(name: 'unsupportedTop') {
    final dataIn = addInput('dataIn', Logic(width: 8), width: 8);
    final accepted = _ExternalLeaf(dataIn, name: 'accepted');
    final rejected = _ExternalLeaf(dataIn, name: 'rejected');
    addOutput('acceptedOutput', width: 8) <= accepted.output('dataOut');
    addOutput('rejectedOutput', width: 8) <= rejected.output('dataOut');
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

  test(
    'SystemCService is a CodeGenService and registers with ModuleServices',
    () async {
      final top = _Top(Logic(width: 8), Logic(width: 8));
      await top.build();

      final sc = SystemCService(top);
      expect(sc, isA<CodeGenService>());
      expect(ModuleServices.instance.lookup<SystemCService>(), same(sc));
      expect(SystemCService.current, same(sc));
    },
  );

  test(
    'SystemCService output carries the SystemC header and module text',
    () async {
      final top = _Top(Logic(width: 8), Logic(width: 8));
      await top.build();

      final sc = SystemCService(top, register: false);
      expect(sc.output, contains('#include <systemc.h>'));
      expect(sc.output, contains('SC_MODULE(Top)'));
      expect(ModuleServices.instance.lookup<SystemCService>(), isNull);
    },
  );

  test(
    'SystemCService write() emits a directory of .sc files by default',
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
    },
  );

  test(
    'SystemCService write() with multiFile false emits a single file',
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
    },
  );

  test('unsupported SystemVerilog behavior is rejected by default', () async {
    final top = _UnsupportedTop();
    await top.build();

    expect(
      () => SystemCService(top, register: false),
      throwsA(
        isA<UnsupportedSystemCModuleException>()
            .having(
              (error) => error.module.runtimeType,
              'module type',
              _ExternalLeaf,
            )
            .having(
              (error) => error.reason,
              'reason',
              contains('SystemVerilog'),
            ),
      ),
    );
  });

  test('selective stubbing still rejects unselected instances', () async {
    final top = _UnsupportedTop();
    await top.build();

    expect(
      () => SystemCService(
        top,
        register: false,
        configuration: SystemCSynthesizerConfiguration(
          stubUnsupportedModule: (module, _) => module.name == 'accepted',
        ),
      ),
      throwsA(
        isA<UnsupportedSystemCModuleException>().having(
          (error) => error.module.name,
          'module instance',
          'rejected',
        ),
      ),
    );
  });

  test('blanket stubbing emits diagnostics and compilable definitions',
      () async {
    final top = _UnsupportedTop();
    await top.build();
    const configuration = SystemCSynthesizerConfiguration(
      stubAllUnsupportedModules: true,
    );

    final sc = SystemCService(
      top,
      register: false,
      configuration: configuration,
    );

    expect(sc.diagnostics, hasLength(2));
    expect(
      sc.diagnostics.map((diagnostic) => diagnostic.module.name),
      unorderedEquals(['accepted', 'rejected']),
    );
    expect(sc.output, contains('WARNING: Empty SystemC stub'));
    expect(sc.output, contains('TODO: Replace this stub'));
    expect(sc.output, contains('SC_MODULE(ExternalLeaf)'));
    expect(sc.output, contains('sc_in<sc_uint<8>> dataIn{"dataIn"};'));
    expect(sc.output, contains('sc_out<sc_uint<8>> dataOut{"dataOut"};'));
    expect(sc.output, contains('ExternalLeaf accepted{"accepted"};'));
    expect(sc.output, contains('accepted.dataIn(dataIn);'));
    expect(sc.output, contains('accepted.dataOut('));

    expect(
      SimCompare.checkSystemCVector(
        top,
        const [],
        synthesizerConfiguration: configuration,
      ),
      isTrue,
    );
  });
}
