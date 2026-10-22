// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/examples/rohd_examples.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/in_process_transport.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/in_process_tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/in_process_waveform_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/loopback_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/static_json_tree_data_source.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

List<SignalOccurrence> _trackedSignals(HierarchyOccurrence root) {
  root.buildAddresses();
  return root
      .depthFirstSignals()
      .where((signal) => !signal.isComputed)
      .toList();
}

void main() {
  group('FilterBank standalone loopback workflow', () {
    late Completer<void> keepAlive;
    late InProcessTreeDataSource treeSource;
    late InProcessTransport transport;
    late InProcessWaveformDataSource waveformSource;
    late LoopbackSignalWaveformApi loopbackApi;
    late HierarchyOccurrence root;
    late int currentTime;
    late List<SignalOccurrence> signals;
    late Map<String, String> addressToSignalId;

    setUpAll(() async {
      keepAlive = await launchFilterBank();
      treeSource = InProcessTreeDataSource(name: 'FilterBank integration');
      transport = InProcessTransport(name: 'FilterBank integration');
      waveformSource = InProcessWaveformDataSource(
        name: 'FilterBank integration',
      );

      root = (await treeSource.evalModuleTree())!;
      signals = _trackedSignals(root);
      addressToSignalId = {
        for (final signal in signals)
          if (signal.address != null)
            signal.address!.toDotString(): signal.path(),
      };
      currentTime = (await transport.getCurrentTime())!;

      loopbackApi = LoopbackSignalWaveformApi(transport)
        ..schematicModules = NetlistService.current?.synthesizedModules
        ..fetchModuleSchematic = treeSource.fetchModuleSchematic;
      await loopbackApi.setExternalStructure(
        ModuleStructure(metadata: MetaData.empty(), modules: [root]),
      );
    });

    tearDownAll(() async {
      if (!keepAlive.isCompleted) {
        keepAlive.complete();
      }
      await waveformSource.dispose();
      await loopbackApi.dispose();
      await treeSource.dispose();
      WaveformDataService.instance.clear();
      ModuleServices.instance.reset();
      await Simulator.reset();
    });

    test('loads hierarchy and incremental schematic data from the real design',
        () async {
      expect(root.name, 'FilterBank');
      expect(signals, isNotEmpty);

      final schematic = treeSource.getSchematicJson();
      expect(schematic, isNotNull);
      expect(schematic!['modules'], isA<Map<String, dynamic>>());

      final definitionName =
          NetlistService.current!.synthesizedModules.keys.first;
      final module = await treeSource.fetchModuleSchematic(definitionName);
      expect(module, isNotNull);
      expect(module, contains(definitionName));

      final transportTree = await transport.getModuleTree();
      expect(transportTree?['netlist'], isA<Map<String, dynamic>>());
      final transportModule = await transport.getModuleNetlist(definitionName);
      expect(transportModule, contains(definitionName));

      final refreshedRoot = await treeSource.refreshModuleTree();
      expect(refreshedRoot?.name, root.name);

      expect(await treeSource.fetchFlcHierarchy(), isNull);
      expect(await treeSource.fetchModuleFlc('FilterBank'), isNull);
      expect(await treeSource.fetchFlcFilePath(), isNull);
      treeSource.clearFlcCache();
    });

    test('serves compact and incremental waveform data through in-process APIs',
        () async {
      expect(currentTime, greaterThan(0));
      expect(
          waveformSource.modeDescription, contains('FilterBank integration'));

      final update = waveformSource.liveUpdates.first;
      await waveformSource.fetchAndEmitCurrentTime();
      expect((await update).upToTime, currentTime);

      final transportUpdate = transport.liveUpdates.first;
      await transport.fetchAndEmitCurrentTime();
      expect((await transportUpdate).upToTime, currentTime);

      final snapshot = await waveformSource.getSnapshotCompact(currentTime);
      expect(snapshot, isNotNull);
      expect(snapshot!['v'], isA<Map<String, dynamic>>());
      expect(snapshot['v'] as Map<String, dynamic>, isNotEmpty);
      expect(await waveformSource.getSnapshot(currentTime), isNull);
      expect(await waveformSource.getSignalDictionary(), isNull);

      final transportSnapshot = await transport.getSnapshotCompact(currentTime);
      expect(transportSnapshot?['v'], isA<Map<String, dynamic>>());

      final signalIds = signals.take(3).map((signal) => signal.path()).toList();
      final waveforms = await waveformSource.getWaveformData(
        signalIds: signalIds,
      );
      expect(waveforms, isNotEmpty);
      expect(waveforms.any((waveform) => waveform.data.isNotEmpty), isTrue);

      final addresses = addressToSignalId.keys.take(3).toList();
      final compactWaveforms = await waveformSource.getWaveformDataCompact(
        signalAddresses: addresses,
        addressToSignalId: addressToSignalId,
      );
      expect(compactWaveforms, isNotEmpty);
      expect(
        compactWaveforms.any((waveform) => waveform.data.isNotEmpty),
        isTrue,
      );

      final incrementalWaveforms =
          await waveformSource.getWaveformDataWithTimepointsCompact(
        signalTimepoints: {for (final address in addresses) address: 0},
        addressToSignalId: addressToSignalId,
      );
      expect(incrementalWaveforms, isNotEmpty);
      expect(
        await waveformSource.getWaveformDataSince(
          signalIds: signalIds,
          sinceTime: 0,
        ),
        isNotEmpty,
      );
      expect(
        await waveformSource.getWaveformDataWithTimepoints(
          signalTimepoints: {for (final signalId in signalIds) signalId: 0},
        ),
        isNotEmpty,
      );
    });

    test('presents the same live data through the loopback viewer API',
        () async {
      final snapshot = await loopbackApi.getSnapshot(currentTime);
      expect(snapshot, isNotNull);
      expect(snapshot, isNotEmpty);

      final signalIds = signals.take(3).map((signal) => signal.path()).toList();
      final waveforms = await loopbackApi.getWaveformData(signalIds: signalIds);
      expect(waveforms, isNotEmpty);
      expect(waveforms.any((waveform) => waveform.data.isNotEmpty), isTrue);

      final refreshed = await loopbackApi.refresh();
      expect(refreshed, isNotEmpty);
    });

    test('derives computed and bit-slice waveforms through the base API',
        () async {
      final wideSignal = signals.firstWhere(
        (signal) => !signal.isComputed && signal.width >= 4,
      );
      final snapshot = await loopbackApi.getSnapshot(currentTime);
      expect(snapshot, isNotNull);
      final computedSignalId = snapshot!.entries
          .firstWhere((entry) => entry.value['computed'] == true)
          .key;
      final bitId = '${wideSignal.path()}#b[0]';
      final rangeId = '${wideSignal.path()}#b[3:0]';

      expect(
        loopbackApi.resolveSubFieldBits(bitId),
        (startBit: 0, width: 1),
      );
      expect(
        loopbackApi.resolveSubFieldBits(rangeId),
        (startBit: 0, width: 4),
      );

      final waveforms = await loopbackApi.getWaveformData(
        signalIds: [
          wideSignal.path(),
          computedSignalId,
          bitId,
          rangeId,
        ],
      );
      expect(
        waveforms.any((waveform) => waveform.signalId == wideSignal.path()),
        isTrue,
      );
      expect(waveforms.any((waveform) => waveform.signalId == bitId), isTrue);
      expect(
        waveforms.any((waveform) => waveform.signalId == rangeId),
        isTrue,
      );
      expect(loopbackApi.cachedSignalIds, contains(wideSignal.path()));
      expect(loopbackApi.cachedSignalIds, contains(bitId));

      final streamed = await loopbackApi
          .streamWaveformData(signalIds: [wideSignal.path()]).first;
      expect(streamed.signalId, wideSignal.path());
      expect(streamed.data, isNotEmpty);
      await loopbackApi.expandAllSlimModules();
    });

    test('loads the packaged FilterBank design through the file data source',
        () async {
      final designJson = jsonDecode(
        await File('assets/FilterBank.rohd.json').readAsString(),
      ) as Map<String, dynamic>;
      final fileSource = StaticJsonTreeDataSource(
        designJson,
        name: 'FilterBank.rohd.json',
      );
      addTearDown(fileSource.dispose);

      final fileRoot = await fileSource.evalModuleTree();
      expect(fileRoot?.name, 'FilterBank');
      expect(
        fileSource.modeDescription,
        'Static JSON (FilterBank.rohd.json)',
      );

      final fileSchematic = fileSource.getSchematicJson();
      expect(fileSchematic?['modules'], isA<Map<String, dynamic>>());
      final modules = fileSchematic!['modules'] as Map<String, dynamic>;
      final definitionName = modules.keys.first;
      final module = await fileSource.fetchModuleSchematic(definitionName);
      expect(module?['modules'], contains(definitionName));

      final refreshedRoot = await fileSource.refreshModuleTree();
      expect(refreshedRoot?.name, fileRoot?.name);
    });

    test('executes design-shell commands against the live example', () async {
      const target = InProcessRohdDesignTarget();

      final response = await target.command(
        'filter-bank-workflow',
        'find-ports .*',
      );

      expect(response['result'], isA<Map<Object?, Object?>>());
    });

    test('reports unavailable values after in-process source disposal',
        () async {
      final inactiveTree = InProcessTreeDataSource();
      final inactiveTransport = InProcessTransport();
      final inactiveWaveforms = InProcessWaveformDataSource();
      await inactiveTree.dispose();
      await inactiveTransport.dispose();
      await inactiveWaveforms.dispose();

      expect(inactiveTree.isConnected, isFalse);
      expect(await inactiveTree.evalModuleTree(), isNull);
      expect(await inactiveTree.refreshModuleTree(), isNull);
      expect(await inactiveTree.fetchModuleSchematic('FilterBank'), isNull);
      expect(await inactiveTree.fetchModuleFlc('FilterBank'), isNull);
      expect(await inactiveTree.fetchFlcHierarchy(), isNull);
      expect(await inactiveTree.fetchFlcFilePath(), isNull);

      expect(inactiveTransport.isConnected, isFalse);
      expect(await inactiveTransport.getCurrentTime(), isNull);
      expect(await inactiveTransport.getSnapshotCompact(currentTime), isNull);
      expect(
        await inactiveTransport.getWaveformDataCompact(
          signalAddresses: addressToSignalId.keys.take(1).toList(),
          addressToSignalId: addressToSignalId,
        ),
        isEmpty,
      );
      expect(await inactiveTransport.getModuleTree(), isNull);
      expect(await inactiveTransport.getModuleNetlist('FilterBank'), isNull);

      expect(inactiveWaveforms.isConnected, isFalse);
      expect(await inactiveWaveforms.getCurrentTime(), isNull);
      expect(await inactiveWaveforms.getSnapshotCompact(currentTime), isNull);
      expect(
        await inactiveWaveforms.getWaveformData(
          signalIds: [signals.first.path()],
        ),
        isEmpty,
      );
      expect(
        await inactiveWaveforms.getWaveformDataWithTimepointsCompact(
          signalTimepoints: const {'0': 0},
          addressToSignalId: const {'0': 'FilterBank/clk'},
        ),
        isEmpty,
      );
    });
  });
}
