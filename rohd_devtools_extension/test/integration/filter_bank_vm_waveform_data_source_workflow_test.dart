// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank_vm_waveform_data_source_workflow_test.dart
// Tests FilterBank VM waveform data-source workflows.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_waveform_data_source.dart';

import 'support/filter_bank_vm_target.dart';

Future<int> _waitForCurrentTime(VmServiceWaveformDataSource source) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final time = await source.getCurrentTime();
    if (time != null && time > 0) {
      return time;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('FilterBank VM target did not record waveform data');
}

void main() {
  test(
    'uses compact waveform transport and tracking against a real FilterBank VM',
    () async {
      final target = await startFilterBankVmTarget();
      addTearDown(target.dispose);

      final connection = await IoVmConnectionStrategy(
        retryDelay: const Duration(milliseconds: 50),
      ).connect(target.serviceUri);
      addTearDown(connection.vmService.dispose);

      final treeSource = VmServiceTreeDataSource(
        vmService: connection.vmService,
        isolateId: connection.isolateId,
      );
      final root = await treeSource.evalModuleTree();
      expect(root, isNotNull);
      root!.buildAddresses();
      final signals = root
          .depthFirstSignals()
          .where((signal) => !signal.isComputed && signal.address != null)
          .take(3)
          .toList();
      expect(signals, hasLength(3));
      final addressToSignalId = <String, String>{
        for (final signal in signals)
          signal.address!.toDotString(): signal.path(),
      };
      final signalIdToAddress = <String, String>{
        for (final entry in addressToSignalId.entries) entry.value: entry.key,
      };

      final source = VmServiceWaveformDataSource(
        vmService: connection.vmService,
        isolateId: connection.isolateId,
      );
      addTearDown(source.dispose);
      final currentTime = await _waitForCurrentTime(source);
      expect(source.isConnected, isTrue);
      expect(source.modeDescription, contains('Live Simulation'));

      final initialUpdate = source.liveUpdates.first;
      await source.fetchAndEmitCurrentTime();
      expect((await initialUpdate).upToTime, currentTime);
      expect(source.lastFetchedTime, currentTime);

      final snapshot = await source.getSnapshotCompact(currentTime);
      expect(snapshot?['v'], isA<Map<String, dynamic>>());
      expect(snapshot!['v'] as Map<String, dynamic>, isNotEmpty);

      expect(
        await source.getWaveformData(
          signalIds: addressToSignalId.values.toList(),
        ),
        isEmpty,
      );
      expect(
        await source.getWaveformDataSince(
          signalIds: addressToSignalId.values.toList(),
          sinceTime: 0,
        ),
        isEmpty,
      );
      expect(
        await source.getWaveformDataWithTimepoints(signalTimepoints: const {}),
        isEmpty,
      );
      final legacyIncremental = await source.getWaveformDataWithTimepoints(
        signalTimepoints: {
          for (final signalId in addressToSignalId.values) signalId: -1,
        },
      );
      expect(legacyIncremental, hasLength(signals.length));

      final compactWaveforms = await source.getWaveformDataCompact(
        signalAddresses: addressToSignalId.keys.toList(),
        addressToSignalId: addressToSignalId,
      );
      expect(compactWaveforms, hasLength(signals.length));
      expect(
        compactWaveforms.every((waveform) => waveform.data.isNotEmpty),
        isTrue,
      );

      final compactIncremental =
          await source.getWaveformDataWithTimepointsCompact(
        signalTimepoints: {
          for (final address in addressToSignalId.keys) address: -1,
        },
        addressToSignalId: addressToSignalId,
      );
      expect(compactIncremental, hasLength(signals.length));

      source.setAddressLookups(
        signalIdToAddress: (signalId) => signalIdToAddress[signalId],
        addressToSignalId: (address) => addressToSignalId[address],
      );
      for (final signalId in addressToSignalId.values) {
        source.trackSignal(signalId);
        expect(source.getLastTrackedTimepoint(signalId), -1);
      }
      expect(source.trackedSignalKeys, containsAll(addressToSignalId.values));

      source.pauseFetches();
      expect(source.fetchesPaused, isTrue);
      final resumedUpdate = source.liveUpdates.first;
      await source.resumeFetches();
      expect(source.fetchesPaused, isFalse);
      expect((await resumedUpdate).incrementalData, isNotEmpty);
      expect(
        source.trackedSignalKeys.every(
          (signalId) => source.getLastTrackedTimepoint(signalId) >= 0,
        ),
        isTrue,
      );

      source.untrackSignal(signals.first.path());
      expect(source.trackedSignalKeys, isNot(contains(signals.first.path())));
      source.untrackAllSignals();
      expect(source.trackedSignalKeys, isEmpty);

      await expectLater(
        source.getSnapshot(currentTime),
        throwsUnimplementedError,
      );
      await expectLater(source.getSignalDictionary(), throwsUnimplementedError);

      await source.requestGarbageCollection();
      source.trackSignal(signals.first.path());
      await source.reconnect(
        connection.vmService,
        connection.isolateId,
        preserveTracking: true,
      );
      expect(source.trackedSignalKeys, [signals.first.path()]);
      await source.reconnect(
        connection.vmService,
        connection.isolateId,
      );
      expect(source.trackedSignalKeys, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
