// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// loopback_miter_test.dart
// Verifies that signal names, widths, and DFS ordering agree between the
// server-side WaveformDataService and the client-side LoopbackSignalWaveformApi
// when running in-process (loopback mode).
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
// Runs every example registered in [rohdExamples] through the same checks.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/examples/rohd_examples.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/in_process_transport.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/in_process_tree_data_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/loopback_signal_waveform_api.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/regex_utils.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_waveform/rohd_waveform.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Parse `"N'hXX"` or `"N'bXX"` to extract the declared width N.
/// Returns null if the value is not in ROHD width-prefixed format.
int? _parseWidthFromValue(String value) {
  final match = regExpFirstMatch(r"^(\d+)'", value);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  return null;
}

/// Format a Logic's value using the same compact format as
/// WaveformDataService's `_formatLogicValue`: 1-bit → no width prefix,
/// multi-bit valid → "0xHEX".
String _formatLiveValue(Logic logic) {
  final value = logic.value;
  if (logic.width == 1) {
    return value.toString(includeWidth: false);
  } else if (!value.isValid) {
    return value.toString(includeWidth: false);
  } else {
    final hexStr = value.toBigInt().toRadixString(16).toUpperCase();
    return '0x$hexStr';
  }
}

/// Collect all signals from HierarchyOccurrence roots using the canonical
/// [HierarchyOccurrence.depthFirstSignals] traversal from rohd_hierarchy.
List<SignalOccurrence> _collectSignalsDfs(List<HierarchyOccurrence> roots) {
  final result = <SignalOccurrence>[];
  for (final root in roots) {
    root.buildAddresses();
    result.addAll(root.depthFirstSignals());
  }
  return result;
}

// ---------------------------------------------------------------------------
// Per-example miter test group
// ---------------------------------------------------------------------------

