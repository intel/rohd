// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/design_query_language.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_shell_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/waveform_cli.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_transport.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/vm_service_waveform_data_source.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show LocalCrossProbeChannel, LocalCrossProbeService;
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

import 'support/filter_bank_vm_target.dart';

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
    'runs hierarchy, waveform, and shell CLI commands against FilterBank',
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
      final schematic = treeSource.getSchematicJson();
      expect(schematic?['modules'], isA<Map<String, dynamic>>());

      final transport = VmServiceTransport(
        vmService: connection.vmService,
        isolateId: connection.isolateId,
      );
      addTearDown(transport.dispose);
      final currentTime = await _waitForWaveformTime(transport);

      final hierarchyCli = DesignTraversalCli(root);
      final clockSignals = hierarchyCli.findSignals('clk');
      expect(clockSignals, isNotEmpty);
      final clock = clockSignals.first;
      expect(clock.address, isNotNull);
      expect(hierarchyCli.resolveSignal(clock.address!), isNotNull);
      expect(hierarchyCli.resolveSignal('not/a/signal'), isNull);

      final waveformDataSource = VmServiceWaveformDataSource(
        vmService: connection.vmService,
        isolateId: connection.isolateId,
      );
      addTearDown(waveformDataSource.dispose);
      final waveformCli = WaveformCli(
        waveforms: waveformDataSource,
        loadSignals: () => loadCliSignals(treeSource),
      );
      final waveformStatus = await waveformCli.status();
      expect(waveformStatus['connected'], isTrue);
      expect(waveformStatus['currentTimePs'], currentTime);
      final waveformMatches = await waveformCli.findSignals('clk|reset');
      final matchedSignals = waveformMatches['signals'] as List<dynamic>;
      expect(matchedSignals, isNotEmpty);
      final waveformValue = await waveformCli.valueAt(clock.id, currentTime);
      expect(waveformValue['signal'], clock.id);
      expect(waveformValue['timePs'], currentTime);

      final connectivity = SchematicTraversalCli.fromNetlist(schematic!);
      SignalOccurrence? resolvedSignal;
      String? reference;
      for (final signal in root.depthFirstSignals()) {
        final address = signal.address?.toDotString();
        if (address == null) {
          continue;
        }
        final resolved = connectivity.resolveSignalHandle(address);
        if (resolved != null) {
          resolvedSignal = resolved;
          reference = address;
          break;
        }
      }
      expect(resolvedSignal, isNotNull);
      expect(reference, isNotNull);

      final query = DesignQueryLanguage(connectivity: connectivity);
      final selected = query.evaluate('select signal $reference');
      expect(selected.signal?.address, reference);
      final assigned =
          query.evaluate('let observed = select signal $reference');
      expect(assigned.alias, 'observed');
      final fanout = query.evaluate('@observed | fanout transparent');
      expect(fanout.connectivity?.direction, 'fanout');
      expect(
        () => query.evaluate('select module FilterBank'),
        throwsFormatException,
      );

      final channel = LocalCrossProbeChannel();
      final shellCrossProbe = LocalCrossProbeService(channel, source: 'shell');
      final observer = LocalCrossProbeService(channel, source: 'observer');
      addTearDown(shellCrossProbe.dispose);
      addTearDown(observer.dispose);
      addTearDown(channel.dispose);
      final shell = RohdShellDtdService(crossProbeService: shellCrossProbe);

      expect(shell.status()['ready'], isFalse);
      expect(shell.execute('status')['ok'], isTrue);
      expect(shell.execute('commands')['commands'], isA<List<Object?>>());
      expect(shell.execute('select signal $reference')['ok'], isFalse);

      shell.configure(schematic, designName: root.name);
      expect(shell.status()['ready'], isTrue);
      expect(shell.status()['designName'], root.name);
      expect(
        shell.execute('let selected = select signal $reference')['ok'],
        isTrue,
      );
      expect(shell.execute('@selected | fanin')['ok'], isTrue);
      final sent = shell.execute('send @selected @selected');
      expect(sent['ok'], isTrue);
      expect(observer.incomingSignals.value, [resolvedSignal!.path()]);
      expect(shell.execute('bad command')['ok'], isFalse);

      shell.clearDesign();
      expect(shell.status()['ready'], isFalse);
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
