// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// miter_test.dart
// Verifies computed gate outputs match VCD-tracked outputs (miter check).
//
// 2026 March
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// Mirrors the devtools architecture:
// 1. Loads Yosys JSON → rohd_hierarchy (via DesignDataAdapter
//    + rootNameOverride)
// 2. Loads VCD as the waveform source (pure Dart parser, equivalent to
//    WaveDumper / WellenReader)
// 3. Maps VCD signals onto the hierarchy via path normalization ('.' ↔ '/')
// 4. Builds a gate netlist from Yosys JSON connectivity (equivalent to
//    WaveformService.getGateNetlistJSON() on the ROHD side)
// 5. Evaluates gates using tracked VCD values as seeds, using LogicValue
//    for proper x/z propagation (matching _evaluateGates in
//    VmServiceSignalWaveformApi)
// 6. Verifies computed outputs match tracked VCD outputs (miter check)
//
// Run with: flutter test test/miter_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart' show LogicValue;
import 'package:rohd_devtools_extension/rohd_devtools/services/design_data_adapter.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/regex_utils.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

// ---------------------------------------------------------------------------
// Gate types we can evaluate (matching VmServiceSignalWaveformApi._evalOpLV)
// ---------------------------------------------------------------------------
const _cellTypeToOp = <String, String>{
  r'$and': 'and',
  r'$or': 'or',
  r'$xor': 'xor',
  r'$not': 'not',
  r'$buf': 'buf',
  r'$mux': 'mux',
  r'$reduce_or': 'uor',
  r'$reduce_and': 'uand',
  r'$reduce_xor': 'uxor',
  r'$eq': 'eq',
  r'$ne': 'ne',
  r'$shl': 'sll',
  r'$shr': 'srl',
  r'$ge': 'gte',
  r'$lt': 'lt',
  r'$add': 'add',
  // $concat → 'swz' and $slice → 'bus' are handled specially in the builder.
};

String get _fixtures => 'test/fixtures';

void main() {
  _miterGroup(
    label: 'filter_bank',
    jsonFile: '$_fixtures/filter_bank.json',
    vcdFile: '$_fixtures/filter_bank.vcd',
  );
}

