// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_connection_host_lifecycle_test.dart
// Tests for the base DevTools connection host lifecycle.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dtd/dtd.dart';
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

class _ThrowingConnectionStrategy extends VmConnectionStrategy {
  @override
  Future<VmConnectionResult> connect(String uri) async =>
      throw Exception('connect exploded');
}

class _DtdHostStub {
  _DtdHostStub._(this._server);

  final HttpServer _server;
  final requestedMethods = <String>[];
  final connections = <WebSocket>[];

  static Future<_DtdHostStub> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = _DtdHostStub._(server);
    unawaited(stub._listen());
    return stub;
  }

  Uri get uri => Uri(
        scheme: 'ws',
        host: InternetAddress.loopbackIPv4.address,
        port: _server.port,
      );

  Future<void> _listen() async {
    await for (final request in _server) {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        continue;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      connections.add(socket);
      socket.listen((message) {
        final request = jsonDecode(message as String) as Map<String, dynamic>;
        final method = request['method'] as String;
        requestedMethods.add(method);
        final result = _resultFor(method);
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': request['id'],
            if (result == null)
              'error': {
                'code': -32601,
                'message': 'Unexpected DTD request: $method',
              }
            else
              'result': result,
          }),
        );
      });
    }
  }

  Map<String, Object?>? _resultFor(String method) => switch (method) {
        CoreDtdServiceConstants.streamListen => {'type': 'Success'},
        CoreDtdServiceConstants.getRegisteredServices => {
            'type': 'RegisteredServicesResponse',
            'dtdServices': <String>[ConnectedAppServiceConstants.serviceName],
            'clientServices': <Map<String, Object?>>[
              {
                'name': 'rohd',
                'methods': <Map<String, Object?>>[],
              },
            ],
          },
        _ => null,
      };

  void emitEvent({
    required String streamId,
    required String eventKind,
    required Map<String, Object?> eventData,
    required int timestamp,
  }) {
    for (final socket in connections) {
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': CoreDtdServiceConstants.streamNotify,
          'params': {
            'streamId': streamId,
            'eventKind': eventKind,
            'eventData': eventData,
            'timestamp': timestamp,
          },
        }),
      );
    }
  }

  Future<void> close() async {
    for (final connection in connections) {
      unawaited(connection.close());
    }
    await _server.close(force: true);
  }
}

class _TestConnectionHost extends StatefulWidget {
  const _TestConnectionHost({
    required this.strategy,
    this.discoverVmServices,
    this.simpleDialogContent = false,
    this.useRealDtdListener = false,
  });

  final VmConnectionStrategy? strategy;
  final Future<List<DiscoveredVmService>> Function(String uri)?
      discoverVmServices;
  final bool simpleDialogContent;
  final bool useRealDtdListener;

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
      )
      ..add(
        DiagnosticsProperty<bool>('simpleDialogContent', simpleDialogContent),
      )
      ..add(
        DiagnosticsProperty<bool>('useRealDtdListener', useRealDtdListener),
      );
  }
}

