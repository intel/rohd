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

class _CustomInstantiation extends Module with SystemVerilog {
  _CustomInstantiation(Logic data) : super(name: 'customInstantiation') {
    data = addInput('data', data, width: 8);
    addOutput('q', width: 8) <= data;
  }

  @override
  String? definitionVerilog(String definitionType) => null;

  @override
  String? instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) =>
      'assign ${ports['q']} = ~${ports['data']};  // $instanceName';
}

class _CustomInstantiationTop extends Module {
  _CustomInstantiationTop() : super(name: 'customInstantiationTop') {
    final data = addInput('data', Logic(width: 8), width: 8);
    final custom = _CustomInstantiation(data);
    addOutput('q', width: 8) <= custom.output('q');
  }
}

void main() {
  tearDown(ModuleServices.instance.reset);

  test('SystemCService exposes per-module SystemC files', () async {
    final a = Logic(name: 'a', width: 8);
    final b = Logic(name: 'b', width: 8);
    final top = _Top(a, b);
    await top.build();

    final outDir = Directory.systemTemp.createTempSync('rohd_systemc_service_');
    try {
      final sc = SystemCService(top, outputDirectory: outDir.path);

      expect(sc.fileContents, isNotEmpty);
      expect(sc.scFileMap['Top'], contains('Top.sc'));
      expect(sc.scFileMap['Adder'], contains('Adder.sc'));
      expect(sc.contentsByDefinitionName['Top'], contains('SC_MODULE(Top)'));
      expect(
          sc.contentsByDefinitionName['Adder'], contains('SC_MODULE(Adder)'));

      sc.writeOutputs();
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
    'SystemCService writeOutputs emits configured multi-file artifacts',
    () async {
      final top = _Top(Logic(width: 8), Logic(width: 8));
      await top.build();

      final dir = Directory.systemTemp.createTempSync('rohd_systemc_service_');
      try {
        final sc = SystemCService(
          top,
          register: false,
          outputDirectory: dir.path,
        );
        expect(dir.listSync(), isEmpty);
        sc.writeOutputs();
        final files = dir.listSync().whereType<File>().toList();
        expect(files.any((f) => f.path.endsWith('.sc')), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );

  test(
    'SystemCService writeOutputs honors output base name',
    () async {
      final top = _Top(Logic(width: 8), Logic(width: 8));
      await top.build();

      final dir = Directory.systemTemp.createTempSync('rohd_systemc_service_');
      try {
        final sc = SystemCService(
          top,
          register: false,
          multiFile: false,
          outputDirectory: dir.path,
          outputBaseName: 'out',
        );
        final path = '${dir.path}/out.sc';
        expect(File(path).existsSync(), isFalse);
        sc.writeOutputs();
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

  test('stub-only SystemC service exposes result and file inventories',
      () async {
    final stub = _ExternalLeaf(Logic(width: 8), name: 'stub');
    await stub.build();

    final sc = SystemCService(
      stub,
      register: false,
      configuration: const SystemCSynthesizerConfiguration(
        stubAllUnsupportedModules: true,
      ),
    );

    expect(sc.diagnostics, hasLength(1));
    expect(sc.synthesisResults, hasLength(1));
    expect(sc.scFileMap, {
      'ExternalLeaf': ['ExternalLeaf.sc']
    });
    expect(
      sc.contentsByDefinitionName['ExternalLeaf'],
      contains('WARNING: Empty SystemC stub'),
    );
  });

  test(
      'custom SystemVerilog instantiation is rejected independently of '
      'standard definition generation', () async {
    final top = _CustomInstantiationTop();
    await top.build();

    expect(
      top.dumpSystemVerilog(),
      contains('assign q = ~data;'),
    );
    expect(
      () => SystemCService(top, register: false),
      throwsA(
        isA<UnsupportedSystemCModuleException>()
            .having(
              (error) => error.module.runtimeType,
              'module type',
              _CustomInstantiation,
            )
            .having(
              (error) => error.reason,
              'reason',
              contains('custom SystemVerilog instantiation'),
            ),
      ),
    );
  });

  test('custom SystemVerilog instantiation can be explicitly stubbed',
      () async {
    final top = _CustomInstantiationTop();
    await top.build();

    final sc = SystemCService(
      top,
      register: false,
      configuration: const SystemCSynthesizerConfiguration(
        stubAllUnsupportedModules: true,
      ),
    );

    expect(sc.diagnostics, hasLength(1));
    expect(sc.diagnostics.single.module, isA<_CustomInstantiation>());
    expect(
      sc.diagnostics.single.reason,
      contains('custom SystemVerilog instantiation'),
    );
    expect(sc.output, contains('WARNING: Empty SystemC stub'));
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

    SimCompare.checkSystemCVector(
      top,
      const [],
      synthesizerConfiguration: configuration,
    );
  });
}
