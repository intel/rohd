// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// connection_state_machine_test.dart
// Tests for VM connection lifecycle state transitions.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/connection_state_machine.dart';
import 'package:vm_service/vm_service.dart';

class _MockVmService extends Mock implements VmService {}

void main() {
  group('DataLoadState', () {
    test('copies independently and resets every flag', () {
      final state = DataLoadState(
        hierarchyLoaded: true,
        schematicLoaded: true,
        waveformDataLoaded: true,
        hierarchyAttempted: true,
      );

      final copy = state.copy();
      state.reset();

      expect(state.isEmpty, isTrue);
      expect(state.hierarchyAttempted, isFalse);
      expect(copy.isFullyLoaded, isTrue);
      expect(copy.schematicLoaded, isTrue);
      expect(copy.waveformDataLoaded, isTrue);
      expect(copy.hierarchyAttempted, isTrue);
    });
  });

  group('VmIdentity', () {
    test('identifies processes by isolate ID rather than service URI', () {
      const first = VmIdentity(uri: 'ws://localhost:8181', isolateId: 'iso-1');
      const sameProcess = VmIdentity(
        uri: 'ws://localhost:9191',
        isolateId: 'iso-1',
      );
      const otherProcess = VmIdentity(
        uri: 'ws://localhost:8181',
        isolateId: 'iso-2',
      );

      expect(first.isSameProcess(sameProcess), isTrue);
      expect(first.isSameProcess(otherProcess), isFalse);
    });
  });

  group('ConnectionStateMachine', () {
    test('moves from a connection request back to disconnected on failure', () {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);

      machine.handleEvent(const ConnectRequested('ws://localhost:8181'));
      expect(machine.phase, ConnectionPhase.connecting);

      machine.handleEvent(const ConnectionFailed('connection refused'));
      expect(machine.phase, ConnectionPhase.disconnected);
      expect(machine.dataState.isEmpty, isTrue);
    });

    test('records hierarchy load results', () {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);

      machine.handleEvent(const HierarchyLoadResult(success: false));
      expect(machine.dataState.hierarchyAttempted, isTrue);
      expect(machine.dataState.hierarchyLoaded, isFalse);
      expect(machine.dataState.isFullyLoaded, isFalse);

      machine.handleEvent(const HierarchyLoadResult(success: true));
      expect(machine.dataState.isFullyLoaded, isTrue);
    });

    test('preserves data when resuming the same VM process', () {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);
      final service = _MockVmService();
      const identity =
          VmIdentity(uri: 'ws://localhost:8181', isolateId: 'iso-1');

      machine
        ..handleEvent(ConnectionEstablished(service, identity))
        ..handleEvent(const HierarchyLoadResult(success: true))
        ..markSchematicLoaded()
        ..markWaveformDataLoaded()
        ..handleEvent(const PauseRequested());

      expect(machine.phase, ConnectionPhase.paused);
      expect(machine.dataState.isFullyLoaded, isTrue);
      expect(machine.dataState.schematicLoaded, isTrue);
      expect(machine.dataState.waveformDataLoaded, isTrue);

      machine
        ..handleEvent(const ResumeRequested())
        ..handleEvent(ConnectionEstablished(service, identity));

      expect(machine.phase, ConnectionPhase.connected);
      expect(machine.shouldSkipHierarchyReload(identity), isTrue);
      expect(machine.dataState.isFullyLoaded, isTrue);
      expect(machine.dataState.schematicLoaded, isTrue);
      expect(machine.dataState.waveformDataLoaded, isTrue);
    });

    test('clears cached data when the user disconnects', () {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);
      final service = _MockVmService();
      const identity =
          VmIdentity(uri: 'ws://localhost:8181', isolateId: 'iso-1');

      machine
        ..handleEvent(ConnectionEstablished(service, identity))
        ..handleEvent(const HierarchyLoadResult(success: true))
        ..markSchematicLoaded()
        ..markWaveformDataLoaded()
        ..handleEvent(const DisconnectRequested());

      expect(machine.phase, ConnectionPhase.disconnected);
      expect(machine.currentIdentity, isNull);
      expect(machine.lastIdentity, identity);
      expect(machine.dataState.isEmpty, isTrue);
      expect(machine.shouldSkipHierarchyReload(identity), isFalse);
    });

    test('preserves cached data across VM death and recovery', () {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);
      final service = _MockVmService();
      const identity =
          VmIdentity(uri: 'ws://localhost:8181', isolateId: 'iso-1');

      machine
        ..handleEvent(ConnectionEstablished(service, identity))
        ..handleEvent(const HierarchyLoadResult(success: true))
        ..markSchematicLoaded()
        ..handleEvent(const VmDied());

      expect(machine.phase, ConnectionPhase.vmDead);
      expect(machine.lastIdentity, identity);
      expect(machine.dataState.isFullyLoaded, isTrue);
      expect(machine.dataState.schematicLoaded, isTrue);

      machine.handleEvent(const VmRecovered());

      expect(machine.phase, ConnectionPhase.connected);
      expect(machine.dataState.isFullyLoaded, isTrue);
    });

    test('treats DTD unregistration as VM death', () {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);

      machine.handleEvent(const DtdVmUnregistered());

      expect(machine.phase, ConnectionPhase.vmDead);
    });

    test('debounces hierarchy loads requested by debug pauses', () async {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);
      var loads = 0;
      machine
        ..onLoadHierarchy = () async {
          loads++;
        }
        ..handleEvent(
          ConnectionEstablished(
            _MockVmService(),
            const VmIdentity(uri: 'ws://localhost:8181', isolateId: 'iso-1'),
          ),
        )
        ..handleEvent(const DebugPauseReceived('PauseBreakpoint'))
        ..handleEvent(const DebugPauseReceived('PauseException'));

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(loads, 1);
    });

    test('enters demo mode with its hierarchy and schematic data available',
        () {
      final machine = ConnectionStateMachine();
      addTearDown(machine.dispose);

      machine.handleEvent(const DemoModeEntered());

      expect(machine.phase, ConnectionPhase.connected);
      expect(machine.currentIdentity, isNull);
      expect(machine.dataState.isFullyLoaded, isTrue);
      expect(machine.dataState.schematicLoaded, isTrue);
      expect(machine.canLoadData, isFalse);
    });
  });
}
