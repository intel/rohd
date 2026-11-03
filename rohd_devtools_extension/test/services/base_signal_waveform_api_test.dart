// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// base_signal_waveform_api_test.dart
// Tests the base signal waveform API.
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart' show LogicValue;
import 'package:rohd_devtools_extension/rohd_devtools/services/base_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/rohd_service_transport.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

class _FakeTransport implements RohdServiceTransport {
  final _updates = StreamController<WaveformUpdateEvent>.broadcast();
  final samples = <String, List<Data>>{};
  Map<String, dynamic>? compactSnapshot;
  var _connected = true;

  @override
  bool get isConnected => _connected;

  @override
  int get lastFetchedTime => 0;

  @override
  Stream<WaveformUpdateEvent> get liveUpdates => _updates.stream;

  @override
  String get modeDescription => 'Fake';

  void emit(WaveformUpdateEvent update) => _updates.add(update);

  @override
  Future<void> dispose() async {
    _connected = false;
    await _updates.close();
  }

  @override
  Future<int?> getCurrentTime() async => 10;

  @override
  Future<Map<String, dynamic>?> getModuleNetlist(String definitionName) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getModuleTree() async => null;

  @override
  Future<Map<String, dynamic>?> getSnapshotCompact(int time) async =>
      compactSnapshot;

  @override
  Future<List<WaveformData>> getWaveformDataCompact({
    required List<String> signalAddresses,
    required Map<String, String> addressToSignalId,
    int? startTime,
    int? endTime,
  }) async =>
      [
        for (final address in signalAddresses)
          if (addressToSignalId[address] case final signalId?)
            WaveformData(
              signalId: signalId,
              data: samples[signalId] ?? const [],
            ),
      ];

  @override
  Future<List<WaveformData>> getWaveformDataWithTimepointsCompact({
    required Map<String, int> signalTimepoints,
    required Map<String, String> addressToSignalId,
  }) async =>
      getWaveformDataCompact(
        signalAddresses: signalTimepoints.keys.toList(),
        addressToSignalId: addressToSignalId,
      );
}

HierarchyOccurrence _rootWithSignals(List<SignalOccurrence> signals) =>
    HierarchyOccurrence(name: 'top', signals: signals);

Future<BaseSignalWaveformApi> _apiFor(
  _FakeTransport transport,
  HierarchyOccurrence root,
) async {
  final api = BaseSignalWaveformApi(transport);
  await api.setExternalStructure(
    ModuleStructure(metadata: MetaData.empty(), modules: [root]),
  );
  return api;
}

