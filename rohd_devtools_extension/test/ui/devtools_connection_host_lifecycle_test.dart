// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_connection_host_lifecycle_test.dart
// Tests for the base DevTools connection host lifecycle.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/dtd_vm_service_info.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/connection_state_machine.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_connection_host.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/vm_connection_form.dart';
import 'package:vm_service/vm_service.dart';

class _MockVmService extends Mock implements VmService {}

class _MockDtd extends Mock implements DartToolingDaemon {}

Future<void> _completeDtdCall(Invocation _) => Future<void>.value();

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
  const _TestConnectionHost({required this.strategy, this.discoverVmServices});

  final VmConnectionStrategy? strategy;
  final Future<List<DiscoveredVmService>> Function(String uri)?
      discoverVmServices;

  @override
  State<_TestConnectionHost> createState() => _TestConnectionHostState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<VmConnectionStrategy?>('strategy', strategy))
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
  final _dtdCalls = <String>[];
  Completer<void>? _connectionStartCompleter;
  String? _awaitedConnectionUri;
  DartToolingDaemon? _dtdForTest;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<String>('lifecycleCalls', lifecycleCalls));
  }

  @override
  VmConnectionStrategy? get connectionStrategy => widget.strategy;

  @override
  Future<List<DiscoveredVmService>> discoverVmServices(String dtdUri) =>
      widget.discoverVmServices?.call(dtdUri) ??
      super.discoverVmServices(dtdUri);

  @override
  Future<void> startDtdListener() async {
    if (_dtdForTest != null) {
      await super.startDtdListener();
    }
    if (lastVmServiceUri == _awaitedConnectionUri) {
      final completer = _connectionStartCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  @override
  Future<DartToolingDaemon> connectDtd(Uri uri) async => _dtdForTest!;

  List<DtdVmServiceInfo> get _rememberedServicesForTest =>
      rememberedServices ?? const [];

  set _rememberedServicesForTest(List<DtdVmServiceInfo> services) {
    rememberedServices = services;
  }

  void enableAutoReconnectForTest(String vmName) {
    connectedVmName = vmName;
    autoReconnect = true;
  }

  void configureForTest({
    bool? connecting,
    bool? paused,
    bool? vmDead,
  }) {
    if (connecting != null) {
      isConnecting = connecting;
    }
    if (paused != null) {
      isPaused = paused;
    }
    if (vmDead != null) {
      isVmDead = vmDead;
    }
  }

  Future<void> waitForConnectionStart(String uri) {
    _awaitedConnectionUri = uri;
    _connectionStartCompleter = Completer<void>();
    return _connectionStartCompleter!.future;
  }

  Future<void> handleVmEventForTest(DTDEvent event) => handleDtdVmEvent(event);

  Future<void> reconnectFromVmEventForTest(String uri) =>
      reconnectFromDtdEvent(uri);

  void stopDtdListenerForTest() {
    stopDtdListener();
  }

  @override
  Widget build(BuildContext context) =>
      Text(isConnected ? 'connected' : 'disconnected');

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
  void onVmDead() {
    lifecycleCalls.add('dead');
  }

  @override
  void onVmRecovered() {
    lifecycleCalls.add('recovered');
  }

  @override
  void onDtdConnected(DartToolingDaemon dtd) {
    if (_dtdForTest != null) {
      _dtdCalls.add('connected');
    }
  }

  @override
  void onDtdDisconnected() {
    if (_dtdForTest != null) {
      _dtdCalls.add('disconnected');
    }
  }

  @override
  void onServiceAvailable(String serviceName) {
    _dtdCalls.add('available:$serviceName');
  }

  @override
  void onServiceUnavailable(String serviceName) {
    _dtdCalls.add('unavailable:$serviceName');
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
    when(vmService.getVersion).thenAnswer((_) async => Version());
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
        home: Scaffold(
          body: _TestConnectionHost(
            strategy: strategy,
            discoverVmServices: discoverVmServices,
          ),
        ),
      ),
    );
    return tester.state<_TestConnectionHostState>(
      find.byType(_TestConnectionHost),
    );
  }

  testWidgets('connects, pauses, resumes, and disconnects through hooks', (
    tester,
  ) async {
    final vmService = newVmService();
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: vmService, isolateId: 'isolate-1'),
    ]);
    final state = await pumpHost(tester, strategy: strategy);

    await state.connectToVmService('ws://host:8181/app=/ws');
    await tester.pump();

    expect(strategy.connectedUris, ['ws://host:8181/app=/ws']);
    expect(state.isConnected, isTrue);
    expect(state.isVmConnected, isTrue);
    expect(state.lastIsolateId, 'isolate-1');
    expect(state.connectionStateMachine.phase, ConnectionPhase.connected);
    expect(state.lifecycleCalls, [
      'tearDown:freshAttach',
      'before:freshAttach',
      'connected:ws://host:8181/app=/ws',
    ]);

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
    expect(state.lifecycleCalls, [
      'tearDown:freshAttach',
      'before:freshAttach',
      'connected:ws://host:8181/app=/ws',
      'paused',
      'resumed',
      'tearDown:disconnect',
      'disconnected',
    ]);
  });

  testWidgets('reports a missing connection strategy without connecting', (
    tester,
  ) async {
    final state = await pumpHost(tester, strategy: null);

    await state.attemptConnection();
    await tester.pump();

    expect(
      state.connectionError,
      'VM connection not available on this platform',
    );
    expect(state.isConnected, isFalse);
  });

  testWidgets('connects through DTD discovery and retains reconnect details', (
    tester,
  ) async {
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
    expect(state._rememberedServicesForTest, hasLength(1));

    await state.attemptConnection();
    await tester.pump();

    expect(strategy.connectedUris, ['ws://forwarded:8181/app=/ws']);
    expect(state.vmServiceUriController.text, isEmpty);
    expect(state.dtdUriController.text, 'ws://host:8181/dtd=');
    expect(state.connectedVmName, 'counter');
    expect(state.autoReconnect, isTrue);
    expect(state.isConnected, isTrue);
  });

  testWidgets('uses lightweight reconnect only when the isolate matches', (
    tester,
  ) async {
    final firstVmService = newVmService();
    final matchingVmService = newVmService();
    final mismatchingVmService = newVmService();
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: firstVmService, isolateId: 'isolate-1'),
      VmConnectionResult(vmService: matchingVmService, isolateId: 'isolate-1'),
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

  testWidgets(
    'handles in-memory VM lifecycle events and auto-reconnects without DTD I/O',
    (tester) async {
      final firstVmService = newVmService();
      final reconnectedVmService = newVmService();
      final strategy = _TestConnectionStrategy([
        VmConnectionResult(vmService: firstVmService, isolateId: 'isolate-1'),
        VmConnectionResult(
          vmService: reconnectedVmService,
          isolateId: 'isolate-2',
        ),
      ]);
      final state = await pumpHost(tester, strategy: strategy);
      const oldUri = 'ws://host:8181/old=/ws';
      const newUri = 'ws://host:8181/new=/ws';
      await state.connectToVmService(oldUri);
      state.enableAutoReconnectForTest('counter');

      await state.handleVmEventForTest(
        DTDEvent(
          ConnectedAppServiceConstants.serviceName,
          ConnectedAppServiceConstants.vmServiceUnregistered,
          {DtdParameters.uri: 'ws://host:8181/other=/ws'},
          0,
        ),
      );
      expect(state.isVmDead, isFalse);

      await state.handleVmEventForTest(
        DTDEvent(
          ConnectedAppServiceConstants.serviceName,
          ConnectedAppServiceConstants.vmServiceUnregistered,
          {DtdParameters.uri: oldUri},
          0,
        ),
      );
      expect(state.isVmDead, isTrue);
      expect(state.lifecycleCalls, contains('dead'));

      final reconnectStarted = state.waitForConnectionStart(newUri);
      await state.handleVmEventForTest(
        DTDEvent(
          ConnectedAppServiceConstants.serviceName,
          ConnectedAppServiceConstants.vmServiceRegistered,
          {
            DtdParameters.name: 'counter',
            DtdParameters.uri: newUri,
          },
          0,
        ),
      );
      await reconnectStarted;

      expect(strategy.connectedUris, [oldUri, newUri]);
      expect(state.isVmDead, isFalse);
      expect(state.lastVmServiceUri, newUri);
      expect(state.connectedVmName, 'counter');
      expect(state.autoReconnect, isTrue);

      await state.disconnect();
    },
  );

  testWidgets('reports VM service liveness from the active fake service', (
    tester,
  ) async {
    final vmService = newVmService();
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy([
        VmConnectionResult(vmService: vmService, isolateId: 'isolate-1'),
      ]),
    );

    expect(await state.isVmServiceAlive(), isFalse);

    await state.connectToVmService('ws://host:8181/app=/ws');
    expect(await state.isVmServiceAlive(), isTrue);

    when(vmService.getVersion).thenThrow(Exception('target stopped'));
    expect(await state.isVmServiceAlive(), isFalse);

    await state.disconnect();
  });

  testWidgets('ignores lifecycle events while paused or connecting', (
    tester,
  ) async {
    final vmService = newVmService();
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: vmService, isolateId: 'isolate-1'),
    ]);
    final state = await pumpHost(tester, strategy: strategy);
    const uri = 'ws://host:8181/app=/ws';
    await state.connectToVmService(uri);
    state
      ..enableAutoReconnectForTest('counter')
      ..configureForTest(paused: true);
    await state.handleVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceUnregistered,
        {DtdParameters.uri: uri},
        0,
      ),
    );
    expect(state.isVmDead, isFalse);

    state.configureForTest(paused: false, connecting: true);
    await state.handleVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {
          DtdParameters.name: 'counter',
          DtdParameters.uri: 'ws://host:8181/restarted=/ws',
        },
        0,
      ),
    );
    expect(strategy.connectedUris, [uri]);

    await state.disconnect();
  });

  testWidgets(
    'recovers a dead named VM through injected discovery without DTD I/O',
    (tester) async {
      final firstVmService = newVmService();
      final reconnectedVmService = newVmService();
      final strategy = _TestConnectionStrategy([
        VmConnectionResult(vmService: firstVmService, isolateId: 'isolate-1'),
        VmConnectionResult(
          vmService: reconnectedVmService,
          isolateId: 'isolate-2',
        ),
      ]);
      const oldUri = 'ws://host:8181/old=/ws';
      const newUri = 'ws://host:8181/restarted=/ws';
      String? discoveredFrom;
      final state = await pumpHost(
        tester,
        strategy: strategy,
        discoverVmServices: (dtdUri) async {
          discoveredFrom = dtdUri;
          return [
            DiscoveredVmService(
              name: 'counter',
              uri: newUri,
              autoReconnect: true,
            ),
          ];
        },
      );
      await state.connectToVmService(oldUri);
      state
        ..enableAutoReconnectForTest('counter')
        ..configureForTest(vmDead: true);
      state.dtdUriController.text = 'ws://host:8181/dtd=';

      final recovery = state.attemptAutoReconnect();
      await tester.pump(const Duration(seconds: 2));
      await recovery;

      expect(discoveredFrom, 'ws://host:8181/dtd=');
      expect(strategy.connectedUris, [oldUri, newUri]);
      expect(state.lastVmServiceUri, newUri);
      expect(state.isVmDead, isFalse);
      expect(state.rememberedServices, hasLength(1));

      await state.disconnect();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  testWidgets('shows and dismisses local connection dialogs', (tester) async {
    final unavailable = await pumpHost(tester, strategy: null);

    await unavailable.showConnectionDialog();
    await tester.pump();
    expect(
      find.text('VM connection not available on this platform'),
      findsOneWidget,
    );

    final available = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy([
        VmConnectionResult(vmService: newVmService(), isolateId: 'isolate-1'),
      ]),
    );
    final dialog = available.showConnectionDialog();
    await tester.pump();

    expect(find.text('Connect to VM Service'), findsOneWidget);
    expect(find.byType(VmConnectionForm), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets('marks a failed VM dead and recovers on a later liveness poll', (
    tester,
  ) async {
    final vmService = newVmService();
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy([
        VmConnectionResult(vmService: vmService, isolateId: 'isolate-1'),
      ]),
    );
    await state.connectToVmService('ws://host:8181/app=/ws');
    when(vmService.getVersion).thenThrow(Exception('target stopped'));

    for (var failures = 0; failures < 3; failures++) {
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
    }

    expect(state.isVmDead, isTrue);
    expect(state.lifecycleCalls, contains('dead'));

    when(vmService.getVersion).thenAnswer((_) async => Version());
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(state.isVmDead, isFalse);
    expect(state.lifecycleCalls, contains('recovered'));

    await state.disconnect();
  });

  testWidgets('rejects unrelated registered events without reconnecting', (
    tester,
  ) async {
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: newVmService(), isolateId: 'isolate-1'),
    ]);
    final state = await pumpHost(tester, strategy: strategy);
    await state.connectToVmService('ws://host:8181/app=/ws');

    await state.handleVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {
          DtdParameters.name: 'counter',
          DtdParameters.uri: 'ws://host:8181/restarted=/ws',
        },
        0,
      ),
    );
    state.enableAutoReconnectForTest('counter');

    await state.handleVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {
          DtdParameters.name: 'different-target',
          DtdParameters.uri: 'ws://host:8181/restarted=/ws',
        },
        0,
      ),
    );
    await state.handleVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {DtdParameters.name: 'counter'},
        0,
      ),
    );

    expect(strategy.connectedUris, ['ws://host:8181/app=/ws']);
    await state.disconnect();
  });

  testWidgets('uses a lightweight reconnect for a same-URI event', (
    tester,
  ) async {
    final firstVmService = newVmService();
    final replacementVmService = newVmService();
    const uri = 'ws://host:8181/app=/ws';
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: firstVmService, isolateId: 'isolate-1'),
      VmConnectionResult(
        vmService: replacementVmService,
        isolateId: 'isolate-1',
      ),
    ]);
    final state = await pumpHost(tester, strategy: strategy);
    await state.connectToVmService(uri);

    await state.reconnectFromVmEventForTest(uri);

    expect(strategy.connectedUris, [uri, uri]);
    expect(state.vmService, same(replacementVmService));
    expect(state.lifecycleCalls, contains('lightweight:$uri'));

    await state.disconnect();
  });

  testWidgets(
    'listens to injected DTD lifecycle and service streams without DTD I/O',
    (tester) async {
      final dtd = _MockDtd();
      final vmEvents = StreamController<DTDEvent>.broadcast();
      final serviceEvents = StreamController<DTDEvent>.broadcast();
      final done = Completer<void>();
      Future<void> doneFuture(Invocation _) => done.future;
      addTearDown(vmEvents.close);
      addTearDown(serviceEvents.close);
      when(() => dtd.isClosed).thenReturn(false);
      when(() => dtd.done).thenAnswer(doneFuture);
      when(dtd.close).thenAnswer(_completeDtdCall);
      when(() => dtd.streamListen(any())).thenAnswer(_completeDtdCall);
      when(dtd.getRegisteredServices)
          .thenThrow(Exception('registered services unavailable'));
      when(() => dtd.onEvent(any())).thenAnswer((invocation) {
        final streamId = invocation.positionalArguments.single as String;
        return streamId == CoreDtdServiceConstants.servicesStreamId
            ? serviceEvents.stream
            : vmEvents.stream;
      });

      final state = await pumpHost(tester, strategy: null);
      state
        .._dtdForTest = dtd
        ..dtdUriController.text = 'ws://host:8181/dtd=';

      await state.startDtdListener();
      expect(state._dtdCalls, contains('connected'));

      serviceEvents.add(
        DTDEvent(
          CoreDtdServiceConstants.servicesStreamId,
          CoreDtdServiceConstants.serviceRegisteredKind,
          {DtdParameters.service: 'rohd'},
          0,
        ),
      );
      await tester.pump();
      expect(state.isServiceAvailable('rohd'), isTrue);
      expect(state._dtdCalls, contains('available:rohd'));

      serviceEvents.add(
        DTDEvent(
          CoreDtdServiceConstants.servicesStreamId,
          CoreDtdServiceConstants.serviceUnregisteredKind,
          {DtdParameters.service: 'rohd'},
          0,
        ),
      );
      await tester.pump();
      expect(state.isServiceAvailable('rohd'), isFalse);
      expect(state._dtdCalls, contains('unavailable:rohd'));

      state.stopDtdListenerForTest();
      await tester.pump();

      verify(dtd.close).called(1);
      expect(state._dtdCalls, contains('disconnected'));
    },
  );

  testWidgets(
    'handles a completed injected DTD connection without external I/O',
    (tester) async {
      final dtd = _MockDtd();
      final vmEvents = StreamController<DTDEvent>.broadcast();
      final serviceEvents = StreamController<DTDEvent>.broadcast();
      final done = Completer<void>();
      Future<void> doneFuture(Invocation _) => done.future;
      Future<RegisteredServicesResponse> emptyRegisteredServices(
        Invocation _,
      ) async =>
          const RegisteredServicesResponse(
            dtdServices: [],
            clientServices: [],
          );
      addTearDown(vmEvents.close);
      addTearDown(serviceEvents.close);
      when(() => dtd.isClosed).thenReturn(false);
      when(() => dtd.done).thenAnswer(doneFuture);
      when(dtd.close).thenAnswer(_completeDtdCall);
      when(() => dtd.streamListen(any())).thenAnswer(_completeDtdCall);
      when(dtd.getRegisteredServices).thenAnswer(emptyRegisteredServices);
      when(() => dtd.onEvent(any())).thenAnswer((invocation) {
        final streamId = invocation.positionalArguments.single as String;
        return streamId == CoreDtdServiceConstants.servicesStreamId
            ? serviceEvents.stream
            : vmEvents.stream;
      });

      final state = await pumpHost(tester, strategy: null);
      state
        .._dtdForTest = dtd
        ..dtdUriController.text = 'ws://host:8181/dtd=';

      await state.startDtdListener();
      await state.startDtdListener();
      verify(() => dtd.streamListen(any())).called(2);

      done.complete();
      await tester.pump();

      expect(state.persistentDtd, isNull);
      expect(state._dtdCalls, contains('disconnected'));
    },
  );
}
