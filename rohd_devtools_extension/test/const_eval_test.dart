// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// const_eval_test.dart
// Verifies that $const cell-port paths resolve correctly in both
// the shared NetlistEvaluator and evaluateSignalOnDemand.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/netlist_evaluator.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/regex_utils.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

class _Pair extends LogicStructure {
  _Pair({super.name})
      : super([Logic(name: 'low', width: 4), Logic(name: 'high', width: 4)]);

  @override
  _Pair clone({String? name}) => _Pair(name: name);
}

class _SyntheticPaths extends Module {
  _SyntheticPaths() {
    final pair = addTypedInput('pair', _Pair());
    final a = addInputArray('a', LogicArray([2], 4),
        dimensions: [2], elementWidth: 4);
    final out = addTypedOutput('result', _Pair.new);
    out.elements[0] <= pair.elements[1] ^ a.elements[0];
    out.elements[1] <= Const(1, width: 4);
    final arrayOut =
        addOutputArray('arrayOut', dimensions: [2], elementWidth: 4);
    arrayOut.elements[0] <= ~a.elements[0];
    arrayOut.elements[1] <= ~a.elements[1];
  }
}

void main() {
  late Map<String, dynamic> netlistJson;
  late Map<String, dynamic> modules;

  setUpAll(() async {
    final jsonContent =
        await File('test/fixtures/filter_bank.json').readAsString();
    netlistJson = jsonDecode(jsonContent) as Map<String, dynamic>;
    modules = netlistJson['modules'] as Map<String, dynamic>;
  });

  test('generated synthetic cells and ports round-trip through hierarchy',
      () async {
    final dut = _SyntheticPaths();
    await dut.build();
    final json = NetlistSynthesizer().synthesizeToJson(dut);
    final hierarchy = NetlistHierarchyAdapter.fromJson(json);
    final types = <String>{};
    const syntheticTypes = {
      r'$const',
      r'$slice',
      r'$concat',
      r'$struct_pack',
      r'$struct_unpack',
    };
    for (final child in hierarchy.root.children) {
      if (!syntheticTypes.contains(child.definition)) {
        continue;
      }
      types.add(child.definition!);
      expect(hierarchy.occurrenceByPathname(child.path()), same(child));
      expect(hierarchy.pathnameToAddress(child.path()), child.address);
      for (final port in child.ports) {
        expect(hierarchy.portByPathname(port.path()), same(port));
        expect(hierarchy.pathnameToAddress(port.path()), port.address);
      }
    }
    expect(types, syntheticTypes);
  });

  test('legacy same-name net does not shadow constant occurrence', () {
    final hierarchy = NetlistHierarchyAdapter.fromMap(
      netlistJson,
      rootNameOverride: 'FilterBank',
    );
    final owner = hierarchy.root;
    final driver = owner.children.firstWhere(
      (child) =>
          child.definition == r'$const' &&
          owner.signalIndexByName(child.name) >= 0,
    );
    final net = owner.signals[owner.signalIndexByName(driver.name)];
    expect(hierarchy.pathnameToAddress(net.path()), net.address);
    expect(hierarchy.occurrenceByPathname(driver.path()), same(driver));
    expect(hierarchy.portByPathname(driver.ports.single.path()),
        same(driver.ports.single));
  });

  /// Find all $const cell-port paths in the top module.
  List<String> findConstCellPortPaths(
    Map<String, dynamic> modules,
    String rootName,
  ) {
    final topMod = modules[rootName] as Map<String, dynamic>? ?? {};
    final cells = topMod['cells'] as Map<String, dynamic>? ?? {};
    final paths = <String>[];
    for (final entry in cells.entries) {
      final cellData = entry.value as Map<String, dynamic>;
      if (cellData['type'] == r'$const') {
        final pDirs =
            cellData['port_directions'] as Map<String, dynamic>? ?? {};
        for (final p in pDirs.keys) {
          if (pDirs[p] == 'output') {
            paths.add('$rootName/${entry.key}/$p');
          }
        }
      }
    }
    return paths;
  }

  test(r'NetlistEvaluator resolves $const cell-port paths', () {
    final eval = NetlistEvaluator(modules);

    final constCellPaths = findConstCellPortPaths(modules, 'FilterBank');
    expect(
      constCellPaths,
      isNotEmpty,
      reason: 'Should have cell-port const entries',
    );

    for (final path in constCellPaths) {
      final r = eval.evaluate(path, (_) => null);
      expect(
        r,
        isNotNull,
        reason: 'evaluate should resolve cell-port const "$path"',
      );
      expect(
        r!.value,
        matches(regExpPattern(r"^\d+'h")),
        reason: 'Value should be radixString hex, got: ${r.value}',
      );
      expect(
        r.width,
        greaterThan(0),
        reason: 'Width should be >0 for const cell-port path',
      );
    }
  });

  test(r'NetlistEvaluator resolves $const netname paths', () {
    final eval = NetlistEvaluator(modules);

    // Find netname paths driven by $const cells in the top module.
    final topMod = modules['FilterBank'] as Map<String, dynamic>? ?? {};
    final cells = topMod['cells'] as Map<String, dynamic>? ?? {};
    final netnames = topMod['netnames'] as Map<String, dynamic>? ?? {};

    // Build set of bit indices driven by $const cells.
    final constBits = <int>{};
    for (final entry in cells.entries) {
      final cellData = entry.value as Map<String, dynamic>;
      if (cellData['type'] == r'$const') {
        final conns = cellData['connections'] as Map<String, dynamic>? ?? {};
        for (final conn in conns.values) {
          final bits = conn as List? ?? [];
          for (final b in bits) {
            if (b is int) {
              constBits.add(b);
            }
          }
        }
      }
    }

    // Find netnames whose bits are all driven by $const cells.
    final constNetnames = <String>[];
    for (final nnEntry in netnames.entries) {
      final nnData = nnEntry.value as Map<String, dynamic>;
      final bits = nnData['bits'] as List? ?? [];
      if (bits.isNotEmpty && bits.whereType<int>().every(constBits.contains)) {
        constNetnames.add('FilterBank/${nnEntry.key}');
      }
    }

    expect(
      constNetnames,
      isNotEmpty,
      reason: 'Should have netname const entries',
    );

    for (final path in constNetnames.take(5)) {
      final r = eval.evaluate(path, (_) => null);
      expect(
        r,
        isNotNull,
        reason: 'evaluate should resolve const netname "$path"',
      );
    }
  });

  test(r'evaluateSignalOnDemand resolves $const cell-port paths', () {
    // Find a $const cell in the top module.
    String? topKey;
    for (final e in modules.entries) {
      final attrs = (e.value as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>?;
      if (attrs?['top'] == 1) {
        topKey = e.key;
        break;
      }
    }
    topKey ??= modules.keys.first;

    final topMod = modules[topKey] as Map<String, dynamic>;
    final cells = topMod['cells'] as Map<String, dynamic>? ?? {};

    // Find a $const cell.
    String? constCellName;
    String? constPortName;
    for (final entry in cells.entries) {
      final cellData = entry.value as Map<String, dynamic>;
      if (cellData['type'] == r'$const') {
        constCellName = entry.key;
        final pDirs =
            cellData['port_directions'] as Map<String, dynamic>? ?? {};
        for (final p in pDirs.keys) {
          if (pDirs[p] == 'output') {
            constPortName = p;
            break;
          }
        }
        break;
      }
    }

    expect(
      constCellName,
      isNotNull,
      reason: r'Should find a $const cell in the top module',
    );
    expect(
      constPortName,
      isNotNull,
      reason: r'Should find an output port on the $const cell',
    );

    // Build the hierarchy path: "FilterBank/const_cell_name/portName"
    final path = 'FilterBank/$constCellName/$constPortName';

    final result = evaluateSignalOnDemand(
      modules: modules,
      rerootedPath: path,
      snapshotLookup: (_) => null,
    );

    expect(
      result,
      isNotNull,
      reason: 'evaluateSignalOnDemand should resolve '
          r'$const cell-port path: '
          '$path',
    );
    // Value should start with 0x (valid hex), not be all-x.
    expect(
      result!.value,
      matches(regExpPattern(r"^\d+'h")),
      reason: 'Value should be radixString hex, got: ${result.value}',
    );
    expect(result.width, greaterThan(0));
  });

  test(r'evaluateSignalOnDemand resolves $const cell-name paths', () {
    // Find a $const cell in the top module.
    String? topKey;
    for (final e in modules.entries) {
      final attrs = (e.value as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>?;
      if (attrs?['top'] == 1) {
        topKey = e.key;
        break;
      }
    }
    topKey ??= modules.keys.first;

    final topMod = modules[topKey] as Map<String, dynamic>;
    final cells = topMod['cells'] as Map<String, dynamic>? ?? {};

    // Find a $const cell.
    String? constCellName;
    for (final entry in cells.entries) {
      final cellData = entry.value as Map<String, dynamic>;
      if (cellData['type'] == r'$const') {
        constCellName = entry.key;
        break;
      }
    }

    expect(
      constCellName,
      isNotNull,
      reason: r'Should find a $const cell in the top module',
    );

    // Build the 2-segment hierarchy path: "FilterBank/const_cell_name"
    // This is the path the details pane sends when the cell appears
    // as a signal-like entry in the hierarchy tree.
    final path = 'FilterBank/$constCellName';

    final result = evaluateSignalOnDemand(
      modules: modules,
      rerootedPath: path,
      snapshotLookup: (_) => null,
    );

    expect(
      result,
      isNotNull,
      reason: 'evaluateSignalOnDemand should resolve '
          r'$const cell-name path: '
          '$path',
    );
    expect(
      result!.value,
      matches(regExpPattern(r"^\d+'h")),
      reason: 'Value should be radixString hex, got: ${result.value}',
    );
    expect(result.width, greaterThan(0));
  });
}
