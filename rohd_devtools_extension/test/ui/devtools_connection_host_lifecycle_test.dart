// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_connection_host_lifecycle_test.dart
// Tests for the base DevTools connection host lifecycle.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/dtd_vm_service_info.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/connection_state_machine.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_connection_host.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/vm_connection_form.dart';
import 'package:vm_service/vm_service.dart';

class _MockVmService extends Mock implements VmService {}

class _TestConnectionStrategy extends VmConnectionStrategy {
  _TestConnectionStrategy(this.results);

  final List<VmConnectionResult> results;
  final connectedUris = <String>[];

  @override
  Future<VmConnectionResult> connect(String uri) async {
    connectedUris.add(uri);
    return results.removeAt(0);
  }
}

class _TestConnectionHost extends StatefulWidget {
  const _TestConnectionHost({
    required this.strategy,
    this.discoverVmServices,
  });

  final VmConnectionStrategy? strategy;
  final Future<List<DiscoveredVmService>> Function(String uri)?
      discoverVmServices;

  @override
  State<_TestConnectionHost> createState() => _TestConnectionHostState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<VmConnectionStrategy?>('strategy', strategy),
      )
      ..add(
        ObjectFlagProperty<Future<List<DiscoveredVmService>> Function(String)?>(
          'discoverVmServices',
          discoverVmServices,
          ifNull: 'default',
        ),
      );
  }
}

class _TestConnectionHostState
    extends DevToolsConnectionHostState<_TestConnectionHost> {
  final lifecycleCalls = <String>[];

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      IterableProperty<String>('lifecycleCalls', lifecycleCalls),
    );
  }

  @override
  VmConnectionStrategy? get connectionStrategy => widget.strategy;

  @override
  Future<List<DiscoveredVmService>> discoverVmServices(String dtdUri) async =>
      widget.discoverVmServices?.call(dtdUri) ??
      super.discoverVmServices(dtdUri);

  @override
  Future<void> startDtdListener() async {}

  List<DtdVmServiceInfo> get _rememberedServicesForTest =>
      rememberedServices ?? const [];

  set _rememberedServicesForTest(List<DtdVmServiceInfo> services) {
    rememberedServices = services;
  }

  @override
  Widget build(BuildContext context) => Text(
        isConnected ? 'connected' : 'disconnected',
      );

  @override
  Future<void> onVmConnected(VmConnectionResult result, String uri) async {
    lifecycleCalls.add('connected:$uri');
  }

  @override
  Future<void> onBeforeVmConnected(
    VmConnectionResult result,
    String uri, {
    required VmConnectionTransition transition,
  }) async {
    lifecycleCalls.add('before:${transition.kind.name}');
  }

  @override
  Future<void> tearDownOldConnection({
    required VmConnectionTransition transition,
  }) async {
    lifecycleCalls.add('tearDown:${transition.kind.name}');
  }

  @override
  void onVmDisconnected() {
    lifecycleCalls.add('disconnected');
  }

  @override
  Future<void> onVmPaused() async {
    lifecycleCalls.add('paused');
  }

  @override
  Future<void> onVmResumed() async {
    lifecycleCalls.add('resumed');
  }

  @override
  Future<void> onLightweightReconnectSuccess(
    VmConnectionResult result,
    String uri,
  ) async {
    lifecycleCalls.add('lightweight:$uri');
  }
}