void main() {
  test('merges incremental stream data into the cached waveform', () async {
    final transport = _FakeTransport()
      ..samples['top/tracked'] = [
        Data(time: 0, value: '0'),
      ];
    addTearDown(transport.dispose);
    final root = _rootWithSignals([
      SignalOccurrence(name: 'tracked', width: 1, direction: 'output'),
    ])
      ..buildAddresses();
    final api = await _apiFor(transport, root);

    final received = api
        .streamWaveformData(signalIds: const ['top/tracked'])
        .take(2)
        .toList();
    await Future<void>.delayed(Duration.zero);
    transport.emit(
      WaveformUpdateEvent(
        incrementalData: [
          WaveformData(
            signalId: 'top/tracked',
            data: [Data(time: 10, value: '1')],
          ),
        ],
        reason: WaveformUpdateReason.breakpoint,
        upToTime: 10,
      ),
    );

    final waveforms = await received;
    expect(waveforms, hasLength(2));
    expect(
      waveforms.first.data.map((point) => (point.time, point.value)),
      [(0, '0')],
    );
    expect(
      waveforms.last.data.map((point) => (point.time, point.value)),
      [(0, '0'), (10, '1')],
    );
    expect(api.cachedSignalIds, contains('top/tracked'));
  });

  test('expands compact snapshots and synthesizes structural field waveforms',
      () async {
    final transport = _FakeTransport();
    addTearDown(transport.dispose);
    final packet = SignalOccurrence(
      name: 'packet',
      width: 4,
      direction: 'input',
      logicType: {
        'fields': [
          {
            'name': 'low',
            'width': 2,
            'bits': [0, 1],
          },
          {
            'name': 'high',
            'width': 2,
            'bits': [2, 3],
          },
        ],
      },
    );
    final root = _rootWithSignals([packet])..buildAddresses();
    final address = packet.address!.toDotString();
    transport
      ..compactSnapshot = {
        'time': 10,
        'v': {address: "4'hd"},
      }
      ..samples['top/packet'] = [
        Data(time: 0, value: "4'hd"),
        Data(time: 10, value: "4'h6"),
      ];
    final api = await _apiFor(transport, root);

    expect(api.resolveSubFieldBits('top/packet#low'), (startBit: 0, width: 2));
    expect(
      api.resolveSubFieldBits('top/packet#high'),
      (startBit: 2, width: 2),
    );
    expect(api.resolveSubFieldBits('top/packet#[9]'), isNull);
    expect(api.resolveSubFieldBits('top/missing#low'), isNull);

    final snapshot = await api.getSnapshot(10);
    expect(snapshot?['top/packet']?['value'], "4'hd");

    final fields = await api.getWaveformData(
      signalIds: const ['top/packet#low', 'top/packet#high'],
    );
    expect(fields, hasLength(2));
    final low = fields.firstWhere(
      (waveform) => waveform.signalId == 'top/packet#low',
    );
    final high = fields.firstWhere(
      (waveform) => waveform.signalId == 'top/packet#high',
    );
    expect(
      low.data
          .map((point) => parseHexToLV(point.value, 2))
          .toList(growable: false),
      [LogicValue.ofInt(1, 2), LogicValue.ofInt(2, 2)],
    );
    expect(
      high.data
          .map((point) => parseHexToLV(point.value, 2))
          .toList(growable: false),
      [LogicValue.ofInt(3, 2), LogicValue.ofInt(1, 2)],
    );
    expect(api.cachedSignalIds,
        containsAll(['top/packet#low', 'top/packet#high']));
  });

  test('coalesces slim module fetches and clears cached structures', () async {
    final transport = _FakeTransport();
    addTearDown(transport.dispose);
    final api = BaseSignalWaveformApi(transport)
      ..schematicModules = {
        'Top': {
          'attributes': {'top': 1},
          'cells': {
            'placeholder': {'type': r'$and'},
          },
        },
      };
    final fetch = Completer<Map<String, dynamic>>();
    var fetchCalls = 0;
    api.fetchModuleSchematic = (definitionName) {
      expect(definitionName, 'Top');
      fetchCalls++;
      return fetch.future;
    };

    final first = api.ensureFullModules('top/signal');
    final second = api.ensureFullModules('top/signal');
    await Future<void>.delayed(Duration.zero);
    expect(fetchCalls, 1);
    fetch.complete({
      'Top': {
        'attributes': {'top': 1},
        'cells': {
          'full': {
            'type': r'$and',
            'connections': <String, dynamic>{},
            'port_directions': <String, dynamic>{},
          },
        },
      },
    });
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(await api.ensureFullModules('top/signal'), isFalse);

    api
      ..schematicModules = {
        'Top': {
          'attributes': {'top': 1},
          'cells': {
            'placeholder': {'type': r'$and'},
          },
        },
        'Child': {
          'cells': {
            'placeholder': {'type': r'$or'},
          },
        },
      }
      ..clearCache();
    final expanded = <String>[];
    api.fetchModuleSchematic = (definitionName) async {
      expanded.add(definitionName);
      return {
        definitionName: {
          'cells': {
            'full': {
              'type': r'$and',
              'connections': <String, dynamic>{},
              'port_directions': <String, dynamic>{},
            },
          },
        },
      };
    };
    await api.expandAllSlimModules();
    expect(expanded, containsAll(['Top', 'Child']));
    final expansionCount = expanded.length;
    await api.expandAllSlimModules();
    expect(expanded, hasLength(expansionCount));

    api.clearCache();
    expect(api.cachedStructure, isNull);
    expect(api.cachedSignalIds, isEmpty);
  });

  test(
    'synthesizes computed gate waveforms and includes them in snapshots',
    () async {
      final transport = _FakeTransport();
      addTearDown(transport.dispose);
      final inputA = SignalOccurrence(
        name: 'a',
        width: 1,
        direction: 'input',
      );
      final inputB = SignalOccurrence(
        name: 'b',
        width: 1,
        direction: 'input',
      );
      final output = SignalOccurrence(
        name: 'out',
        width: 1,
        direction: 'output',
        isComputed: true,
      );
      final root = _rootWithSignals([inputA, inputB, output])..buildAddresses();
      transport
        ..samples['top/a'] = [
          Data(time: 0, value: "1'b0"),
          Data(time: 10, value: "1'b1"),
        ]
        ..samples['top/b'] = [
          Data(time: 0, value: "1'b1"),
          Data(time: 20, value: "1'b0"),
        ]
        ..compactSnapshot = {
          'time': 10,
          'v': {
            inputA.address!.toDotString(): "1'b1",
            inputB.address!.toDotString(): "1'b1",
          },
        };
      final api = await _apiFor(transport, root);
      api.schematicModules = {
        'top': {
          'attributes': {'top': 1},
          'ports': {
            'a': {
              'bits': [1],
            },
            'b': {
              'bits': [2],
            },
            'out': {
              'bits': [3],
            },
          },
          'netnames': {
            'a': {
              'bits': [1],
            },
            'b': {
              'bits': [2],
            },
            'out': {
              'bits': [3],
            },
          },
          'cells': {
            'gate': {
              'type': r'$and',
              'connections': {
                'A': [1],
                'B': [2],
                'Y': [3],
              },
              'port_directions': {
                'A': 'input',
                'B': 'input',
                'Y': 'output',
              },
            },
          },
        },
      };

      final waveforms = await api.getWaveformData(
        signalIds: const ['top/out'],
      );

      expect(waveforms, hasLength(1));
      expect(waveforms.single.signalId, 'top/out');
      expect(waveforms.single.isComputed, isTrue);
      expect(waveforms.single.data.map((point) => point.time), [0, 10, 20]);
      expect(
        waveforms.single.data
            .map((point) => parseHexToLV(point.value, 1))
            .toList(),
        [LogicValue.zero, LogicValue.one, LogicValue.zero],
      );

      final snapshot = await api.getSnapshot(10);
      expect(snapshot?['top/out']?['computed'], isTrue);
      expect(
        parseHexToLV(snapshot!['top/out']!['value'] as String, 1),
        LogicValue.one,
      );
    },
  );
}
