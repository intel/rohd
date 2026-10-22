// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';
import 'package:vm_service/vm_service.dart';

class _MockVmService extends Mock implements VmService {}

void main() {
  late EvalOnDartLibrary evaluator;
  late Disposable disposable;

  setUp(() {
    evaluator = EvalOnDartLibrary(
      'test',
      _MockVmService(),
      serviceManager: ServiceManager<VmService>(),
    );
    disposable = Disposable();
  });

  test('returns null when evaluation fails', () async {
    final service = TreeService(
      evaluator,
      disposable,
      evalInstance: (_, {required isAlive}) =>
          Future<Instance>.error(Exception('disconnected')),
    );

    expect(await service.evalModuleTree(), isNull);
  });

  test('returns null for empty or unavailable payloads', () async {
    final instance = Instance(id: 'test')..valueAsString = '';
    final service = TreeService(
      evaluator,
      disposable,
      evalInstance: (_, {required isAlive}) async => instance,
    );

    expect(await service.evalModuleTree(), isNull);

    instance.valueAsString = '{"status":"unavailable","reason":"not ready"}';

    expect(await service.evalModuleTree(), isNull);
  });

  test('refresh surfaces a failed evaluation', () async {
    final service = TreeService(
      evaluator,
      disposable,
      evalInstance: (_, {required isAlive}) async =>
          Instance(id: 'test')..valueAsString = '',
    );

    expect(service.refreshModuleTree(), throwsStateError);
  });

  test(
    'loads packaged FilterBank data and caches incremental FLC evaluations',
    () async {
      final netlist =
          await File('test/fixtures/filter_bank.json').readAsString();
      final flcModule = <String, dynamic>{
        'version': 6,
        'files': <String>['example/filter_bank/filter_bank.dart'],
        'modules': <String, dynamic>{
          'FilterBank': <String, dynamic>{'tree': <dynamic>[]},
        },
      };
      final calls = <String>[];
      final service = TreeService(
        evaluator,
        disposable,
        evalInstance: (expression, {required isAlive}) async {
          calls.add(expression);
          final value = switch (expression) {
            final value when value.contains('slimJson') => netlist,
            final value when value.contains('moduleJson') => jsonEncode(
                <String, dynamic>{
                  'modules': <String, dynamic>{
                    'FilterBank': <String, dynamic>{
                      'ports': <String, dynamic>{},
                    },
                  },
                },
              ),
            final value when value.contains('flcModuleJson') =>
              jsonEncode(flcModule),
            final value when value.contains('.flcJson') =>
              jsonEncode(flcModule),
            final value when value.contains('.writtenPath') =>
              '/tmp/FilterBank.flc.json',
            _ => throw StateError('Unexpected evaluation: $expression'),
          };
          return Instance(id: 'test')..valueAsString = value;
        },
      );

      final tree = await service.evalModuleTree();
      expect(tree?.name, 'FilterBank');
      expect(
          service.getSchematicJson()?['modules'], isA<Map<String, dynamic>>());

      final module = await service.fetchModuleSchematic('FilterBank');
      expect(module, contains('FilterBank'));

      final firstFlc = await service.fetchModuleFlc('FilterBank');
      final secondFlc = await service.fetchModuleFlc('FilterBank');
      expect(firstFlc, same(secondFlc));
      expect(
        calls.where((call) => call.contains('flcModuleJson')).length,
        1,
      );

      expect(
        (await service.fetchFlcHierarchy())?['modules'],
        contains('FilterBank'),
      );
      expect(await service.fetchFlcFilePath(), '/tmp/FilterBank.flc.json');

      service.clearFlcCache();
      await service.fetchModuleFlc('FilterBank');
      expect(
        calls.where((call) => call.contains('flcModuleJson')).length,
        2,
      );
    },
  );

  test('returns null for unavailable and malformed incremental responses',
      () async {
    var moduleCalls = 0;
    final service = TreeService(
      evaluator,
      disposable,
      evalInstance: (expression, {required isAlive}) async {
        final value = switch (expression) {
          final value when value.contains('moduleJson') => switch (
                moduleCalls++) {
              0 => 'null',
              _ => 'not JSON',
            },
          final value when value.contains('flcModuleJson') =>
            '{"status":"unavailable","reason":"trace disabled"}',
          final value when value.contains('.flcJson') =>
            '{"status":"unavailable","reason":"trace disabled"}',
          final value when value.contains('.writtenPath') =>
            '{"status":"unavailable"}',
          _ => throw Exception('target disconnected'),
        };
        return Instance(id: 'test')..valueAsString = value;
      },
    );

    expect(await service.fetchModuleSchematic('Missing'), isNull);
    expect(await service.fetchModuleSchematic('Malformed'), isNull);
    expect(await service.fetchModuleFlc('Missing'), isNull);
    expect(await service.fetchFlcHierarchy(), isNull);
    expect(await service.fetchFlcFilePath(), isNull);
    expect(await service.evalModuleTree(), isNull);
  });

  test('caches normalized VM script sources and clears them with FLC cache',
      () async {
    final vmService = _MockVmService();
    const isolateId = 'isolates/source';
    const scriptId = 'scripts/example';
    const scriptUri = 'package:demo/src/example.dart';
    var scriptListRequests = 0;
    var scriptObjectRequests = 0;
    when(() => vmService.getScripts(isolateId)).thenAnswer(
      (_) async {
        scriptListRequests++;
        return ScriptList(
          scripts: [
            ScriptRef(id: scriptId, uri: scriptUri),
          ],
        );
      },
    );
    when(() => vmService.getObject(isolateId, scriptId)).thenAnswer(
      (_) async {
        scriptObjectRequests++;
        return Script(
          id: scriptId,
          uri: scriptUri,
          source: 'first line\nsecond line\nthird line',
        );
      },
    );
    final service = TreeService(
      evaluator,
      disposable,
      vmService: vmService,
      isolateId: isolateId,
      evalInstance: (_, {required isAlive}) async =>
          Instance(id: 'test')..valueAsString = 'null',
    );

    const sourcePath = '.dart_tool/../lib/src/example.dart';
    expect(await service.fetchSourceLine(sourcePath, 2), 'second line');
    expect(await service.fetchSourceLine(sourcePath, 3), 'third line');
    expect(await service.fetchSourceLine(sourcePath, 0), isNull);
    expect(await service.fetchSourceLine(sourcePath, 4), isNull);
    expect(await service.fetchSourceLine('lib/src/missing.dart', 1), isNull);
    expect(scriptListRequests, 1);
    expect(scriptObjectRequests, 1);

    service.clearFlcCache();
    expect(await service.fetchSourceLine(sourcePath, 1), 'first line');
    expect(scriptListRequests, 2);
    expect(scriptObjectRequests, 2);
  });
}