void main() {
  _MockVmService newVmService() {
    final vmService = _MockVmService();
    when(() => vmService.onDebugEvent)
        .thenAnswer((_) => const Stream<Event>.empty());
    when(vmService.dispose).thenAnswer((_) async {});
    return vmService;
  }

  Future<_TestConnectionHostState> pumpHost(
    WidgetTester tester, {
    required VmConnectionStrategy? strategy,
    Future<List<DiscoveredVmService>> Function(String uri)? discoverVmServices,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _TestConnectionHost(
          strategy: strategy,
          discoverVmServices: discoverVmServices,
        ),
      ),
    );
    return tester.state<_TestConnectionHostState>(
      find.byType(_TestConnectionHost),
    );
  }

  testWidgets('connects, pauses, resumes, and disconnects through hooks',
      (tester) async {
    final vmService = newVmService();
    final strategy = _TestConnectionStrategy(
      [VmConnectionResult(vmService: vmService, isolateId: 'isolate-1')],
    );
    final state = await pumpHost(tester, strategy: strategy);

    await state.connectToVmService('ws://host:8181/app=/ws');
    await tester.pump();

    expect(strategy.connectedUris, ['ws://host:8181/app=/ws']);
    expect(state.isConnected, isTrue);
    expect(state.isVmConnected, isTrue);
    expect(state.lastIsolateId, 'isolate-1');
    expect(state.connectionStateMachine.phase, ConnectionPhase.connected);
    expect(
      state.lifecycleCalls,
      [
        'tearDown:freshAttach',
        'before:freshAttach',
        'connected:ws://host:8181/app=/ws'
      ],
    );

    await state.pauseVm();
    expect(state.isPaused, isTrue);
    expect(state.connectionStateMachine.phase, ConnectionPhase.paused);

    await state.resumeVm();
    expect(state.isPaused, isFalse);
    expect(state.connectionStateMachine.phase, ConnectionPhase.connecting);

    await state.disconnect();
    await tester.pump();

    expect(state.isConnected, isFalse);
    expect(state.isVmConnected, isFalse);
    expect(state.lastVmServiceUri, isNull);
    expect(state.connectionStateMachine.phase, ConnectionPhase.disconnected);
    expect(
      state.lifecycleCalls,
      [
        'tearDown:freshAttach',
        'before:freshAttach',
        'connected:ws://host:8181/app=/ws',
        'paused',
        'resumed',
        'tearDown:disconnect',
        'disconnected',
      ],
    );
  });

  testWidgets('reports a missing connection strategy without connecting',
      (tester) async {
    final state = await pumpHost(tester, strategy: null);

    await state.attemptConnection();
    await tester.pump();

    expect(
        state.connectionError, 'VM connection not available on this platform');
    expect(state.isConnected, isFalse);
  });

  testWidgets('connects through DTD discovery and retains reconnect details',
      (tester) async {
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: newVmService(), isolateId: 'isolate-1'),
    ]);
    final state = await pumpHost(
      tester,
      strategy: strategy,
      discoverVmServices: (dtdUri) async {
        expect(dtdUri, 'ws://host:8181/dtd=');
        return [
          DiscoveredVmService(
            name: 'counter',
            uri: 'ws://internal:8181/app=/ws',
            exposedUri: 'ws://forwarded:8181/app=/ws',
          ),
        ];
      },
    );
    state.vmServiceUriController.clear();
    state.dtdUriController.text = ' ws://host:8181/dtd= ';
    state._rememberedServicesForTest = [
      DtdVmServiceInfo.fromFields(
        name: 'counter',
        uri: 'ws://internal:8181/app=/ws',
        exposedUri: 'ws://forwarded:8181/app=/ws',
        autoReconnect: true,
      ),
    ];
    expect(state._rememberedServicesForTest.single.autoReconnect, isTrue);

    await state.attemptConnection();
    await tester.pump();

    expect(strategy.connectedUris, ['ws://forwarded:8181/app=/ws']);
    expect(state.vmServiceUriController.text, isEmpty);
    expect(state.dtdUriController.text, 'ws://host:8181/dtd=');
    expect(state.connectedVmName, 'counter');
    expect(state.autoReconnect, isTrue);
    expect(state.isConnected, isTrue);
  });

  testWidgets('uses lightweight reconnect only when the isolate matches',
      (tester) async {
    final firstVmService = newVmService();
    final matchingVmService = newVmService();
    final mismatchingVmService = newVmService();
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: firstVmService, isolateId: 'isolate-1'),
      VmConnectionResult(
        vmService: matchingVmService,
        isolateId: 'isolate-1',
      ),
      VmConnectionResult(
        vmService: mismatchingVmService,
        isolateId: 'isolate-2',
      ),
    ]);
    final state = await pumpHost(tester, strategy: strategy);
    await state.connectToVmService('ws://host:8181/app=/ws');

    expect(await state.lightweightReconnect('ws://host:8181/app=/ws'), isTrue);
    expect(state.vmService, matchingVmService);
    expect(state.lifecycleCalls.last, 'lightweight:ws://host:8181/app=/ws');

    expect(await state.lightweightReconnect('ws://host:8181/app=/ws'), isFalse);
    verify(mismatchingVmService.dispose).called(1);
    expect(state.vmService, matchingVmService);
  });
}
