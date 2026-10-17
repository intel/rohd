// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

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
}
