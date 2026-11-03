// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_service_tree_data_source_test.dart
// Tests the VM service tree data source.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_tree_data_source.dart';
import 'package:vm_service/vm_service.dart' as vm;

class _MockVmService extends Mock implements vm.VmService {}

const _isolateId = 'isolates/test';
const _libraryId = 'libraries/rohd';

vm.Isolate _isolateWithLibraries(List<vm.LibraryRef> libraries) =>
    vm.Isolate(id: _isolateId, libraries: libraries);

vm.LibraryRef _rohdLibrary() => vm.LibraryRef(
      id: _libraryId,
      uri: 'package:rohd/src/diagnostics/module_services.dart',
    );

vm.Instance _stringResult(String value) => vm.Instance(
      id: 'objects/result',
      kind: vm.InstanceKind.kString,
      valueAsString: value,
    );

void main() {
  test('returns unavailable values when the isolate has no ROHD library',
      () async {
    final vmService = _MockVmService();
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([
        vm.LibraryRef(id: 'libraries/app', uri: 'package:app/main.dart'),
      ]),
    );
    final source = VmServiceTreeDataSource(
      vmService: vmService,
      isolateId: _isolateId,
    );

    expect(await source.evalModuleTree(), isNull);
    expect(await source.fetchModuleSchematic('Missing'), isNull);
    expect(await source.fetchModuleFlc('Missing'), isNull);
    expect(await source.fetchFlcHierarchy(), isNull);
    expect(await source.fetchFlcFilePath(), isNull);
  });

  test('rejects malformed and failed hierarchy payloads before a valid tree',
      () async {
    final vmService = _MockVmService();
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([_rohdLibrary()]),
    );
    final responses = <String>[
      'not JSON',
      '{"status":"fail","message":"not built"}',
      '{"name":"top","subModules":[]}',
    ];
    when(() => vmService.evaluate(_isolateId, _libraryId, any())).thenAnswer(
      (_) async => _stringResult(responses.removeAt(0)),
    );
    final source = VmServiceTreeDataSource(
      vmService: vmService,
      isolateId: _isolateId,
    );

    expect(await source.evalModuleTree(), isNull);
    expect(await source.evalModuleTree(), isNull);
    expect((await source.evalModuleTree())?.name, 'top');
    expect(source.getSchematicJson(), isNull);
  });

  test('unwraps module data and escapes quoted definition names', () async {
    final vmService = _MockVmService();
    when(() => vmService.getIsolate(_isolateId)).thenAnswer(
      (_) async => _isolateWithLibraries([_rohdLibrary()]),
    );
    when(() => vmService.evaluate(_isolateId, _libraryId, any())).thenAnswer(
      (_) async => _stringResult(
        '{"modules":{"Returned":{"ports":{},"cells":{},"netnames":{}}}}',
      ),
    );
    final source = VmServiceTreeDataSource(
      vmService: vmService,
      isolateId: _isolateId,
    );

    final module = await source.fetchModuleSchematic("Quoted'Name");
    expect(module, contains('Returned'));
    final expression =
        verify(() => vmService.evaluate(_isolateId, _libraryId, captureAny()))
            .captured
            .single as String;
    expect(expression, contains(r"Quoted\'Name"));
  });
}