/// Defines the full miter-test suite for a single [RohdExample].
///
/// Each call creates an independent `group()` with its own `setUpAll` that
/// launches the example, wires up the in-process loopback stack, and runs
/// four checks:
///
/// 1. WaveformDataService is initialized with signals
/// 2. Hierarchy signals all have width > 0
/// 3. Server snapshot value widths match hierarchy signal widths
/// 4. Loopback (client) snapshot value widths match hierarchy widths
void _miterGroupForExample(RohdExample example) {
  group('Loopback miter — ${example.name}', () {
    late LoopbackSignalWaveformApi loopbackApi;
    late List<HierarchyOccurrence> hierarchyRoots;
    late int snapshotTime;

    setUpAll(() async {
      // ── 1. Launch the example (builds module, runs sim) ─────────────
      final keepAlive = await example.launcher();
      // We don't need to keep it alive past the test — complete it now.
      keepAlive.complete();

      snapshotTime = WaveformDataService.instance.currentTime;

      // ── 2. Load hierarchy via InProcessTreeDataSource ───────────────
      final treeSource = InProcessTreeDataSource(name: 'miter-test');
      final treeModel = await treeSource.evalModuleTree();
      expect(treeModel, isNotNull, reason: 'Hierarchy should load');

      final rawJson = jsonDecode(
        NetlistService.current?.slimJson ??
            ModuleServices.instance.hierarchyJson,
      ) as Map<String, dynamic>;
      final designData = DesignDataAdapter.parseJson(rawJson);

      hierarchyRoots = [designData.hierarchy.root];

      // ── 3. Wire up loopback waveform API ────────────────────────────
      final waveSource = InProcessTransport(name: 'miter-test');
      loopbackApi = LoopbackSignalWaveformApi(waveSource);

      // Enable client-side NetlistEvaluator so connection nets (e.g.
      // FilterBank/enable) are computed from tracked signal values.
      // Use *full* synthesized modules (with connections) rather than the
      // slim version from getSchematicJson() which lacks connectivity.
      final netSvc = NetlistService.current;
      if (netSvc != null) {
        loopbackApi.schematicModules = netSvc.synthesizedModules;
      }

      final structure = ModuleStructure(
        metadata: MetaData.empty(),
        modules: hierarchyRoots,
      );
      await loopbackApi.setExternalStructure(structure);
    });

    test('WaveformDataService is initialized with signals', () {
      expect(WaveformDataService.instance.isInitialized, isTrue);
      expect(WaveformDataService.instance.signalCount, greaterThan(0));
    });

    test('hierarchy signals all have width > 0', () {
      final signals = _collectSignalsDfs(hierarchyRoots);
      expect(signals, isNotEmpty, reason: 'Hierarchy should have signals');

      for (final signal in signals) {
        expect(
          signal.width,
          greaterThan(0),
          reason: '${signal.path()} should have width > 0',
        );
      }
    });

    test('server snapshot value widths match hierarchy signal widths', () {
      final snapshotJson = WaveformDataService.instance.getSnapshotCompactJSON(
        snapshotTime,
      );
      final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
      final values = snapshot['v'] as Map<String, dynamic>;
      final signals = _collectSignalsDfs(hierarchyRoots);

      // Build address → signal map (addresses assigned by _collectSignalsDfs).
      final addressToSignal = <String, SignalOccurrence>{};
      for (final sig in signals) {
        if (sig.address != null) {
          addressToSignal[sig.address!.toDotString()] = sig;
        }
      }

      final mismatches = <String>[];

      for (final entry in values.entries) {
        final addrStr = entry.key;
        final value = entry.value as String;
        final valueWidth = _parseWidthFromValue(value);

        if (valueWidth == null) {
          continue;
        }

        final signal = addressToSignal[addrStr];
        if (signal != null) {
          if (signal.width != valueWidth) {
            mismatches.add(
              'addr=$addrStr ${signal.path()}: '
              'hierarchy.width=${signal.width}, '
              'value.width=$valueWidth (value="$value")',
            );
          }
        } else {
          mismatches.add('addr=$addrStr no matching hierarchy signal');
        }
      }

      if (mismatches.isNotEmpty) {
        // Print all mismatches to make a failing miter test diagnosable.
        // ignore: avoid_print
        print('\n=== WIDTH MISMATCHES (${example.name}) ===');
        for (final m in mismatches) {
          // Print each mismatch on its own line for readable test output.
          // ignore: avoid_print
          print('  $m');
        }
        // Separate these diagnostics from the test failure message.
        // ignore: avoid_print
        print('');
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'All server snapshot value widths should match '
            'hierarchy signal widths',
      );
    });

    test('loopback getSnapshot value widths match hierarchy widths', () async {
      final snapshot = await loopbackApi.getSnapshot(snapshotTime);
      expect(snapshot, isNotNull, reason: 'Loopback snapshot should succeed');

      final signals = _collectSignalsDfs(hierarchyRoots);
      final signalsByPath = {for (final s in signals) s.path(): s};

      final mismatches = <String>[];

      for (final entry in snapshot!.entries) {
        final signalId = entry.key;
        final meta = entry.value;
        final value = meta['value'] as String?;
        final clientWidth = meta['width'] as int?;

        final hierSignal = signalsByPath[signalId];
        if (hierSignal != null && clientWidth != null) {
          if (hierSignal.width != clientWidth) {
            mismatches.add(
              '$signalId: hierarchy.width=${hierSignal.width}, '
              'client.width=$clientWidth',
            );
          }
        }

        if (value != null && clientWidth != null) {
          final valueWidth = _parseWidthFromValue(value);
          if (valueWidth != null && valueWidth != clientWidth) {
            mismatches.add(
              '$signalId: client.width=$clientWidth, '
              'value.width=$valueWidth (value="$value")',
            );
          }
        }
      }

      if (mismatches.isNotEmpty) {
        // Print all mismatches to make a failing loopback test diagnosable.
        // ignore: avoid_print
        print('\n=== LOOPBACK SNAPSHOT MISMATCHES (${example.name}) ===');
        for (final m in mismatches) {
          // Print each mismatch on its own line for readable test output.
          // ignore: avoid_print
          print('  $m');
        }
        // Separate these diagnostics from the test failure message.
        // ignore: avoid_print
        print('');
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'All loopback snapshot widths should be consistent',
      );
    });

    test(
      'server snapshot values match live Logic.value for tracked signals',
      () {
        // This test catches the bug where WaveformDataService records different
        // values for connected signals (e.g. parent clk vs child clk) due
        // to missed .changed events — the snapshot would show a stale value
        // while Logic.value has the correct live value.
        final snapshotJson =
            WaveformDataService.instance.getSnapshotCompactJSON(snapshotTime);
        final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
        final values = snapshot['v'] as Map<String, dynamic>;

        final addressToId =
            WaveformDataService.instance.debugGetAddressToIdMap();
        final signalLogicMap =
            WaveformDataService.instance.debugGetSignalLogicMap();

        final mismatches = <String>[];

        for (final entry in values.entries) {
          final addrStr = entry.key;
          final snapshotValue = entry.value as String;

          // Resolve address → signal ID → Logic object
          final signalId = addressToId[addrStr];
          if (signalId == null) {
            continue;
          }

          final logic = signalLogicMap[signalId];
          if (logic == null) {
            continue; // Computed/alias signal without Logic ref
          }

          // Compare snapshot value against live Logic.value
          final liveValue = _formatLiveValue(logic);
          if (snapshotValue != liveValue) {
            mismatches.add(
              '$signalId (addr=$addrStr): '
              'snapshot="$snapshotValue", live="$liveValue"',
            );
          }
        }

        if (mismatches.isNotEmpty) {
          // Print all mismatches to make a failing value test diagnosable.
          // ignore: avoid_print
          print('\n=== VALUE MISMATCHES (${example.name}) ===');
          for (final m in mismatches) {
            // Print each mismatch on its own line for readable test output.
            // ignore: avoid_print
            print('  $m');
          }
          // Separate these diagnostics from the test failure message.
          // ignore: avoid_print
          print('');
        }

        expect(
          mismatches,
          isEmpty,
          reason: 'All server snapshot values should match '
              'live Logic.value for tracked signals',
        );
      },
    );

    test(
      'client snapshot values match live Logic.value for tracked signals',
      () async {
        // End-to-end: client receives snapshot via loopback API and every
        // value for a tracked signal should agree with the live Logic.value.
        final snapshot = await loopbackApi.getSnapshot(snapshotTime);
        expect(snapshot, isNotNull, reason: 'Loopback snapshot should succeed');

        final signalLogicMap =
            WaveformDataService.instance.debugGetSignalLogicMap();

        final mismatches = <String>[];

        for (final entry in snapshot!.entries) {
          final signalId = entry.key;
          final meta = entry.value;
          final clientValue = meta['value'] as String?;

          if (clientValue == null) {
            continue;
          }

          final logic = signalLogicMap[signalId];
          if (logic == null) {
            continue; // Computed/alias signal without Logic ref
          }

          final liveValue = _formatLiveValue(logic);
          if (clientValue != liveValue) {
            mismatches.add(
              '$signalId: client="$clientValue", live="$liveValue"',
            );
          }
        }

        if (mismatches.isNotEmpty) {
          // Print all mismatches to make a failing client test diagnosable.
          // ignore: avoid_print
          print('\n=== CLIENT VALUE MISMATCHES (${example.name}) ===');
          for (final m in mismatches) {
            // Print each mismatch on its own line for readable test output.
            // ignore: avoid_print
            print('  $m');
          }
          // Separate these diagnostics from the test failure message.
          // ignore: avoid_print
          print('');
        }

        expect(
          mismatches,
          isEmpty,
          reason: 'All client snapshot values should match '
              'live Logic.value for tracked signals',
        );
      },
    );

    test(
      'getWaveformData returns non-empty data for tracked signals',
      () async {
        // Regression test: InProcessTransport must parse the compact JSON
        // format from WaveformService (abbreviated keys: i, d, t, v).
        // A previous bug used full-name keys (address, data, time, value)
        // which silently returned 0 waveforms.
        final signals = _collectSignalsDfs(hierarchyRoots);
        // Pick a handful of leaf signals that should have waveform data.
        final testIds = signals
            .where((s) => !s.isComputed)
            .take(5)
            .map((s) => s.path())
            .toList();
        expect(
          testIds,
          isNotEmpty,
          reason: 'Should have at least one tracked leaf signal',
        );

        final waveforms = await loopbackApi.getWaveformData(signalIds: testIds);

        final withData = waveforms.where((w) => w.data.isNotEmpty).toList();
        // Report waveform coverage to aid diagnosis when the assertion fails.
        // ignore: avoid_print
        print(
          '\n[getWaveformData] Requested ${testIds.length} signals, '
          'got ${waveforms.length} waveforms '
          '(${withData.length} with data points)',
        );
        for (final wf in waveforms) {
          // Report per-signal point counts for incomplete waveform data.
          // ignore: avoid_print
          print('  ${wf.signalId}: ${wf.data.length} points');
        }

        expect(
          withData,
          isNotEmpty,
          reason: 'At least one tracked signal should have waveform data',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  rohdExamples.forEach(_miterGroupForExample);
}