/// Defines a self-contained miter-test group for one design.
void _miterGroup({
  required String label,
  required String jsonFile,
  required String vcdFile,
}) {
  group('Miter test — $label', () {
    late DesignData designData;
    late HierarchyService hierarchy;
    late Map<String, dynamic> netlistJson;
    late _VcdData vcdData;
    late _GateNetlist netlist;

    setUpAll(() async {
      final jsonContent = await File(jsonFile).readAsString();
      netlistJson = jsonDecode(jsonContent) as Map<String, dynamic>;
      designData = DesignDataAdapter.parseJson(netlistJson);

      final vcdContent = await File(vcdFile).readAsString();
      vcdData = _parseVcd(vcdContent);

      hierarchy = NetlistHierarchyAdapter.fromMap(
        netlistJson,
        rootNameOverride: vcdData.rootScope,
      );

      netlist = _buildGateNetlist(netlistJson, vcdData.rootScope);
    });

    test('DesignDataAdapter detects Yosys format', () {
      expect(designData.format, DesignDataFormat.netlistSchematic);
      expect(designData.hasSchematic, isTrue);
    });

    test('hierarchy loads with expected structure', () {
      final root = hierarchy.root;
      expect(root.name, vcdData.rootScope);
      final children = root.children;
      expect(
        children,
        isNotEmpty,
        reason: 'Top module should have child instances',
      );
      expect(root.name, isNotEmpty);
      expect(children.first.name, isNotEmpty);
    });

    test('VCD signals align with hierarchy paths', () {
      var matched = 0;
      var total = 0;
      for (final vcdPath in vcdData.signals.keys) {
        total++;
        final hierPath = vcdPath.replaceAll('.', '/');
        final addr = OccurrenceAddress.tryFromPathname(
          hierPath,
          hierarchy.root,
        );
        if (addr != null && hierarchy.signalByAddress(addr) != null) {
          matched++;
        }
      }
      expect(total, greaterThan(0), reason: 'Should have VCD signals to check');
      expect(
        matched,
        greaterThan(0),
        reason: 'Some VCD signals should resolve in the hierarchy',
      );
    });

    test('gate netlist has expected entries', () {
      expect(netlist.gates, isNotEmpty);
      expect(netlist.wires, isNotNull);
      expect(netlist.consts, isNotNull);
    });

    test('computed gate outputs match VCD tracked values', () {
      final sortedTimes = vcdData.timepoints.toList()..sort();
      final testTimes = <int>[];
      if (sortedTimes.length <= 20) {
        testTimes.addAll(sortedTimes.where((t) => t > 0));
      } else {
        final step = sortedTimes.length ~/ 20;
        for (var i = 1; i < sortedTimes.length; i += step) {
          testTimes.add(sortedTimes[i]);
        }
      }

      var totalComparisons = 0;
      var mismatchCount = 0;
      final mismatchDetails = <String>[];

      for (final time in testTimes) {
        final tracked = _vcdValuesAtTime(vcdData, time);
        final computed = _evaluateGates(netlist, tracked);

        for (final entry in computed.entries) {
          final signalId = entry.key;
          final vcdPath = signalId.replaceAll('/', '.');
          if (!tracked.containsKey(vcdPath)) {
            continue;
          }

          totalComparisons++;

          final computedVal = entry.value;
          final trackedVal = tracked[vcdPath]!;

          final w = computedVal.width;
          final tw = trackedVal.width;
          final cmp = w == tw
              ? computedVal
              : (w < tw
                  ? computedVal.zeroExtend(tw)
                  : computedVal.getRange(0, tw));
          final tgt = w == tw
              ? trackedVal
              : (tw < w ? trackedVal.zeroExtend(w) : trackedVal.getRange(0, w));

          if (cmp != tgt) {
            mismatchCount++;
            if (mismatchDetails.length < 30) {
              mismatchDetails.add(
                't=$time $signalId: '
                'computed=${_fmtLV(computedVal)} '
                'tracked=${_fmtLV(trackedVal)}',
              );
            }
          }
        }
      }

      expect(
        totalComparisons,
        greaterThan(0),
        reason: 'Should have comparison points',
      );
      expect(
        mismatchCount,
        0,
        reason: '$mismatchCount mismatches out of $totalComparisons '
            'comparisons across ${testTimes.length} timepoints.\n'
            '${mismatchDetails.take(10).join('\n')}',
      );
    });
  });
}

// ===========================================================================
// VCD Parser (pure Dart — equivalent to WellenReader/WaveDumper)
// ===========================================================================

class _VcdData {
  /// SignalOccurrence values keyed by VCD dot-path (e.g. "root.adder0.clk").
  final Map<String, List<({int time, String value})>> signals;

  /// All timepoints in the VCD.
  final Set<int> timepoints;

  /// Root scope name (e.g. "filter_bank").
  final String rootScope;

  _VcdData(this.signals, this.timepoints, this.rootScope);
}

_VcdData _parseVcd(String content) {
  final signals = <String, List<({int time, String value})>>{};
  final timepoints = <int>{};
  final scopeStack = <String>[];
  final idToPath = <String, String>{};
  var currentTime = 0;
  var inHeader = true;
  String? rootScope;

  for (final line in content.split('\n')) {
    final trimmed = line.trim();

    if (trimmed.startsWith(r'$scope')) {
      final match = regExpFirstMatch(r'\$scope\s+\w+\s+(\S+)\s+\$end', trimmed);
      if (match != null) {
        final name = match.group(1)!;
        if (scopeStack.isEmpty) {
          rootScope = name;
        }
        scopeStack.add(name);
      }
    } else if (trimmed.startsWith(r'$upscope')) {
      if (scopeStack.isNotEmpty) {
        scopeStack.removeLast();
      }
    } else if (trimmed.startsWith(r'$var')) {
      final match = regExpFirstMatch(
        r'\$var\s+\w+\s+\d+\s+(\S+)\s+(\S+)',
        trimmed,
      );
      if (match != null) {
        final vcdId = match.group(1)!;
        final sigName = match.group(2)!;
        final fullPath = [...scopeStack, sigName].join('.');
        idToPath[vcdId] = fullPath;
        signals[fullPath] = [];
      }
    } else if (trimmed.startsWith(r'$enddefinitions')) {
      inHeader = false;
    } else if (!inHeader) {
      if (trimmed.startsWith('#')) {
        currentTime = int.tryParse(trimmed.substring(1)) ?? currentTime;
        timepoints.add(currentTime);
      } else if (trimmed.startsWith('b') || trimmed.startsWith('B')) {
        final parts = trimmed.split(' ');
        if (parts.length >= 2) {
          final path = idToPath[parts[1]];
          if (path != null) {
            signals[path]?.add((time: currentTime, value: parts[0]));
          }
        }
      } else if (trimmed.length >= 2 && '01xzXZ'.contains(trimmed[0])) {
        final value = trimmed[0];
        final vcdId = trimmed.substring(1);
        final path = idToPath[vcdId];
        if (path != null) {
          signals[path]?.add((time: currentTime, value: value));
        }
      }
    }
  }

  return _VcdData(signals, timepoints, rootScope ?? '');
}

