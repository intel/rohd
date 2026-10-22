// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_extension_client.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/source_navigation_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_signal_value_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_transport.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/waveform_signal_value_source.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdSourceFormat;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';
import 'package:vm_service/vm_service.dart' as vm;

import 'support/filter_bank_vm_target.dart';

List<SignalOccurrence> _trackedSignals(HierarchyOccurrence root) {
  root.buildAddresses();
  return root
      .depthFirstSignals()
      .where((signal) => !signal.isComputed)
      .take(3)
      .toList();
}

Future<int> _waitForWaveformTime(VmServiceTransport transport) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final time = await transport.getCurrentTime();
    if (time != null && time > 0) {
      return time;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('FilterBank VM target did not record waveform data');
}

void main() {
  test(
    'queries a real FilterBank target through the VM service adapters',
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
      expect(root?.name, 'FilterBank');

      final schematic = treeSource.getSchematicJson();
      expect(schematic?['modules'], isA<Map<String, dynamic>>());
      final definitionName =
          (schematic!['modules'] as Map<String, dynamic>).keys.first;
      final module = await treeSource.fetchModuleSchematic(definitionName);
      expect(module, contains(definitionName));

      final transport = VmServiceTransport(
        vmService: connection.vmService,
        isolateId: connection.isolateId,
      );
      addTearDown(transport.dispose);

      final currentTime = await _waitForWaveformTime(transport);

      final isolate = await connection.vmService.getIsolate(
        connection.isolateId,
      );
      final rohdLibrary =
          (isolate.libraries ?? const <vm.LibraryRef>[]).firstWhere(
        (library) => library.uri?.contains('module_services') ?? false,
      );
      final valueSource = VmServiceSignalValueSource(
        rohdControllerEval: EvalOnDartLibrary(
          rohdLibrary.uri!,
          connection.vmService,
          serviceManager: ServiceManager<vm.VmService>(),
        ),
        evalDisposable: Disposable(),
        vmService: connection.vmService,
        evalInstance: (expression, {required isAlive}) async {
          final result = await connection.vmService.evaluate(
            connection.isolateId,
            rohdLibrary.id!,
            expression,
          );
          if (result is vm.Instance) {
            return result;
          }
          if (result is vm.InstanceRef && result.id != null) {
            final object = await connection.vmService.getObject(
              connection.isolateId,
              result.id!,
            );
            if (object is vm.Instance) {
              return object;
            }
          }
          throw StateError('VM evaluation did not return a string instance');
        },
      );
      addTearDown(valueSource.dispose);
      expect(await valueSource.getCurrentTime(), currentTime);
      final valueSourceSnapshot = await valueSource.getSnapshot(currentTime);
      expect(valueSourceSnapshot, isNotNull);
      expect(valueSourceSnapshot, isNotEmpty);

      final snapshot = await transport.getSnapshotCompact(currentTime);
      expect(snapshot?['v'], isA<Map<String, dynamic>>());
      expect(snapshot!['v'] as Map<String, dynamic>, isNotEmpty);

      final transportTree = await transport.getModuleTree();
      expect(transportTree?['netlist'], isA<Map<String, dynamic>>());
      final transportModule = await transport.getModuleNetlist(definitionName);
      expect(transportModule, contains(definitionName));

      final signals = _trackedSignals(root!);
      expect(signals, isNotEmpty);
      final addressToSignalId = {
        for (final signal in signals)
          if (signal.address != null)
            signal.address!.toDotString(): signal.path(),
      };
      final waveforms = await transport.getWaveformDataCompact(
        signalAddresses: addressToSignalId.keys.toList(),
        addressToSignalId: addressToSignalId,
      );
      expect(waveforms, isNotEmpty);
      expect(waveforms.any((waveform) => waveform.data.isNotEmpty), isTrue);
      final incrementalWaveforms =
          await transport.getWaveformDataWithTimepointsCompact(
        signalTimepoints: {
          for (final address in addressToSignalId.keys) address: 0,
        },
        addressToSignalId: addressToSignalId,
      );
      expect(incrementalWaveforms, isNotEmpty);

      addressToSignalId.values.forEach(transport.trackSignal);
      expect(
        transport.trackedSignalKeys,
        containsAll(addressToSignalId.values),
      );
      final firstTrackedSignal = addressToSignalId.values.first;
      expect(transport.getLastTrackedTimepoint(firstTrackedSignal), -1);
      transport.untrackSignal(firstTrackedSignal);
      expect(transport.trackedSignalKeys, isNot(contains(firstTrackedSignal)));
      transport.trackSignal(firstTrackedSignal);
      final timeUpdate = transport.liveUpdates.first;
      await transport.fetchAndEmitCurrentTime();
      expect((await timeUpdate).upToTime, currentTime);
      transport.pauseFetches();
      expect(transport.fetchesPaused, isTrue);
      final resumedUpdate = transport.liveUpdates.first;
      await transport.resumeFetches();
      expect(transport.fetchesPaused, isFalse);
      expect((await resumedUpdate).incrementalData, isNotEmpty);
      transport.untrackAllSignals();
      expect(transport.trackedSignalKeys, isEmpty);

      final waveformApi = VmServiceSignalWaveformApi(transport)
        ..schematicModules = schematic['modules'] as Map<String, dynamic>
        ..fetchModuleSchematic = treeSource.fetchModuleSchematic;
      await waveformApi.setExternalStructure(
        ModuleStructure(metadata: MetaData.empty(), modules: [root]),
      );

      final expandedSnapshot = await waveformApi.getSnapshot(currentTime);
      expect(expandedSnapshot, isNotNull);
      expect(expandedSnapshot, isNotEmpty);
      final waveformValueSource = WaveformSignalValueSource(api: waveformApi);
      expect(await waveformValueSource.getCurrentTime(), currentTime);
      expect(await waveformValueSource.getSnapshot(currentTime), isNotEmpty);

      final updateTransport = VmServiceTransport(
        vmService: connection.vmService,
        isolateId: connection.isolateId,
      );
      addTearDown(updateTransport.dispose);
      final updateSource = WaveformSignalValueSource(
        api: waveformApi,
        liveUpdates: updateTransport.liveUpdates,
      );
      final mappedUpdate = updateSource.updates!.first;
      await updateTransport.fetchAndEmitCurrentTime();
      final update = await mappedUpdate;
      expect(update.upToTime, currentTime);
      expect(update.hasData, isFalse);
      expect(update.reason, WaveformUpdateReason.breakpoint.name);

      final signalIds = signals.map((signal) => signal.path()).toList();
      final apiWaveforms = await waveformApi.getWaveformData(
        signalIds: signalIds,
      );
      expect(apiWaveforms, isNotEmpty);
      expect(apiWaveforms.any((waveform) => waveform.data.isNotEmpty), isTrue);
      expect(transport.trackedSignalKeys, containsAll(signalIds));

      final expanded = await waveformApi.ensureFullModules(signalIds.first);
      expect(expanded, isTrue);
      final evaluator = NetlistEvaluator(
        schematic['modules'] as Map<String, dynamic>,
      );
      final evaluablePaths =
          evaluator.allEvaluablePaths(root.path()).where(evaluator.canEvaluate);
      expect(evaluablePaths, isNotEmpty);
      String? snapshotLookup(String path) =>
          expandedSnapshot![path]?['value'] as String?;
      final evaluated = evaluator.evaluateBatch(
        evaluablePaths,
        snapshotLookup,
      );
      expect(evaluated, isNotEmpty);
      final leafBackedPath = evaluablePaths.firstWhere(
        (path) => evaluator.collectLeaves(path).isNotEmpty,
      );
      expect(evaluator.isComputed(leafBackedPath), isTrue);
      expect(evaluator.signalWidth(leafBackedPath), greaterThan(0));
      expect(evaluator.collectLeaves(leafBackedPath), isNotEmpty);
      evaluator.clearValues();
      expect(
        evaluator.evaluate(leafBackedPath, snapshotLookup),
        isNotNull,
      );
      evaluator.reset();
      final sharedEvaluator = NetlistEvaluator(
        schematic['modules'] as Map<String, dynamic>,
        evaluator.cache.withSharedStructure(),
      );
      expect(
        sharedEvaluator.evaluate(leafBackedPath, snapshotLookup),
        isNotNull,
      );
      await transport.requestGarbageCollection();
      await transport.reconnect(
        connection.vmService,
        connection.isolateId,
        preserveTracking: true,
      );
      expect(transport.trackedSignalKeys, contains(signalIds.first));
      await transport.reconnect(
        connection.vmService,
        connection.isolateId,
      );
      expect(transport.trackedSignalKeys, isEmpty);
      final disposedTransport = VmServiceTransport(
        vmService: connection.vmService,
        isolateId: connection.isolateId,
      );
      await disposedTransport.dispose();
      expect(disposedTransport.isConnected, isFalse);
      expect(await disposedTransport.getCurrentTime(), isNull);
      expect(await disposedTransport.getSnapshotCompact(currentTime), isNull);
      expect(
        await disposedTransport.getWaveformDataCompact(
          signalAddresses: addressToSignalId.keys.toList(),
          addressToSignalId: addressToSignalId,
        ),
        isEmpty,
      );
      expect(
        await disposedTransport.getWaveformDataWithTimepointsCompact(
          signalTimepoints: {
            for (final address in addressToSignalId.keys) address: -1,
          },
          addressToSignalId: addressToSignalId,
        ),
        isEmpty,
      );
      expect(await disposedTransport.getModuleTree(), isNull);
      expect(
        await disposedTransport.getModuleNetlist(definitionName),
        isNull,
      );

      final flcHierarchy = await treeSource.fetchFlcHierarchy();
      expect(flcHierarchy?['version'], 6);
      final flcModules = flcHierarchy?['modules'];
      expect(flcModules, isA<Map<String, dynamic>>());
      final flcDefinition = (flcModules! as Map<String, dynamic>).keys.first;
      final flcModule = await treeSource.fetchModuleFlc(flcDefinition);
      expect(flcModule?['modules'], contains(flcDefinition));
      expect(
        await treeSource.fetchModuleFlc(flcDefinition),
        same(flcModule),
      );
      treeSource.clearFlcCache();
      expect(
        (await treeSource.fetchModuleFlc(flcDefinition))?['modules'],
        contains(flcDefinition),
      );
      expect(await treeSource.fetchFlcFilePath(), isNull);
      expect(
        await treeSource.fetchSourceLine('does/not/exist.dart', 1),
        isNull,
      );
      expect((await treeSource.refreshModuleTree())?.name, root.name);

      final flcService = FlcService(
        fetchModuleFlc: treeSource.fetchModuleFlc,
        fetchFlcHierarchy: treeSource.fetchFlcHierarchy,
        fetchFlcFilePath: treeSource.fetchFlcFilePath,
        onClearCache: treeSource.clearFlcCache,
      );
      expect(
        await flcService.getModuleFormats(flcDefinition),
        contains('rohd'),
      );
      final extensionClient = FlcExtensionClient(flcService: flcService);
      addTearDown(extensionClient.dispose);
      expect(await extensionClient.ping(), isTrue);
      final extensionInfo = await extensionClient.queryModule(flcDefinition);
      expect(extensionInfo.extensionAvailable, isTrue);
      expect(extensionInfo.formats.keys, contains(RohdSourceFormat.rohd));
      final fallbackInfo = await extensionClient.queryModule(
        'not-a-filter-bank-definition',
        instancePath: [flcDefinition],
      );
      expect(fallbackInfo.formats.keys, contains(RohdSourceFormat.rohd));
      expect(
        await extensionClient.lookupSignalFrames(signals: const []),
        isEmpty,
      );
      extensionClient.openSourceLocation(
        file: 'example/filter_bank/filter_bank.dart',
        line: 1,
      );

      var lookupPath = '';
      var frames = const <SourceFrame>[];
      for (final signal in root.depthFirstSignals()) {
        frames = await flcService.resolveSignal(flcDefinition, signal.name);
        if (frames.isNotEmpty) {
          lookupPath = '$flcDefinition/${signal.name}';
          break;
        }
      }
      expect(lookupPath, isNotEmpty);
      expect(frames, isNotEmpty);
      final sourceLine = await treeSource.fetchSourceLine(
        frames.first.file,
        frames.first.line,
      );
      expect(sourceLine, isNotNull);
      expect(sourceLine!.trim(), isNotEmpty);
      expect(await treeSource.fetchSourceLine(frames.first.file, 0), isNull);

      final sourceNavigation = SourceNavigationService()
        ..setFlcService(flcService)
        ..sourceLineFetcher = treeSource.fetchSourceLine;
      final enrichedFrames = await sourceNavigation.resolveSourceFrames(
        [lookupPath],
      );
      expect(enrichedFrames, isNotEmpty);
      expect(enrichedFrames.first.label, contains(':'));
      expect(enrichedFrames.first.methodName, isNotNull);

      expect(
        await sourceNavigation.goToSourceFromPaths([lookupPath]),
        isFalse,
      );
      expect(
        await sourceNavigation.goToSourceFromSignals([
          {
            'module': flcDefinition,
            'name': lookupPath.substring(lookupPath.lastIndexOf('/') + 1),
          },
        ]),
        isFalse,
      );
      expect(
        await sourceNavigation.navigateToFrame(enrichedFrames, 0),
        isFalse,
      );
      expect(
        await sourceNavigation.navigateToFormat(
          enrichedFrames,
          0,
          RohdSourceFormat.rohd,
        ),
        isFalse,
      );
      sourceNavigation
        ..clearSourceLineFetcher()
        ..clearFlcService();
      expect(sourceNavigation.isAvailable, isFalse);

      final shellTarget = VmServiceRohdDesignTarget(
        connection.vmService,
        connection.isolateId,
      );
      final shellResponse = await shellTarget.command(
        'filter-bank-vm-workflow',
        'find-ports .*',
      );
      expect(shellResponse['ok'], isTrue);
      expect(shellResponse['result'], isNotNull);
      final completions = await shellTarget.complete(
        'filter-bank-vm-workflow',
        'find',
        4,
      );
      expect(completions['ok'], isTrue);
      expect(completions['items'], isA<List<Object?>>());
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
