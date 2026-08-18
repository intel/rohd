// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_connection_form_test.dart
// Tests for VM connection form user workflows.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/vm_connection_form.dart';

void main() {
  Future<void> pumpForm(
    WidgetTester tester, {
    required TextEditingController vmUriController,
    required TextEditingController dtdUriController,
    required VoidCallback onConnect,
    DiscoverVmServicesCallback? discoverVmServices,
    List<DiscoveredVmService>? initialServices,
    ValueChanged<List<DiscoveredVmService>>? onServicesDiscovered,
    bool showDemoButton = false,
    VoidCallback? onDemoMode,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VmConnectionForm(
              vmServiceUriController: vmUriController,
              dtdUriController: dtdUriController,
              onConnect: onConnect,
              cleanVmServiceUri: (uri) => uri.trim(),
              cleanDtdUri: (uri) => uri.trim(),
              discoverVmServices: discoverVmServices,
              initialDiscoveredServices: initialServices,
              onServicesDiscovered: onServicesDiscovered,
              showDemoButton: showDemoButton,
              onDemoMode: onDemoMode,
            ),
          ),
        ),
      );

  testWidgets('cleans the manual URI before requesting a connection',
      (tester) async {
    final vmUriController =
        TextEditingController(text: ' ws://host:8181/app=/ws ');
    final dtdUriController = TextEditingController();
    addTearDown(vmUriController.dispose);
    addTearDown(dtdUriController.dispose);
    var connections = 0;

    await pumpForm(
      tester,
      vmUriController: vmUriController,
      dtdUriController: dtdUriController,
      onConnect: () => connections++,
    );

    await tester.tap(find.text('Connect'));

    expect(vmUriController.text, 'ws://host:8181/app=/ws');
    expect(connections, 1);
  });

  testWidgets('discovers and auto-selects a single VM service', (tester) async {
    final vmUriController = TextEditingController();
    final dtdUriController = TextEditingController();
    addTearDown(vmUriController.dispose);
    addTearDown(dtdUriController.dispose);
    final discovered = <List<DiscoveredVmService>>[];
    final service = DiscoveredVmService(
      name: 'counter',
      uri: 'ws://internal:8181/app=/ws',
      exposedUri: 'ws://forwarded:8181/app=/ws',
    );

    await pumpForm(
      tester,
      vmUriController: vmUriController,
      dtdUriController: dtdUriController,
      onConnect: () {},
      discoverVmServices: (dtdUri) async {
        expect(dtdUri, 'ws://host:8181/dtd=');
        return [service];
      },
      onServicesDiscovered: discovered.add,
    );

    await tester.enterText(
      find.byType(TextField).first,
      ' ws://host:8181/dtd= ',
    );
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    expect(find.text('1 VM service(s) found:'), findsOneWidget);
    expect(find.text('counter'), findsOneWidget);
    expect(vmUriController.text, 'ws://forwarded:8181/app=/ws');
    expect(service.autoReconnect, isTrue);
    expect(discovered.single, [service]);
  });

  testWidgets('connects to live services but only fills ended service URIs',
      (tester) async {
    final vmUriController = TextEditingController();
    final dtdUriController = TextEditingController();
    addTearDown(vmUriController.dispose);
    addTearDown(dtdUriController.dispose);
    var connections = 0;
    final liveService = DiscoveredVmService(
      name: 'live VM',
      uri: 'ws://live:8181/app=/ws',
    );
    final endedService = DiscoveredVmService(
      name: 'ended VM',
      uri: 'ws://ended:8181/app=/ws',
      isAlive: false,
    );

    await pumpForm(
      tester,
      vmUriController: vmUriController,
      dtdUriController: dtdUriController,
      onConnect: () => connections++,
      initialServices: [liveService, endedService],
    );

    await tester.tap(find.text('live VM'));
    expect(vmUriController.text, liveService.connectionUri);
    expect(connections, 1);

    await tester.tap(find.text('ended VM'));
    expect(vmUriController.text, endedService.connectionUri);
    expect(connections, 1);
    expect(find.textContaining('(ended)'), findsOneWidget);
  });

  testWidgets('explains when DTD discovery finds no VM services',
      (tester) async {
    final vmUriController = TextEditingController();
    final dtdUriController = TextEditingController();
    addTearDown(vmUriController.dispose);
    addTearDown(dtdUriController.dispose);

    await pumpForm(
      tester,
      vmUriController: vmUriController,
      dtdUriController: dtdUriController,
      onConnect: () {},
      discoverVmServices: (dtdUri) async => const [],
    );

    await tester.enterText(
      find.byType(TextField).first,
      'ws://host:8181/dtd=',
    );
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    expect(
      find.text('No VM services found. Is your app running?'),
      findsOneWidget,
    );
  });

  testWidgets('invokes the optional demo mode command', (tester) async {
    final vmUriController = TextEditingController();
    final dtdUriController = TextEditingController();
    addTearDown(vmUriController.dispose);
    addTearDown(dtdUriController.dispose);
    var demoRequests = 0;

    await pumpForm(
      tester,
      vmUriController: vmUriController,
      dtdUriController: dtdUriController,
      onConnect: () {},
      showDemoButton: true,
      onDemoMode: () => demoRequests++,
    );

    await tester.tap(find.text('Continue without Connection (Demo examples)'));

    expect(demoRequests, 1);
  });
}