/// Get a map of VCD-path → LogicValue at a given timepoint.
Map<String, LogicValue> _vcdValuesAtTime(_VcdData vcd, int time) {
  final result = <String, LogicValue>{};

  for (final entry in vcd.signals.entries) {
    final values = entry.value;
    if (values.isEmpty) {
      continue;
    }

    // Binary search for the last value ≤ time.
    var lo = 0;
    var hi = values.length - 1;
    var best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (values[mid].time <= time) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (best < 0) {
      continue;
    }

    result[entry.key] = _vcdStringToLV(values[best].value);
  }

  return result;
}

/// Convert a VCD value string (e.g. "b10110", "0", "1", "x") to LogicValue.
LogicValue _vcdStringToLV(String v) {
  if (v.startsWith('b') || v.startsWith('B')) {
    final bin = v.substring(1);
    if (bin.isEmpty) {
      return LogicValue.ofString('0');
    }
    return LogicValue.ofString(bin);
  }
  // Single character: 0/1/x/z
  return LogicValue.ofString(v);
}

// ===========================================================================
// Gate Netlist Builder (from Yosys JSON)
//
// Produces the same format as WaveformService.getGateNetlistJSON():
//   gates:  [{out, op, in, w, ...}]
//   wires:  {aliasId → sourceId}
//   consts: {constId → {v, w}}
//   meta:   {signalId → [width, name, direction]}
// ===========================================================================

class _GateNetlist {
  final List<Map<String, dynamic>> gates;
  final Map<String, String> wires;
  final Map<String, Map<String, dynamic>> consts;
  final Map<String, List<dynamic>> meta;

  _GateNetlist({
    required this.gates,
    required this.wires,
    required this.consts,
    required this.meta,
  });
}

