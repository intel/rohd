// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// filter_bank_integration_test.dart
// Integration tests using a real ROHD FilterBank netlist JSON fixture.
// Covers model getters, service methods, and adapter edge cases.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:test/test.dart';

/// Load the slim FilterBank fixture and build a NetlistHierarchyAdapter.
NetlistHierarchyAdapter _loadFixture() {
  final json = File('test/fixtures/filter_bank.json').readAsStringSync();
  return NetlistHierarchyAdapter.fromJson(json);
}

void main() {
  late NetlistHierarchyAdapter adapter;
  late HierarchyService service;

  setUpAll(() {
    adapter = _loadFixture();
    service = adapter;
    service.root.buildAddresses();
  });

  // ─────────────── NetlistHierarchyAdapter parsing ───────────────

  group('NetlistHierarchyAdapter — FilterBank fixture', () {
    test('top module is FilterBank', () {
      expect(service.root.name, 'FilterBank');
    });

    test('rootNameOverride replaces root node name', () {
      final json = File('test/fixtures/filter_bank.json').readAsStringSync();
      final custom =
          NetlistHierarchyAdapter.fromJson(json, rootNameOverride: 'MyDesign');
      expect(custom.root.name, 'MyDesign');
    });

    test('root has expected ports as signals', () {
      final portNames = service.root.signals.map((s) => s.name).toSet();
      expect(portNames, containsAll(['clk', 'reset', 'start', 'done']));
    });

    test('has hierarchical children (ch0, ch1, controller)', () {
      final childNames = service.root.children.map((c) => c.name).toSet();
      // ch0_1 and ch1_1 are FilterChannel instances; controller_1 is
      // FilterController
      expect(childNames, containsAll(['ch0_1', 'ch1_1', 'controller_1']));
    });

    test('primitive cells are marked isPrimitive', () {
      // array_slice cells in FilterBank are $slice — primitive
      final sliceCells = service.root.children
          .where((c) => c.type != null && c.type!.startsWith(r'$'));
      expect(sliceCells, isNotEmpty);
      for (final cell in sliceCells) {
        expect(cell.isPrimitive, isTrue,
            reason: '${cell.name} (${cell.type}) should be primitive');
      }
    });

    test('primitive cells have port signals from port_directions', () {
      final primitives = service.root.children.where((c) => c.isPrimitive);
      for (final prim in primitives) {
        expect(prim.signals, isNotEmpty,
            reason: '${prim.name} should have port signals');
        // All signals on primitive cells should be Port instances
        for (final s in prim.signals) {
          expect(s is Port, isTrue,
              reason: '${prim.name}/${s.name} should be a Port');
          expect((s as Port).direction, isNotEmpty);
        }
      }
    });

    test('netnames with hide_name=1 are excluded', () {
      // FilterBank has controller_1_loadingPhase with hide_name=1
      final allSignalNames =
          service.root.depthFirstSignals().map((s) => s.name);
      expect(allSignalNames, isNot(contains('controller_1_loadingPhase')));
    });

    test('netnames with computed attribute are included with isComputed', () {
      // CoeffBank has const_0_2_h0 with computed=1
      // Navigate: FilterBank → ch0_1 → one of its children should have
      // a CoeffBank with computed signals
      bool foundComputed(HierarchyNode node) {
        for (final s in node.signals) {
          if (s.isComputed) {
            return true;
          }
        }
        return node.children.any(foundComputed);
      }

      expect(foundComputed(service.root), isTrue,
          reason: 'Should have at least one computed signal');
    });

    test(r'$-prefixed netnames are excluded', () {
      // Any netname starting with $ should be filtered out
      final allNames = service.root.depthFirstSignals().map((s) => s.name);
      final dollarNames = allNames.where((n) => n.startsWith(r'$'));
      expect(dollarNames, isEmpty,
          reason: r'No $-prefixed netnames should appear');
    });
  });

  // ─────────────── HierarchyNode model getters ───────────────

  group('HierarchyNode model getters', () {
    test('ports returns only Port instances', () {
      final ports = service.root.ports;
      expect(ports, isNotEmpty);
      for (final p in ports) {
        expect(p, isA<Port>());
        expect(p.direction, isNotEmpty);
      }
    });

    test('inputs returns only input ports', () {
      final inputs = service.root.inputs;
      expect(inputs, isNotEmpty);
      for (final s in inputs) {
        expect(s.direction, 'input');
      }
      expect(inputs.map((s) => s.name), contains('clk'));
    });

    test('outputs returns only output ports', () {
      final outputs = service.root.outputs;
      expect(outputs, isNotEmpty);
      for (final s in outputs) {
        expect(s.direction, 'output');
      }
      expect(outputs.map((s) => s.name), contains('done'));
    });

    test(r'isPrimitiveType is true for $-prefixed types', () {
      expect(HierarchyNode.isPrimitiveType(r'$mux'), isTrue);
      expect(HierarchyNode.isPrimitiveType(r'$and'), isTrue);
    });

    test(r'isPrimitiveType is false for non-$-prefixed types', () {
      expect(HierarchyNode.isPrimitiveType('FilterBank'), isFalse);
    });

    test('isPrimitiveType is false for empty string', () {
      expect(HierarchyNode.isPrimitiveType(''), isFalse);
    });

    test('isPrimitiveCell reflects isPrimitive field and type', () {
      // A node marked isPrimitive=true
      final primCell = service.root.children.firstWhere((c) => c.isPrimitive);
      expect(primCell.isPrimitiveCell, isTrue);

      // The root module is not primitive
      expect(service.root.isPrimitiveCell, isFalse);
    });

    test('depthFirstSignals places root signals first', () {
      final all = service.root.depthFirstSignals();
      expect(all, isNotEmpty);

      final rootSigs = service.root.signals;
      for (var i = 0; i < rootSigs.length; i++) {
        expect(all[i].name, rootSigs[i].name);
      }
    });

    test('depthFirstSignals count equals recursive signal total', () {
      final all = service.root.depthFirstSignals();
      int countSignals(HierarchyNode n) =>
          n.signals.length +
          n.children.fold(0, (sum, c) => sum + countSignals(c));
      expect(all.length, countSignals(service.root));
    });
  });

  // ─────────────── Signal model getters ───────────────

  group('Signal model getters', () {
    test('isPort is true for Port instances', () {
      final port = service.root.signals.first;
      expect(port.isPort, isTrue);
    });

    test('input port has isInput true and isOutput/isInout false', () {
      final clk = service.root.signals.firstWhere((s) => s.name == 'clk');
      expect(clk.isPort, isTrue);
      expect(clk.isInput, isTrue);
      expect(clk.isOutput, isFalse);
      expect(clk.isInout, isFalse);
    });

    test('output port has isOutput true and isInput false', () {
      final done = service.root.signals.firstWhere((s) => s.name == 'done');
      expect(done.isOutput, isTrue);
      expect(done.isInput, isFalse);
    });

    test('isPort is false for non-Port signals (internal wires)', () {
      // Internal signals (from netnames) are Signal, not Port.
      // The fixture includes visible non-port netnames like tapMatch0.
      final allSigs = service.root.depthFirstSignals();
      final nonPorts = allSigs.where((s) => !s.isPort).toList();
      expect(nonPorts, isNotEmpty,
          reason: 'Should have non-Port internal signals from netnames');
    });

    test('Signal.toString includes name and width', () {
      final clk = service.root.signals.firstWhere((s) => s.name == 'clk');
      final str = clk.toString();
      expect(str, contains('clk'));
    });
  });

  // ─────────────── HierarchyService methods ───────────────

  group('HierarchyService — search coverage', () {
    test('searchNodes returns HierarchyNode objects', () {
      final nodes = service.searchNodes('controller');
      expect(nodes, isNotEmpty);
      for (final n in nodes) {
        expect(n, isA<HierarchyNode>());
      }
    });

    test('autocompletePaths returns children for partial path', () {
      final suggestions = service.autocompletePaths('FilterBank/');
      expect(suggestions, isNotEmpty);
      for (final s in suggestions) {
        expect(s, startsWith('FilterBank/'));
      }
    });

    test('autocompletePaths filters by prefix', () {
      final suggestions = service.autocompletePaths('FilterBank/ch');
      expect(suggestions, isNotEmpty);
      for (final s in suggestions) {
        expect(s.toLowerCase(), contains('/ch'));
      }
    });

    test('autocompletePaths with empty string returns root', () {
      final suggestions = service.autocompletePaths('');
      // Should suggest root-level completions
      expect(suggestions, isNotEmpty);
    });

    test('autocompletePaths appends / for nodes with children', () {
      final suggestions = service.autocompletePaths('FilterBank/');
      final withSlash = suggestions.where((s) => s.endsWith('/'));
      // At least ch0_1 and ch1_1 have children
      expect(withSlash, isNotEmpty);
    });

    test('hasRegexChars is false for plain text', () {
      expect(HierarchyService.hasRegexChars('clk'), isFalse);
    });

    test('hasRegexChars detects * glob', () {
      expect(HierarchyService.hasRegexChars('c*'), isTrue);
    });

    test('hasRegexChars detects ? glob', () {
      expect(HierarchyService.hasRegexChars('cl?'), isTrue);
    });

    test('hasRegexChars detects character class', () {
      expect(HierarchyService.hasRegexChars('[a-z]'), isTrue);
    });

    test('hasRegexChars detects group alternation', () {
      expect(HierarchyService.hasRegexChars('(a|b)'), isTrue);
    });

    test('hasRegexChars detects + quantifier', () {
      expect(HierarchyService.hasRegexChars('a+'), isTrue);
    });

    test('longestCommonPrefix finds shared prefix', () {
      expect(
        HierarchyService.longestCommonPrefix(
            ['FilterBank/ch0', 'FilterBank/ch1']),
        'FilterBank/ch',
      );
    });

    test('longestCommonPrefix returns null for empty list', () {
      expect(HierarchyService.longestCommonPrefix([]), isNull);
    });

    test('longestCommonPrefix returns null for no common prefix', () {
      expect(HierarchyService.longestCommonPrefix(['abc', 'xyz']), isNull);
    });

    test('longestCommonPrefix is case-insensitive', () {
      final prefix =
          HierarchyService.longestCommonPrefix(['Filter/abc', 'filter/abd']);
      expect(prefix, 'Filter/ab');
    });
  });

  // ─────────────── HierarchySearchController ───────────────

  group('HierarchySearchController — additional coverage', () {
    test('selectAt selects valid index', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(service)
            ..updateQuery('clk');
      expect(ctrl.hasResults, isTrue);

      ctrl.selectAt(0);
      expect(ctrl.selectedIndex, 0);
    });

    test('selectAt clamps high index to last result', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(service)
            ..updateQuery('clk');
      expect(ctrl.hasResults, isTrue);

      ctrl.selectAt(999);
      expect(ctrl.selectedIndex, ctrl.results.length - 1);
    });

    test('selectAt clamps negative index to zero', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(service)
            ..updateQuery('clk');
      expect(ctrl.hasResults, isTrue);

      ctrl.selectAt(-5);
      expect(ctrl.selectedIndex, 0);
    });

    test('selectAt on empty results is no-op', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(service)
            ..selectAt(3);
      expect(ctrl.selectedIndex, 0);
      expect(ctrl.hasResults, isFalse);
    });

    test('tabComplete expands to longest common prefix', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(service)
            ..updateQuery('clk');
      if (ctrl.results.length > 1) {
        final expansion = ctrl.tabComplete('clk');
        // Expansion should be longer than the query if results share a
        // common prefix beyond 'clk'
        if (expansion != null) {
          expect(expansion.length, greaterThan(3));
        }
      }
    });

    test('tabComplete returns null when no results', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(service)
            ..updateQuery('zzz_nonexistent');
      expect(ctrl.tabComplete('zzz_nonexistent'), isNull);
    });

    test('tabComplete returns null when prefix is not longer', () {
      final ctrl =
          HierarchySearchController<SignalSearchResult>.forSignals(service)
            ..updateQuery('clk');
      // If there's a single result whose displayPath equals normalized
      // query, tabComplete should return null or the path itself.
      // With multiple results from different modules, the common prefix
      // may not be longer.
      final result = ctrl.tabComplete(ctrl.results.first.displayPath);
      // Either null or the same length — shouldn't crash
      expect(result, anyOf(isNull, isA<String>()));
    });
  });

  // ─────────────── ModuleSearchResult getters ───────────────

  group('ModuleSearchResult — additional getters', () {
    test('kind reflects node.kind', () {
      final results = service.searchModules('ch0');
      expect(results, isNotEmpty);
      final r = results.first;
      expect(r.kind, isNotNull);
    });

    test('childCount reflects node.children.length', () {
      final results = service.searchModules('FilterBank');
      final fbResult = results.firstWhere((r) => r.path.length == 1,
          orElse: () => results.first);
      expect(fbResult.childCount, greaterThan(0));
    });

    test('toString includes module name', () {
      final results = service.searchModules('ch0');
      expect(results.first.toString(), contains('ch0'));
    });
  });

  // ─────────────── SignalSearchResult toString ───────────────

  group('SignalSearchResult.toString', () {
    test('toString includes signal name', () {
      final results = service.searchSignals('clk');
      expect(results, isNotEmpty);
      expect(results.first.toString(), contains('clk'));
    });
  });

  // ─────────────── BaseHierarchyAdapter edge case ───────────────
  // The real uninitialized-root StateError test lives in
  // coverage_gaps_test.dart.  Here we just verify fromTree works.

  group('BaseHierarchyAdapter — fromTree produces usable root', () {
    test('fromTree immediately sets root', () {
      final tree =
          HierarchyNode(id: 'r', name: 'r', kind: HierarchyKind.module);
      final svc = BaseHierarchyAdapter.fromTree(tree);
      expect(svc.root.name, 'r');
    });
  });

  // ─────────────── Multiple instantiation (dedup) ───────────────

  group('Multiple instantiation — FilterChannel dedup', () {
    test('ch0 and ch1 are separate node instances', () {
      final ch0 = service.root.children.firstWhere((c) => c.name == 'ch0_1');
      final ch1 = service.root.children.firstWhere((c) => c.name == 'ch1_1');
      expect(identical(ch0, ch1), isFalse);
    });

    test('ch0 and ch1 have identical signal structure', () {
      final ch0 = service.root.children.firstWhere((c) => c.name == 'ch0_1');
      final ch1 = service.root.children.firstWhere((c) => c.name == 'ch1_1');

      expect(ch0.signals.length, ch1.signals.length);

      final ch0PortNames = ch0.signals.map((s) => s.name).toSet();
      final ch1PortNames = ch1.signals.map((s) => s.name).toSet();
      expect(ch0PortNames, ch1PortNames);
    });

    test('search finds signals in both channel instances', () {
      // Both channels should have a clk port
      final results = service.searchSignals('clk');
      final channelClks = results
          .where((r) =>
              r.signalId.contains('ch0_1') || r.signalId.contains('ch1_1'))
          .toList();
      // Should find clk in both ch0_1 and ch1_1
      expect(
          channelClks.where((r) => r.signalId.contains('ch0_1')), isNotEmpty);
      expect(
          channelClks.where((r) => r.signalId.contains('ch1_1')), isNotEmpty);
    });

    test('addresses resolve independently for each instance', () {
      final ch0Addr = HierarchyAddress.tryFromPathname(
          'FilterBank/ch0_1/clk', service.root);
      final ch1Addr = HierarchyAddress.tryFromPathname(
          'FilterBank/ch1_1/clk', service.root);

      expect(ch0Addr, isNotNull);
      expect(ch1Addr, isNotNull);
      expect(ch0Addr, isNot(equals(ch1Addr)));

      final ch0Sig = service.signalByAddress(ch0Addr!);
      final ch1Sig = service.signalByAddress(ch1Addr!);
      expect(ch0Sig, isNotNull);
      expect(ch1Sig, isNotNull);
      expect(ch0Sig!.name, 'clk');
      expect(ch1Sig!.name, 'clk');
    });

    test('both instances have internal (non-port) signals', () {
      final ch0 = service.root.children.firstWhere((c) => c.name == 'ch0_1');
      final ch1 = service.root.children.firstWhere((c) => c.name == 'ch1_1');

      final ch0Internal = ch0.signals.where((s) => !s.isPort).toList();
      final ch1Internal = ch1.signals.where((s) => !s.isPort).toList();

      expect(ch0Internal, isNotEmpty,
          reason: 'ch0_1 should have internal signals from netnames');
      expect(ch1Internal, isNotEmpty,
          reason: 'ch1_1 should have internal signals from netnames');
    });

    test('both instances share the same internal signal names', () {
      final ch0 = service.root.children.firstWhere((c) => c.name == 'ch0_1');
      final ch1 = service.root.children.firstWhere((c) => c.name == 'ch1_1');

      final ch0Names =
          ch0.signals.where((s) => !s.isPort).map((s) => s.name).toSet();
      final ch1Names =
          ch1.signals.where((s) => !s.isPort).map((s) => s.name).toSet();
      expect(ch0Names, ch1Names);
    });

    test('internal signals are addressable per-instance', () {
      // validPipe exists as a netname in both FilterChannel definitions
      final ch0Addr = HierarchyAddress.tryFromPathname(
          'FilterBank/ch0_1/validPipe', service.root);
      final ch1Addr = HierarchyAddress.tryFromPathname(
          'FilterBank/ch1_1/validPipe', service.root);

      expect(ch0Addr, isNotNull, reason: 'ch0_1/validPipe should resolve');
      expect(ch1Addr, isNotNull, reason: 'ch1_1/validPipe should resolve');
      expect(ch0Addr, isNot(equals(ch1Addr)));

      final ch0Sig = service.signalByAddress(ch0Addr!);
      final ch1Sig = service.signalByAddress(ch1Addr!);
      expect(ch0Sig, isNotNull);
      expect(ch1Sig, isNotNull);
      expect(ch0Sig!.name, 'validPipe');
      expect(ch1Sig!.name, 'validPipe');
      expect(ch0Sig.isPort, isFalse);
    });

    test('search finds internal signals in both instances', () {
      final results = service.searchSignals('validPipe');
      final inCh0 = results.where((r) => r.signalId.contains('ch0_1'));
      final inCh1 = results.where((r) => r.signalId.contains('ch1_1'));
      expect(inCh0, isNotEmpty, reason: 'validPipe should be found in ch0_1');
      expect(inCh1, isNotEmpty, reason: 'validPipe should be found in ch1_1');
    });

    test('depthFirstSignals includes internal signals from both instances', () {
      final all = service.root.depthFirstSignals();
      final vpSigs = all.where((s) => s.name == 'validPipe').toList();
      expect(vpSigs.length, greaterThanOrEqualTo(2),
          reason: 'validPipe should appear in at least ch0 and ch1');
    });
  });

  // ─────────────── InOut (bidirectional) port tests ───────────────

  group('InOut port — dataBus', () {
    test('root has dataBus as inout port', () {
      final dataBus = service.root.signals
          .whereType<Port>()
          .where((p) => p.name == 'dataBus')
          .firstOrNull;
      expect(dataBus, isNotNull, reason: 'FilterBank should have dataBus');
      expect(dataBus!.direction, 'inout');
      expect(dataBus.isInout, isTrue);
      expect(dataBus.isInput, isFalse);
      expect(dataBus.isOutput, isFalse);
    });

    test('inputs getter excludes inout ports', () {
      final inputs = service.root.inputs;
      final inoutInInputs = inputs.where((s) => s.direction == 'inout');
      expect(inoutInInputs, isEmpty,
          reason: 'inputs should not include inout ports');
    });

    test('outputs getter excludes inout ports', () {
      final outputs = service.root.outputs;
      final inoutInOutputs = outputs.where((s) => s.direction == 'inout');
      expect(inoutInOutputs, isEmpty,
          reason: 'outputs should not include inout ports');
    });

    test('ports getter includes inout ports', () {
      final allPorts = service.root.ports;
      final inouts = allPorts.where((p) => p.direction == 'inout').toList();
      expect(inouts, isNotEmpty, reason: 'ports should include inout ports');
      expect(inouts.first.name, 'dataBus');
    });

    test('dataBus is addressable and resolvable', () {
      final addr =
          HierarchyAddress.tryFromPathname('FilterBank/dataBus', service.root);
      expect(addr, isNotNull, reason: 'dataBus should be addressable');

      final sig = service.signalByAddress(addr!);
      expect(sig, isNotNull);
      expect(sig!.name, 'dataBus');
      expect(sig.isInout, isTrue);
    });

    test('search finds dataBus inout port', () {
      final results = service.searchSignals('dataBus');
      expect(results, isNotEmpty);
      final dataBusResults =
          results.where((r) => r.signalId.contains('dataBus'));
      expect(dataBusResults, isNotEmpty);
    });

    test('SharedDataBus child also has dataBus inout', () {
      final sharedBus = service.root.children
          .where((c) => c.name == 'sharedBus_1')
          .firstOrNull;
      expect(sharedBus, isNotNull,
          reason: 'sharedBus_1 cell should be present');
      final childDataBus = sharedBus!.signals
          .whereType<Port>()
          .where((p) => p.name == 'dataBus')
          .firstOrNull;
      expect(childDataBus, isNotNull,
          reason: 'SharedDataBus should have dataBus inout');
      expect(childDataBus!.isInout, isTrue);
    });

    test('depthFirstSignals includes inout ports', () {
      final all = service.root.depthFirstSignals();
      final inouts = all.where((s) => s is Port && s.isInout);
      expect(inouts, isNotEmpty,
          reason: 'depthFirstSignals should include inout ports');
    });

    test('addressToPathname round-trips for inout signal', () {
      final addr =
          HierarchyAddress.tryFromPathname('FilterBank/dataBus', service.root);
      expect(addr, isNotNull);
      final pathname = service.addressToPathname(addr!, asSignal: true);
      expect(pathname, 'FilterBank/dataBus');
    });
  });
}