class _TestConnectionHostState
    extends DevToolsConnectionHostState<_TestConnectionHost> {
  final lifecycleCalls = <String>[];
  bool throwOnNextTearDown = false;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        IterableProperty<String>('lifecycleCalls', lifecycleCalls),
      )
      ..add(
        DiagnosticsProperty<bool>('throwOnNextTearDown', throwOnNextTearDown),
      );
  }

  @override
  VmConnectionStrategy? get connectionStrategy => widget.strategy;

  @override
  Future<List<DiscoveredVmService>> discoverVmServices(String dtdUri) async =>
      widget.discoverVmServices?.call(dtdUri) ??
      super.discoverVmServices(dtdUri);

  @override
  Future<void> startDtdListener() async {
    if (widget.useRealDtdListener) {
      return super.startDtdListener();
    }
  }

  List<DtdVmServiceInfo>? get _rememberedServicesForTest => rememberedServices;

  set _rememberedServicesForTest(List<DtdVmServiceInfo>? services) {
    rememberedServices = services;
  }

  void configureTrackedVmForTest({
    required String uri,
    required String isolateId,
    String? name,
    bool autoReconnect = false,
    bool paused = false,
    bool connecting = false,
  }) {
    lastVmServiceUri = uri;
    lastIsolateId = isolateId;
    connectedVmName = name;
    this.autoReconnect = autoReconnect;
    isConnected = true;
    isPaused = paused;
    isConnecting = connecting;
  }

  Future<void> handleDtdVmEventForTest(DTDEvent event) =>
      handleDtdVmEvent(event);

  Future<void> reconnectFromDtdEventForTest(String uri) =>
      reconnectFromDtdEvent(uri);

  void handleServiceStreamEventForTest(DTDEvent event) =>
      handleServiceStreamEventForTesting(event);

  Future<void> checkVmLivenessForTest() => checkVmLivenessForTesting();

  Future<void> startDtdListenerForTest() => startDtdListener();

  void stopDtdListenerForTest() => stopDtdListener();

  void throwOnNextTearDownForTest() {
    throwOnNextTearDown = true;
  }

  Widget buildBaseConnectionDialogContentForTest(BuildContext context) =>
      super.buildConnectionDialogContent(context);

  @override
  Widget build(BuildContext context) => Text(
        isConnected ? 'connected' : 'disconnected',
      );

  @override
  Widget buildConnectionDialogContent(BuildContext dialogContext) =>
      widget.simpleDialogContent
          ? const Text('Simple connection content')
          : super.buildConnectionDialogContent(dialogContext);

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
    if (throwOnNextTearDown) {
      throwOnNextTearDown = false;
      throw Exception('tearDown exploded');
    }
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

  @override
  void onVmDead() {
    lifecycleCalls.add('dead');
  }

  @override
  void onVmRecovered() {
    lifecycleCalls.add('recovered');
  }

  @override
  void onServiceAvailable(String serviceName) {
    lifecycleCalls.add('available:$serviceName');
  }

  @override
  void onServiceUnavailable(String serviceName) {
    lifecycleCalls.add('unavailable:$serviceName');
  }

  @override
  void onDtdConnected(DartToolingDaemon dtd) {
    if (widget.useRealDtdListener) {
      lifecycleCalls.add('dtdConnected');
    }
  }

  @override
  void onDtdDisconnected() {
    if (widget.useRealDtdListener) {
      lifecycleCalls.add('dtdDisconnected');
    }
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
    bool simpleDialogContent = false,
    bool useRealDtdListener = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Scaffold(
          body: _TestConnectionHost(
            strategy: strategy,
            discoverVmServices: discoverVmServices,
            simpleDialogContent: simpleDialogContent,
            useRealDtdListener: useRealDtdListener,
          ),
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

  testWidgets('continues connecting when old teardown throws', (tester) async {
    final vmService = newVmService();
    final strategy = _TestConnectionStrategy(
      [VmConnectionResult(vmService: vmService, isolateId: 'isolate-1')],
    );
    final state = await pumpHost(tester, strategy: strategy);
    state.throwOnNextTearDownForTest();

    await state.connectToVmService('ws://host:8181/app=/ws');
    await tester.pump();

    expect(state.isConnected, isTrue);
    expect(state.connectionGeneration, 1);
    expect(
      state.lifecycleCalls,
      [
        'tearDown:freshAttach',
        'before:freshAttach',
        'connected:ws://host:8181/app=/ws',
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

  testWidgets('shows snackbar when connection dialog has no strategy',
      (tester) async {
    final state = await pumpHost(tester, strategy: null);

    await state.showConnectionDialog();
    await tester.pump();

    expect(
      find.text('VM connection not available on this platform'),
      findsOneWidget,
    );
  });

  testWidgets('shows and cancels the default connection dialog',
      (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
      simpleDialogContent: true,
    );

    final dialogFuture = state.showConnectionDialog();
    await tester.pumpAndSettle();

    expect(find.text('Connect to VM Service'), findsOneWidget);
    expect(find.text('Simple connection content'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dialogFuture;
  });

  testWidgets('builds default connection dialog content with remembered VMs',
      (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
    );
    state
      .._rememberedServicesForTest = [
        DtdVmServiceInfo.fromFields(
          name: 'counter',
          uri: 'ws://internal:8181/app=/ws',
          exposedUri: 'ws://forwarded:8181/app=/ws',
          autoReconnect: true,
        ),
      ]
      ..connectionError = 'Try again';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: NoSplash.splashFactory,
        ),
        home: Builder(
          builder: (context) => Material(
            child: SizedBox(
              width: 1000,
              child: state.buildBaseConnectionDialogContentForTest(context),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('counter'), findsWidgets);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('clears connecting state when connection strategy throws',
      (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _ThrowingConnectionStrategy(),
    );
    state.vmServiceUriController.text = 'ws://host:8181/app=/ws';

    await state.attemptConnection();
    await tester.pump();

    expect(state.isConnected, isFalse);
    expect(state.isConnecting, isFalse);
    expect(state.connectionError, contains('connect exploded'));
  });

  testWidgets('pause and resume are no-ops when disconnected', (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
    );

    await state.pauseVm();
    await state.resumeVm();

    expect(state.isPaused, isFalse);
    expect(state.lifecycleCalls, isEmpty);
  });

  testWidgets('checks VM service liveness from current service',
      (tester) async {
    final liveService = newVmService();
    when(liveService.getVersion).thenAnswer(
      (_) async => Version(major: 4, minor: 0),
    );
    final deadService = newVmService();
    when(deadService.getVersion).thenThrow(Exception('closed'));
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: liveService, isolateId: 'isolate-1'),
      VmConnectionResult(vmService: deadService, isolateId: 'isolate-2'),
    ]);

    final state = await pumpHost(tester, strategy: strategy);
    expect(await state.isVmServiceAlive(), isFalse);

    await state.connectToVmService('ws://host:8181/live=/ws');
    expect(await state.isVmServiceAlive(), isTrue);

    await state.connectToVmService('ws://host:8181/dead=/ws');
    expect(await state.isVmServiceAlive(), isFalse);
  });

  testWidgets('liveness probe marks the VM dead and recovered', (tester) async {
    final vmService = newVmService();
    var versionChecks = 0;
    when(vmService.getVersion).thenAnswer((_) async {
      versionChecks++;
      if (versionChecks <= 3) {
        throw Exception('closed');
      }
      return Version(major: 4, minor: 0);
    });
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(vmService: vmService, isolateId: 'isolate-1'),
    ]);
    final state = await pumpHost(tester, strategy: strategy);
    await state.connectToVmService('ws://host:8181/app=/ws');
    state.lifecycleCalls.clear();

    await state.checkVmLivenessForTest();
    await state.checkVmLivenessForTest();
    await state.checkVmLivenessForTest();
    await tester.pump();

    expect(state.isVmDead, isTrue);
    expect(state.lifecycleCalls, ['dead']);

    await state.checkVmLivenessForTest();
    await tester.pump();

    expect(state.isVmDead, isFalse);
    expect(state.lifecycleCalls, ['dead', 'recovered']);
  });

  testWidgets('service stream events update availability only on changes',
      (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
    );

    state
      ..handleServiceStreamEventForTest(
        DTDEvent(
          CoreDtdServiceConstants.servicesStreamId,
          CoreDtdServiceConstants.serviceRegisteredKind,
          const {},
          1,
        ),
      )
      ..handleServiceStreamEventForTest(
        DTDEvent(
          CoreDtdServiceConstants.servicesStreamId,
          CoreDtdServiceConstants.serviceRegisteredKind,
          const {'service': 'rohd'},
          2,
        ),
      )
      ..handleServiceStreamEventForTest(
        DTDEvent(
          CoreDtdServiceConstants.servicesStreamId,
          CoreDtdServiceConstants.serviceRegisteredKind,
          const {'service': 'rohd'},
          3,
        ),
      );
    expect(state.isServiceAvailable('rohd'), isTrue);
    expect(state.lifecycleCalls, ['available:rohd']);

    state
      ..handleServiceStreamEventForTest(
        DTDEvent(
          CoreDtdServiceConstants.servicesStreamId,
          CoreDtdServiceConstants.serviceUnregisteredKind,
          const {'service': 'other'},
          4,
        ),
      )
      ..handleServiceStreamEventForTest(
        DTDEvent(
          CoreDtdServiceConstants.servicesStreamId,
          CoreDtdServiceConstants.serviceUnregisteredKind,
          const {'service': 'rohd'},
          5,
        ),
      );

    expect(state.isServiceAvailable('rohd'), isFalse);
    expect(state.lifecycleCalls, ['available:rohd', 'unavailable:rohd']);
  });

  testWidgets('real DTD listener tracks services and VM lifecycle events',
      (tester) async {
    Future<void> waitForCondition(
      bool Function() condition,
      String description,
    ) async {
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out waiting for $description');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
    }

    final dtd = (await tester.runAsync(_DtdHostStub.start))!;
    addTearDown(() => tester.runAsync(dtd.close));
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
      useRealDtdListener: true,
    );
    state
      ..dtdUriController.text = dtd.uri.toString()
      ..configureTrackedVmForTest(
        uri: 'ws://ours:8181/app=/ws',
        isolateId: 'isolate-1',
      );

    await tester.runAsync(
      () => state.startDtdListenerForTest().timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail(
              'Timed out starting DTD listener; '
              'requests=${dtd.requestedMethods}, '
              'connections=${dtd.connections.length}',
            ),
          ),
    );
    await tester.pump();

    expect(dtd.requestedMethods, [
      CoreDtdServiceConstants.streamListen,
      CoreDtdServiceConstants.streamListen,
      CoreDtdServiceConstants.getRegisteredServices,
    ]);
    expect(state.persistentDtd, isNotNull);
    expect(state.isServiceAvailable('rohd'), isTrue);
    expect(state.lifecycleCalls, ['dtdConnected', 'available:rohd']);

    await tester.runAsync(
      () async {
        dtd.emitEvent(
          streamId: CoreDtdServiceConstants.servicesStreamId,
          eventKind: CoreDtdServiceConstants.serviceUnregisteredKind,
          eventData: const {'service': 'rohd'},
          timestamp: 1,
        );
        await Future<void>.delayed(Duration.zero);
      },
    );
    await waitForCondition(
      () => !state.isServiceAvailable('rohd'),
      'service unregistration',
    );

    expect(state.isServiceAvailable('rohd'), isFalse);
    expect(state.lifecycleCalls.last, 'unavailable:rohd');

    await tester.runAsync(
      () async {
        dtd.emitEvent(
          streamId: ConnectedAppServiceConstants.serviceName,
          eventKind: ConnectedAppServiceConstants.vmServiceUnregistered,
          eventData: const {
            DtdParameters.exposedUri: 'ws://ours:8181/app=/ws',
          },
          timestamp: 2,
        );
        await Future<void>.delayed(Duration.zero);
      },
    );
    await waitForCondition(() => state.isVmDead, 'VM unregistration');

    expect(state.isVmDead, isTrue);
    expect(state.lifecycleCalls.last, 'dead');

    state.stopDtdListenerForTest();
    await tester.pump();

    expect(state.persistentDtd, isNull);
    expect(state.lifecycleCalls.last, 'dtdDisconnected');
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

  testWidgets('DTD reconnect uses lightweight path for the same URI',
      (tester) async {
    final replacementVmService = newVmService();
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(
        vmService: replacementVmService,
        isolateId: 'isolate-1',
      ),
    ]);
    final state = await pumpHost(tester, strategy: strategy);
    state.configureTrackedVmForTest(
      uri: 'ws://host:8181/app=/ws',
      isolateId: 'isolate-1',
      name: 'counter',
      autoReconnect: true,
    );

    await state.reconnectFromDtdEventForTest('ws://host:8181/app=/ws');
    await tester.pump();

    expect(strategy.connectedUris, ['ws://host:8181/app=/ws']);
    expect(state.vmService, replacementVmService);
    expect(state.isVmDead, isFalse);
    expect(state.lifecycleCalls, ['lightweight:ws://host:8181/app=/ws']);
  });

  testWidgets('DTD registered event triggers full reconnect for new URI',
      (tester) async {
    final replacementVmService = newVmService();
    final strategy = _TestConnectionStrategy([
      VmConnectionResult(
        vmService: replacementVmService,
        isolateId: 'isolate-2',
      ),
    ]);
    final state = await pumpHost(tester, strategy: strategy);
    state.configureTrackedVmForTest(
      uri: 'ws://old:8181/app=/ws',
      isolateId: 'isolate-1',
      name: 'counter',
      autoReconnect: true,
    );

    await state.handleDtdVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {
          DtdParameters.name: 'counter',
          DtdParameters.exposedUri: 'ws://new:8181/app=/ws',
        },
        1,
      ),
    );
    await tester.pump();

    expect(strategy.connectedUris, ['ws://new:8181/app=/ws']);
    expect(state.vmServiceUriController.text, 'ws://new:8181/app=/ws');
    expect(state.connectedVmName, 'counter');
    expect(state.autoReconnect, isTrue);
    expect(state.isVmDead, isFalse);
    expect(
      state.lifecycleCalls,
      [
        'tearDown:sameVmRestart',
        'before:sameVmRestart',
        'connected:ws://new:8181/app=/ws',
      ],
    );
  });

  testWidgets('DTD registered events without a matching target are ignored',
      (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
    );
    state.configureTrackedVmForTest(
      uri: 'ws://ours:8181/app=/ws',
      isolateId: 'isolate-1',
      name: 'counter',
      autoReconnect: true,
    );

    await state.handleDtdVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {DtdParameters.name: 'other'},
        1,
      ),
    );
    await state.handleDtdVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {DtdParameters.name: 'counter'},
        2,
      ),
    );

    expect(state.isVmDead, isFalse);
    expect(state.lifecycleCalls, isEmpty);
  });

  testWidgets('DTD unregister marks only the tracked VM dead', (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
    );
    state.configureTrackedVmForTest(
      uri: 'ws://ours:8181/app=/ws',
      isolateId: 'isolate-1',
    );

    await state.handleDtdVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceUnregistered,
        {DtdParameters.uri: 'ws://other:8181/app=/ws'},
        1,
      ),
    );
    expect(state.isVmDead, isFalse);
    expect(state.lifecycleCalls, isEmpty);

    await state.handleDtdVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceUnregistered,
        {DtdParameters.exposedUri: 'ws://ours:8181/app=/ws'},
        2,
      ),
    );
    await tester.pump();

    expect(state.isVmDead, isTrue);
    expect(state.lifecycleCalls, ['dead']);
  });

  testWidgets('DTD events are ignored while paused or connecting',
      (tester) async {
    final state = await pumpHost(
      tester,
      strategy: _TestConnectionStrategy(const []),
    );
    state.configureTrackedVmForTest(
      uri: 'ws://ours:8181/app=/ws',
      isolateId: 'isolate-1',
      paused: true,
    );

    await state.handleDtdVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceUnregistered,
        {DtdParameters.uri: 'ws://ours:8181/app=/ws'},
        1,
      ),
    );
    expect(state.isVmDead, isFalse);

    state.configureTrackedVmForTest(
      uri: 'ws://ours:8181/app=/ws',
      isolateId: 'isolate-1',
      connecting: true,
    );
    await state.handleDtdVmEventForTest(
      DTDEvent(
        ConnectedAppServiceConstants.serviceName,
        ConnectedAppServiceConstants.vmServiceRegistered,
        {DtdParameters.name: 'ours'},
        2,
      ),
    );

    expect(state.isVmDead, isFalse);
    expect(state.lifecycleCalls, isEmpty);
  });
}