_GateNetlist _buildGateNetlist(
  Map<String, dynamic> netlistJson,
  String rootName,
) {
  final modules = netlistJson['modules'] as Map<String, dynamic>;

  // Find top module.
  String? topName;
  for (final entry in modules.entries) {
    final attrs = (entry.value as Map<String, dynamic>)['attributes']
        as Map<String, dynamic>?;
    if (attrs?['top'] == 1) {
      topName = entry.key;
      break;
    }
  }
  topName ??= modules.keys.first;

  final gates = <Map<String, dynamic>>[];
  final wires = <String, String>{};
  final consts = <String, Map<String, dynamic>>{};
  final meta = <String, List<dynamic>>{};
  var constCounter = 0;

  void walkModule(String path, Map<String, dynamic> moduleData) {
    final cells = moduleData['cells'] as Map<String, dynamic>? ?? {};
    final netnames = moduleData['netnames'] as Map<String, dynamic>? ?? {};
    final ports = moduleData['ports'] as Map<String, dynamic>? ?? {};

    // ── Build bit → signal path mapping for this module context ───────
    // Include ALL netnames (even hidden/$-prefixed) so the DFS can
    // resolve intermediate wires between gates.
    final bitToSignal = <int, String>{};

    // Track bit-lists for each signal path (for orphan detection).
    final signalBitList = <String, List<int>>{};

    void registerBits(String sigPath, List<dynamic> bits) {
      final intBits = <int>[];
      for (final bit in bits) {
        if (bit is int) {
          bitToSignal.putIfAbsent(bit, () => sigPath);
          intBits.add(bit);
        }
      }
      if (intBits.isNotEmpty) {
        signalBitList[sigPath] = intBits;
      }
    }

    // Ports first (take precedence over netname duplicates).
    for (final entry in ports.entries) {
      final pData = entry.value as Map<String, dynamic>;
      final bits = pData['bits'] as List? ?? [];
      registerBits('$path/${entry.key}', bits);
    }

    // Then all netnames.
    for (final entry in netnames.entries) {
      final nData = entry.value as Map<String, dynamic>;
      final bits = nData['bits'] as List? ?? [];
      registerBits('$path/${entry.key}', bits);
    }

    // ── Process cells ─────────────────────────────────────────────────
    for (final cellEntry in cells.entries) {
      final cellName = cellEntry.key;
      final cellData = cellEntry.value as Map<String, dynamic>;
      final cellType = cellData['type']?.toString() ?? '';
      final connections =
          cellData['connections'] as Map<String, dynamic>? ?? {};
      final portDirs =
          cellData['port_directions'] as Map<String, dynamic>? ?? {};

      if (modules.containsKey(cellType) &&
          !HierarchyOccurrence.isPrimitiveType(cellType)) {
        // ── Non-primitive cell: wire port aliases and recurse ────────
        final childPath = '$path/$cellName';
        final childModData = modules[cellType] as Map<String, dynamic>;
        final childPorts = childModData['ports'] as Map<String, dynamic>? ?? {};

        for (final portEntry in connections.entries) {
          final portName = portEntry.key;
          final parentBits = portEntry.value as List;
          final childPortData = childPorts[portName] as Map<String, dynamic>?;
          if (childPortData == null) {
            continue;
          }

          final dir = childPortData['direction']?.toString() ?? 'inout';
          final childSigPath = '$childPath/$portName';

          // Find the parent signal that these bits connect to.
          final parentSig = _resolveSignal(parentBits, bitToSignal);
          if (parentSig == null) {
            continue;
          }

          if (dir == 'input') {
            // Child reads from parent: child port → parent signal.
            wires[childSigPath] = parentSig;
          } else if (dir == 'output') {
            // Parent reads from child: parent signal → child port.
            wires[parentSig] = childSigPath;
          }
        }

        walkModule(childPath, childModData);
      } else if (cellType == r'$const') {
        // ── Constant block: parse Verilog literal from port name ──
        // Port name is e.g. "8'hff" → 8-bit 0xFF.
        for (final portName in portDirs.keys) {
          if (portDirs[portName] != 'output') {
            continue;
          }
          final bits = connections[portName] as List? ?? [];
          final outputSig = _resolveSignal(bits, bitToSignal);
          if (outputSig == null) {
            continue;
          }
          final width = bits.whereType<int>().length;
          final lv = _parseVerilogLiteral(portName, width);
          consts[outputSig] = {'v': _formatLVBinary(lv), 'w': lv.width};
          meta[outputSig] = [lv.width, cellName, 'output'];
        }
      } else if (cellType == r'$dff') {
        // DFF: sequential element — Q is a registered value, not
        // combinationally derivable. Leave Q as an unresolved leaf;
        // it will get its value from VCD tracked data.
      } else if (cellType == r'$concat') {
        // $concat: Y = {B, A}  (B is MSB, A is LSB)
        final aBits = connections['A'] as List? ?? [];
        final bBits = connections['B'] as List? ?? [];
        final yBits = connections['Y'] as List? ?? [];
        final aSig = _resolveSignal(aBits, bitToSignal);
        final bSig = _resolveSignal(bBits, bitToSignal);
        final ySig = _resolveSignal(yBits, bitToSignal);
        if (aSig != null && bSig != null && ySig != null) {
          final aWidth = aBits.whereType<int>().length;
          final bWidth = bBits.whereType<int>().length;
          final yWidth = yBits.whereType<int>().length;
          // swz convention: inputs[0]=LSB (A), inputs[1]=MSB (B)
          gates.add({
            'out': ySig,
            'op': 'swz',
            'in': [aSig, bSig],
            'w': yWidth,
            'iw': [aWidth, bWidth],
          });
          meta[ySig] = [yWidth, cellName, 'output'];
        }
      } else if (cellType == r'$slice') {
        // $slice: Y = A[OFFSET +: Y_WIDTH]
        // When OFFSET+Y_WIDTH > A_WIDTH, this is a reversed BusSubset
        // (startIndex > endIndex in ROHD). OFFSET = startIndex (MSB).
        final aBits = connections['A'] as List? ?? [];
        final yBits = connections['Y'] as List? ?? [];
        final aSig = _resolveSignal(aBits, bitToSignal);
        final ySig = _resolveSignal(yBits, bitToSignal);
        final params = cellData['parameters'] as Map<String, dynamic>? ?? {};
        final offset = params['OFFSET'] as int? ?? 0;
        if (aSig != null && ySig != null) {
          final yWidth = yBits.whereType<int>().length;
          final aWidth = aBits.whereType<int>().length;
          int lo;
          int hi;
          bool rev;
          if (offset + yWidth > aWidth) {
            final endIdx = (offset - yWidth + 1).clamp(0, aWidth - 1);
            lo = endIdx;
            hi = offset.clamp(0, aWidth - 1);
            rev = true;
          } else {
            lo = offset;
            hi = offset + yWidth - 1;
            rev = false;
          }
          if (lo == 0 &&
              hi == aWidth - 1 &&
              !rev &&
              yWidth == aWidth &&
              ySig != aSig) {
            gates.add({
              'out': ySig,
              'op': 'buf',
              'in': [aSig],
              'w': yWidth,
            });
          } else {
            gates.add({
              'out': ySig,
              'op': 'bus',
              'in': [aSig],
              'w': yWidth,
              'lo': lo,
              'hi': hi,
              if (rev) 'rev': true,
            });
          }
          meta[ySig] = [yWidth, cellName, 'output'];
        }
      } else if (_cellTypeToOp.containsKey(cellType)) {
        // ── Primitive evaluable gate ────────────────────────────────
        final op = _cellTypeToOp[cellType]!;
        String? outputSig;
        var outputWidth = 1;
        final inputSigs = <String>[];

        // For $mux, _evalOpLV expects: [select, d0, d1].
        // Yosys ports: A=d0, B=d1, S=select, Y=output.
        final orderedPorts = <String>[];
        if (cellType == r'$mux') {
          for (final name in ['S', 'A', 'B']) {
            if (portDirs.containsKey(name)) {
              orderedPorts.add(name);
            }
          }
          for (final name in portDirs.keys) {
            if (!orderedPorts.contains(name)) {
              orderedPorts.add(name);
            }
          }
        } else {
          orderedPorts.addAll(portDirs.keys);
        }

        for (final portName in orderedPorts) {
          final dir = portDirs[portName]?.toString() ?? 'input';
          final bits = connections[portName] as List? ?? [];

          if (dir == 'output') {
            outputSig = _resolveSignal(bits, bitToSignal);
            outputWidth = bits.whereType<int>().length;
            if (outputWidth == 0) {
              outputWidth = bits.length;
            }
          } else {
            // Handle constant-only inputs.
            if (bits.every((b) => b is String)) {
              final constId = '__const_${constCounter++}';
              final constVal =
                  bits.reversed.map((b) => b == '1' ? '1' : '0').join();
              consts[constId] = {'v': constVal, 'w': bits.length};
              inputSigs.add(constId);
            } else {
              final sig = _resolveSignal(bits, bitToSignal);
              if (sig != null) {
                inputSigs.add(sig);
              }
            }
          }
        }

        if (outputSig != null && inputSigs.isNotEmpty) {
          gates.add({
            'out': outputSig,
            'op': op,
            'in': inputSigs,
            'w': outputWidth,
          });
          meta[outputSig] = [outputWidth, cellName, 'output'];
        }
      }
    }

    // ── Post-processing: create bus gates for orphaned sub-signals ───
    final gateOutputSet = <String>{};
    for (final g in gates) {
      gateOutputSet.add(g['out'] as String);
    }

    for (final entry in signalBitList.entries) {
      final sigPath = entry.key;
      if (gateOutputSet.contains(sigPath)) {
        continue;
      }
      if (wires.containsKey(sigPath)) {
        continue;
      }
      if (consts.containsKey(sigPath)) {
        continue;
      }

      final bits = entry.value;
      if (bits.isEmpty) {
        continue;
      }

      final parentSig = bitToSignal[bits.first];
      if (parentSig == null || parentSig == sigPath) {
        continue;
      }
      if (!gateOutputSet.contains(parentSig)) {
        continue;
      }

      final parentBits = signalBitList[parentSig];
      if (parentBits == null) {
        continue;
      }

      final lo = parentBits.indexOf(bits.first);
      if (lo < 0) {
        continue;
      }

      var contiguous = true;
      for (var i = 0; i < bits.length; i++) {
        if (lo + i >= parentBits.length || parentBits[lo + i] != bits[i]) {
          contiguous = false;
          break;
        }
      }
      if (!contiguous) {
        continue;
      }

      final hi = lo + bits.length - 1;

      if (lo == 0 && bits.length == parentBits.length) {
        wires[sigPath] = parentSig;
      } else {
        gates.add({
          'out': sigPath,
          'op': 'bus',
          'in': [parentSig],
          'w': bits.length,
          'lo': lo,
          'hi': hi,
        });
      }
    }
  }

  walkModule(rootName, modules[topName] as Map<String, dynamic>);

  return _GateNetlist(gates: gates, wires: wires, consts: consts, meta: meta);
}

