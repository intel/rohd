// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_design_dtd_service_test.dart
// Tests for the typed ROHD design-session DTD bridge.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:vm_service/vm_service.dart' as vm;

class _FakeDesignTarget {
  String? method;
  Map<String, Object?>? parameters;

  Future<Map<String, Object?>> call(
      String method, Map<String, Object?> parameters) async {
    this.method = method;
    this.parameters = parameters;
    return {
      'schemaVersion': RohdDesignSessionProtocol.schemaVersion,
      'ok': true,
      'result': {'address': '0.1', 'path': 'top/leaf/dataOut'}
    };
  }
}

class _MockVmService extends Mock implements vm.VmService {}

void main() {
  test('forwards typed calls without interpreting occurrence DTOs', () async {
    final target = _FakeDesignTarget();
    final service = RohdDesignDtdService(target.call);
    final handle = {'address': '0.1'};

    final response = await service.execute(RohdDesignSessionProtocol.fanin,
        '{"signal":{"address":"0.1"},"transparent":true}');

    expect(target.method, RohdDesignSessionProtocol.fanin);
    expect(target.parameters, {'signal': handle, 'transparent': true});
    expect(response['ok'], isTrue);
    expect(response['result'], {'address': '0.1', 'path': 'top/leaf/dataOut'});
  });

  test('rejects non-object parameter JSON before forwarding', () async {
    final target = _FakeDesignTarget();
    final service = RohdDesignDtdService(target.call);

    final response =
        await service.execute(RohdDesignSessionProtocol.status, '[]');

    expect(target.method, isNull);
    expect(response['ok'], isFalse);
    expect(Map<String, Object?>.from(response['error']! as Map)['code'],
        'invalidArgument');
  });

  test('escapes aliases in debugger-evaluated command strings', () async {
    final vmService = _MockVmService();
    const isolateId = 'isolates/target';
    const libraryId = 'libraries/rohd-inspector';
    when(() => vmService.getIsolate(isolateId))
        .thenAnswer((_) async => vm.Isolate(id: isolateId, libraries: [
              vm.LibraryRef(
                  id: libraryId,
                  uri: 'package:rohd/src/diagnostics/inspector_service.dart')
            ]));
    when(() => vmService.evaluate(isolateId, libraryId, any())).thenAnswer(
        (_) async => vm.Instance(
            id: 'objects/response',
            kind: vm.InstanceKind.kString,
            valueAsString: '{"ok":true}'));
    final target = VmServiceRohdDesignTarget(vmService, isolateId);

    await target.command('terminal', r'get-value $x');

    final expression = verify(
      () => vmService.evaluate(isolateId, libraryId, captureAny()),
    ).captured.single as String;
    expect(expression, contains(r'"get-value \$x"'));
  });
}
