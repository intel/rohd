// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_backed_connection_host_workflow_test.dart
// Tests VM-backed connection-host workflows.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/devtools_connection_host.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/vm_connection_form.dart';

import 'support/filter_bank_vm_target.dart';

class _PreparedVmConnectionStrategy extends VmConnectionStrategy {
  _PreparedVmConnectionStrategy(this.result);

  final VmConnectionResult result;
  final connectedUris = <String>[];

  @override
  Future<VmConnectionResult> connect(String uri) async {
    connectedUris.add(uri);
    return result;
  }
}

class _FailingVmConnectionStrategy extends VmConnectionStrategy {
  int attempts = 0;

  @override
  Future<VmConnectionResult> connect(String uri) async {
    attempts++;
    throw Exception('simulated connection failure');
  }
}

class _LiveConnectionHost extends StatefulWidget {
  const _LiveConnectionHost({required this.strategy});

  final VmConnectionStrategy? strategy;

  @override
  State<_LiveConnectionHost> createState() => _LiveConnectionHostState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<VmConnectionStrategy?>('strategy', strategy),
    );
  }
}

class _LiveConnectionHostState
    extends DevToolsConnectionHostState<_LiveConnectionHost> {
  final lifecycleCalls = <String>[];
  VmConnectionResult? connectedResult;
  int demoModeRequests = 0;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IterableProperty<String>('lifecycleCalls', lifecycleCalls))
      ..add(
        DiagnosticsProperty<VmConnectionResult?>(
          'connectedResult',
          connectedResult,
        ),
      )
      ..add(IntProperty('demoModeRequests', demoModeRequests));
  }

  @override
  VmConnectionStrategy? get connectionStrategy => widget.strategy;

  @override
  Future<void> startDtdListener() async {}

  @override
  Future<void> onBeforeVmConnected(
    VmConnectionResult result,
    String uri, {
    required VmConnectionTransition transition,
  }) async {
    lifecycleCalls.add('before:${transition.kind.name}');
  }

  @override
  Future<void> onVmConnected(VmConnectionResult result, String uri) async {
    connectedResult = result;
    lifecycleCalls.add('connected:$uri');
  }

  @override
  Future<void> tearDownOldConnection({
    required VmConnectionTransition transition,
  }) async {
    lifecycleCalls.add('tearDown:${transition.kind.name}');
  }

  @override
  Future<void> onLightweightReconnectSuccess(
    VmConnectionResult result,
    String uri,
  ) async {
    lifecycleCalls.add('lightweight:$uri');
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
  void onDemoModeRequested() {
    demoModeRequests++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isConnected ? 'connected' : 'disconnected'),
              ElevatedButton(
                onPressed: showConnectionDialog,
                child: const Text('Open VM connection'),
              ),
            ],
          ),
        ),
      );
}

void main() {
  testWidgets(
    'connects a real FilterBank VM through the host connection form',
    (tester) async {
      final target = await tester.runAsync(startFilterBankVmTarget);
      expect(target, isNotNull);
      final vmTarget = target!;
      addTearDown(vmTarget.dispose);

      final ioStrategy = IoVmConnectionStrategy(
        retryDelay: const Duration(milliseconds: 50),
      );
      final connectionUri = ioStrategy.normalizeUri(vmTarget.serviceUri);
      expect(connectionUri, isNotNull);
      final connection = await tester.runAsync(
        () => ioStrategy.connect(connectionUri!.toString()),
      );
      expect(connection, isNotNull);
      final vmConnection = connection!;
      addTearDown(vmConnection.vmService.dispose);
      final strategy = _PreparedVmConnectionStrategy(vmConnection);

      await tester.pumpWidget(
        MaterialApp(home: _LiveConnectionHost(strategy: strategy)),
      );
      final state = tester.state<_LiveConnectionHostState>(
        find.byType(_LiveConnectionHost),
      );
      expect(find.text('disconnected'), findsOneWidget);

      await tester.tap(find.text('Open VM connection'));
      await tester.pumpAndSettle();
      final connectionForm = find.byType(VmConnectionForm);
      expect(connectionForm, findsOneWidget);
      final formFields = find.descendant(
        of: connectionForm,
        matching: find.byType(TextField),
      );
      expect(formFields, findsNWidgets(2));
      await tester.enterText(formFields.at(1), ' $connectionUri ');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.byType(VmConnectionForm), findsNothing);
      expect(find.text('connected'), findsOneWidget);
      expect(strategy.connectedUris, [connectionUri.toString()]);
      expect(state.vmService, vmConnection.vmService);
      expect(state.lastIsolateId, vmConnection.isolateId);
      expect(
        state.lifecycleCalls,
        [
          'tearDown:freshAttach',
          'before:freshAttach',
          'connected:$connectionUri',
        ],
      );

      await state.pauseVm();
      await tester.pump();
      expect(state.isPaused, isTrue);
      await state.resumeVm();
      await tester.pump();
      expect(state.isPaused, isFalse);

      await state.disconnect();
      await tester.pump();
      expect(find.text('disconnected'), findsOneWidget);
      expect(
        state.lifecycleCalls,
        [
          'tearDown:freshAttach',
          'before:freshAttach',
          'connected:$connectionUri',
          'paused',
          'resumed',
          'tearDown:disconnect',
          'disconnected',
        ],
      );
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );

  testWidgets(
    'surfaces manual connection failures and demo mode without DTD',
    (tester) async {
      final strategy = _FailingVmConnectionStrategy();
      await tester.pumpWidget(
        MaterialApp(home: _LiveConnectionHost(strategy: strategy)),
      );
      final state = tester.state<_LiveConnectionHostState>(
        find.byType(_LiveConnectionHost),
      );

      state.vmServiceUriController.text = 'not a VM service URI';
      await state.attemptConnection();
      await tester.pump();
      expect(
        state.connectionError,
        'Please enter a VM Service URI or DTD URI',
      );
      expect(strategy.attempts, 0);

      state.vmServiceUriController.text = 'ws://host:8181/app=/ws';
      await state.attemptConnection();
      await tester.pump();
      expect(strategy.attempts, 1);
      expect(state.connectionError, contains('simulated connection failure'));
      expect(state.isConnected, isFalse);

      await tester.tap(find.text('Open VM connection'));
      await tester.pumpAndSettle();
      expect(find.byType(VmConnectionForm), findsOneWidget);
      expect(
        find.textContaining('Connection failed: Exception:'),
        findsOneWidget,
      );
      final demoButton = find.text(
        'Continue without Connection (Demo examples)',
      );
      await tester.ensureVisible(demoButton);
      await tester.tap(demoButton);
      await tester.pumpAndSettle();
      expect(state.demoModeRequests, 1);
      expect(find.byType(VmConnectionForm), findsNothing);
    },
  );

  testWidgets(
    'reports unavailable VM connection support without opening a dialog',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _LiveConnectionHost(strategy: null)),
      );
      final state = tester.state<_LiveConnectionHostState>(
        find.byType(_LiveConnectionHost),
      );

      await tester.tap(find.text('Open VM connection'));
      await tester.pump();
      expect(
        find.text('VM connection not available on this platform'),
        findsOneWidget,
      );

      await state.attemptConnection();
      expect(
        state.connectionError,
        'VM connection not available on this platform',
      );
      expect(state.isConnected, isFalse);
    },
  );
}