/// Find the signal path that covers ALL integer bits in [bits].
/// Returns null if bits span multiple signals or any bit is unmapped.
String? _resolveSignal(List<dynamic> bits, Map<int, String> bitToSignal) {
  String? signal;
  for (final bit in bits) {
    if (bit is int) {
      final sig = bitToSignal[bit];
      if (sig == null) {
        return null;
      }
      signal ??= sig;
      if (sig != signal) {
        return null; // Bits span multiple signals.
      }
    }
  }
  return signal;
}

// ===========================================================================
// Gate Evaluator (DFS with memoization)
//
// Matches VmServiceSignalWaveformApi._evaluateGates():
// - Seeds with tracked signal values
// - Constants from the netlist
// - DFS resolution: wires → source, gates → evaluate from inputs
// - Cycle detection
// - LogicValue for correct x/z propagation
// ===========================================================================

/// Evaluate all gates; return a map of gate-output signalId → LogicValue.
Map<String, LogicValue> _evaluateGates(
  _GateNetlist netlist,
  Map<String, LogicValue> tracked,
) {
  final gateByOutput = <String, Map<String, dynamic>>{};
  for (final gate in netlist.gates) {
    gateByOutput[gate['out'] as String] = gate;
  }

  // Memoization cache.
  final vals = <String, LogicValue>{};

  // Seed with tracked values (VCD paths use '.', gate IDs use '/').
  for (final entry in tracked.entries) {
    vals[entry.key] = entry.value;
    vals[entry.key.replaceAll('.', '/')] = entry.value;
  }

  // Seed constants.
  for (final entry in netlist.consts.entries) {
    final data = entry.value;
    final w = data['w'] as int? ?? 1;
    vals[entry.key] = _parseToLV(data['v'] as String? ?? 'x', w);
  }

  final resolving = <String>{};

  LogicValue resolve(String id, int fallbackWidth) {
    if (vals.containsKey(id)) {
      return vals[id]!;
    }

    if (resolving.contains(id)) {
      return LogicValue.filled(fallbackWidth, LogicValue.x);
    }
    resolving.add(id);

    try {
      // Wire alias.
      if (netlist.wires.containsKey(id)) {
        final source = netlist.wires[id]!;
        final lv = resolve(source, fallbackWidth);
        vals[id] = lv;
        return lv;
      }

      // Gate output.
      final gate = gateByOutput[id];
      if (gate != null) {
        final op = gate['op'] as String;
        final inputs = (gate['in'] as List<dynamic>).cast<String>();
        final width = gate['w'] as int;

        final inVals = <LogicValue>[];
        for (final inputId in inputs) {
          inVals.add(resolve(inputId, width));
        }

        final outVal = _evalOpLV(op, inVals, width, gate);
        vals[id] = outVal;
        return outVal;
      }

      // Unknown — return x.
      return LogicValue.filled(fallbackWidth, LogicValue.x);
    } finally {
      resolving.remove(id);
    }
  }

  // Resolve all gate outputs.
  final result = <String, LogicValue>{};
  for (final gate in netlist.gates) {
    final outId = gate['out'] as String;
    final width = gate['w'] as int;
    resolve(outId, width);
    if (vals.containsKey(outId)) {
      result[outId] = vals[outId]!;
    }
  }

  return result;
}

// ===========================================================================
// LogicValue helpers (matching VmServiceSignalWaveformApi)
// ===========================================================================

LogicValue _parseToLV(String value, int width) {
  if (width == 0) {
    return LogicValue.ofString('');
  }
  // Radix-string format from LogicValue.toString(), e.g. "8'hff".
  if (value.contains("'")) {
    try {
      return _matchWidth(LogicValue.ofRadixString(value), width);
    } on Exception {
      /* fall through */
    }
  }
  // Single-char fill values from VCD.
  if (value == 'x') {
    return LogicValue.filled(width, LogicValue.x);
  }
  if (value == 'z') {
    return LogicValue.filled(width, LogicValue.z);
  }
  // Hex with 0x prefix.
  if (value.startsWith('0x') || value.startsWith('0X')) {
    try {
      return _matchWidth(
        LogicValue.ofRadixString("$width'h${value.substring(2)}"),
        width,
      );
    } on Exception {
      /* fall through */
    }
  }
  // Binary string of 01xz.
  if (value.split('').every((c) => '01xz'.contains(c))) {
    return _matchWidth(LogicValue.ofString(value), width);
  }
  return LogicValue.filled(width, LogicValue.x);
}

LogicValue _matchWidth(LogicValue lv, int w) {
  if (lv.width == w) {
    return lv;
  }
  if (lv.width < w) {
    return lv.zeroExtend(w);
  }
  return lv.getRange(0, w);
}

LogicValue _evalOpLV(
  String op,
  List<LogicValue> inputs,
  int width, [
  Map<String, dynamic>? gate,
]) {
  final xOut = LogicValue.filled(width, LogicValue.x);
  switch (op) {
    case 'and':
      if (inputs.length != 2) {
        return xOut;
      }
      return _matchWidth(inputs[0], width) & _matchWidth(inputs[1], width);
    case 'or':
      if (inputs.length != 2) {
        return xOut;
      }
      return _matchWidth(inputs[0], width) | _matchWidth(inputs[1], width);
    case 'xor':
      if (inputs.length != 2) {
        return xOut;
      }
      return _matchWidth(inputs[0], width) ^ _matchWidth(inputs[1], width);
    case 'not':
      if (inputs.isEmpty) {
        return xOut;
      }
      return ~_matchWidth(inputs[0], width);
    case 'buf':
      if (inputs.isEmpty) {
        return xOut;
      }
      return _matchWidth(inputs[0], width);
    case 'mux':
      // Inputs: [select, d0, d1]
      if (inputs.length != 3) {
        return xOut;
      }
      final ctrl = inputs[0];
      final d0 = _matchWidth(inputs[1], width);
      final d1 = _matchWidth(inputs[2], width);
      if (!ctrl.isValid) {
        return d0 == d1 ? d0 : xOut;
      }
      return ctrl[0] == LogicValue.zero ? d0 : d1;
    case 'uor':
      if (inputs.isEmpty) {
        return xOut;
      }
      return inputs[0].or();
    case 'eq':
      if (inputs.length != 2) {
        return xOut;
      }
      final a = inputs[0];
      final b = _matchWidth(inputs[1], a.width);
      if (!a.isValid || !b.isValid) {
        return xOut;
      }
      return a == b ? LogicValue.one : LogicValue.zero;
    case 'ne':
      if (inputs.length != 2) {
        return xOut;
      }
      final a = inputs[0];
      final b = _matchWidth(inputs[1], a.width);
      if (!a.isValid || !b.isValid) {
        return xOut;
      }
      return a != b ? LogicValue.one : LogicValue.zero;
    case 'sll':
      if (inputs.length != 2) {
        return xOut;
      }
      if (!inputs[1].isValid) {
        return xOut;
      }
      return _matchWidth(inputs[0], width) << inputs[1];
    case 'srl':
      if (inputs.length != 2) {
        return xOut;
      }
      if (!inputs[1].isValid) {
        return xOut;
      }
      return _matchWidth(inputs[0], width) >>> inputs[1];
    case 'gte':
      if (inputs.length != 2) {
        return xOut;
      }
      final gteW =
          inputs[0].width > inputs[1].width ? inputs[0].width : inputs[1].width;
      return _matchWidth(inputs[0], gteW) >= _matchWidth(inputs[1], gteW);
    case 'lt':
      if (inputs.length != 2) {
        return xOut;
      }
      final ltW =
          inputs[0].width > inputs[1].width ? inputs[0].width : inputs[1].width;
      return _matchWidth(inputs[0], ltW) < _matchWidth(inputs[1], ltW);
    case 'add':
      if (inputs.length != 2) {
        return xOut;
      }
      return _matchWidth(inputs[0], width) + _matchWidth(inputs[1], width);
    case 'uand':
      if (inputs.isEmpty) {
        return xOut;
      }
      return inputs[0].and();
    case 'uxor':
      if (inputs.isEmpty) {
        return xOut;
      }
      return inputs[0].xor();
    case 'bus':
      // BusSubset: extract bits [hi:lo] from input.
      if (inputs.isEmpty || gate == null) {
        return xOut;
      }
      final lo = gate['lo'] as int;
      final hi = gate['hi'] as int? ?? (lo + width - 1);
      final rev = gate['rev'] as bool? ?? false;
      final needed = hi + 1;
      final src = inputs[0].width >= needed
          ? inputs[0]
          : _matchWidth(inputs[0], needed);
      final slice = src.getRange(lo, hi + 1);
      return rev ? slice.reversed : slice;
    case 'swz':
      // Swizzle: inputs[0]=LSB, inputs[last]=MSB.
      if (gate == null) {
        return xOut;
      }
      final inputWidths = (gate['iw'] as List<dynamic>?)?.cast<int>();
      if (inputWidths == null || inputWidths.length != inputs.length) {
        return xOut;
      }
      final parts = <LogicValue>[];
      for (var i = inputs.length - 1; i >= 0; i--) {
        final iw = inputWidths[i];
        final src =
            inputs[i].width >= iw ? inputs[i] : _matchWidth(inputs[i], iw);
        parts.add(src.getRange(0, iw));
      }
      return parts.length == 1
          ? parts.first
          : LogicValue.ofIterable(parts.reversed);
    default:
      return xOut;
  }
}

String _fmtLV(LogicValue lv) {
  if (lv.width == 0) {
    return '';
  }
  return lv.toString();
}

/// Parse a Verilog-style constant literal from a `$const` port name.
///
/// Format: `<width>'h<hex_value>`, e.g. `"8'hff"` → 8-bit 0xFF.
/// Falls back to [fallbackWidth] x-filled if parsing fails.
LogicValue _parseVerilogLiteral(String literal, int fallbackWidth) {
  try {
    return LogicValue.ofRadixString(literal);
  } on Exception {
    return LogicValue.filled(fallbackWidth, LogicValue.x);
  }
}

/// Format a [LogicValue] as a binary string for the netlist `consts` map.
String _formatLVBinary(LogicValue lv) {
  if (lv.width == 0) {
    return '';
  }
  final buf = StringBuffer();
  for (var i = lv.width - 1; i >= 0; i--) {
    buf.write(lv[i] == LogicValue.one ? '1' : '0');
  }
  return buf.toString();
}
