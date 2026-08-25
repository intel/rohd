// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// gate_catalog_test.dart
// Verifies that the checked-in gate-catalog netlist asset
// (`test/fixtures/gate_catalog.rohd.json`) is byte-for-byte reproducible from
// `GateCatalog` (see `test/fixtures/gate_catalog_module.dart`), and spot
// checks coverage of every gate API this catalog is meant to exercise.
//
// If this test fails only because of an intentional change to gate lowering
// or the netlist cell mapper, regenerate the asset with:
//   dart run tool/generate_gate_catalog.dart
// and review the diff before committing it.
//
// 2026 August 20
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import 'fixtures/gate_catalog_module.dart';

/// Builds a fresh [GateCatalog] with deterministic, freshly-allocated input
/// signals.
GateCatalog _buildCatalog() => GateCatalog(
      clk: Logic(name: 'clk'),
      en: Logic(name: 'en'),
      reset: Logic(name: 'reset'),
      muxSel: Logic(name: 'muxSel'),
      enableTri: Logic(name: 'enableTri'),
      a4: Logic(name: 'a4', width: 4),
      b4: Logic(name: 'b4', width: 4),
      a8: Logic(name: 'a8', width: 8),
      b8: Logic(name: 'b8', width: 8),
      d4: Logic(name: 'd4', width: 4),
      shamt4: Logic(name: 'shamt4', width: 4),
      idx3: Logic(name: 'idx3', width: 3),
      idx5: Logic(name: 'idx5', width: 5),
      resetValueDyn4: Logic(name: 'resetValueDyn4', width: 4),
      busNet: LogicNet(name: 'busNet', width: 8),
    );

/// Synthesizes [GateCatalog] to combined netlist JSON using the default
/// [NetlistSynthesizerConfiguration] (the same defaults a typical consumer
/// would use).
Future<String> _synthesizeCatalogJson() async {
  final catalog = _buildCatalog();
  await catalog.build();
  final synth = NetlistSynthesizer();
  return synth.synthesizeToJson(catalog);
}

/// Path (relative to the package root, where `dart test` runs) to the
/// checked-in fixture asset.
const _fixturePath = 'test/fixtures/gate_catalog.rohd.json';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('GateCatalog netlist JSON matches checked-in fixture byte-for-byte',
      () async {
    final generated = await _synthesizeCatalogJson();
    final fixtureFile = File(_fixturePath);

    expect(fixtureFile.existsSync(), isTrue,
        reason: 'Missing fixture at $_fixturePath. Generate it with: '
            'dart run tool/generate_gate_catalog.dart');

    final checkedIn = fixtureFile.readAsStringSync();
    expect(
      generated,
      equals(checkedIn),
      reason: 'Generated gate-catalog netlist JSON no longer matches the '
          'checked-in fixture. If this change is intentional, regenerate '
          'the asset with `dart run tool/generate_gate_catalog.dart` and '
          'review/commit the diff.',
    );
  });

  test('GateCatalog netlist JSON is deterministic across repeated synthesis',
      () async {
    final first = await _synthesizeCatalogJson();
    await Simulator.reset();
    final second = await _synthesizeCatalogJson();
    expect(second, equals(first));
  });

  group('gate catalog coverage', () {
    late Map<String, dynamic> json;
    late Map<String, dynamic> moduleDef;
    late Map<String, dynamic> cells;

    setUpAll(() async {
      final text = await _synthesizeCatalogJson();
      json = jsonDecode(text) as Map<String, dynamic>;
      final modules = json['modules'] as Map<String, dynamic>;
      moduleDef = modules['GateCatalog'] as Map<String, dynamic>;
      cells = moduleDef['cells'] as Map<String, dynamic>;
    });

    List<Map<String, dynamic>> cellsOfType(String type) => cells.values
        .cast<Map<String, dynamic>>()
        .where((c) => c['type'] == type)
        .toList();

    test('every standard Yosys arithmetic/logic/compare/shift cell exists', () {
      const expectedTypes = <String>{
        r'$not',
        r'$and',
        r'$or',
        r'$xor',
        r'$reduce_and',
        r'$reduce_or',
        r'$reduce_xor',
        r'$add',
        r'$sub',
        r'$mul',
        r'$div',
        r'$mod',
        r'$pow',
        r'$eq',
        r'$ne',
        r'$lt',
        r'$gt',
        r'$le',
        r'$ge',
        r'$shl',
        r'$shr',
        r'$sshr',
        r'$mux',
        r'$shiftx',
        r'$slice',
        r'$concat',
        r'$tribuf',
        r'$dff',
        r'$dffe',
        r'$sdff',
        r'$sdffe',
        r'$adff',
        r'$adffe',
        r'$aldff',
        r'$aldffe',
      };
      for (final type in expectedTypes) {
        expect(cellsOfType(type), isNotEmpty, reason: 'missing $type cell');
      }
    });

    test('Power/Divide/Modulo cells have full standard A/B/Y parameters', () {
      for (final type in [r'$pow', r'$div', r'$mod']) {
        final matches = cellsOfType(type);
        expect(matches, isNotEmpty, reason: type);
        for (final cell in matches) {
          expect(
            cell['parameters'],
            equals({
              'A_SIGNED': 0,
              'A_WIDTH': 4,
              'B_SIGNED': 0,
              'B_WIDTH': 4,
              'Y_WIDTH': 4,
            }),
            reason: type,
          );
          expect(
            cell['port_directions'],
            equals({'A': 'input', 'B': 'input', 'Y': 'output'}),
            reason: type,
          );
        }
      }
    });

    test(r'IndexGate cells map to $shiftx with full standard parameters', () {
      final matches = cellsOfType(r'$shiftx');
      // One "natural" 3-bit index and one "oversized" 5-bit index.
      expect(matches, hasLength(2));
      final bWidths =
          matches.map((c) => (c['parameters'] as Map)['B_WIDTH']).toSet();
      expect(bWidths, equals({3, 5}));
      for (final cell in matches) {
        final params = cell['parameters'] as Map<String, dynamic>;
        expect(params['A_SIGNED'], 0);
        expect(params['B_SIGNED'], 0);
        expect(params['A_WIDTH'], 8);
        expect(params['Y_WIDTH'], 1);
        expect(
          cell['port_directions'],
          equals({'A': 'input', 'B': 'input', 'Y': 'output'}),
        );
      }
    });

    test('ReplicationOp is retained as an explicit, visible (unmapped) cell',
        () {
      final replicationCells = cellsOfType('ReplicationOp');
      expect(replicationCells, hasLength(2));
      // Confirm it is not force-mapped to any standard Yosys cell type
      // (e.g. `$concat`): its cell `type` field is the raw ROHD
      // `definitionName`, not a `$`-prefixed standard primitive.
      for (final cell in replicationCells) {
        expect(cell['type'], isNot(startsWith(r'$')));
      }
      final outputWidths = replicationCells.map((c) {
        final connections =
            (c['connections'] as Map).values.cast<List<dynamic>>();
        return connections.map((l) => l.length).reduce((a, b) => a > b ? a : b);
      }).toSet();
      expect(outputWidths, equals({12, 20}));
    });

    test(r'constant-control mux() folds away at build time (no extra $mux)',
        () {
      // Two dynamic-control mux instantiations (Mux class + mux() function)
      // produce two explicit `$mux` cells; the two dynamic-synchronous-reset
      // flip-flops (see below) each lower to an additional `$mux` (selecting
      // the reset value) for four `$mux` cells total. The two
      // constant-control mux() calls fold away entirely at build time and
      // contribute no additional `$mux` cells.
      expect(cellsOfType(r'$mux'), hasLength(4));

      final ports = moduleDef['ports'] as Map<String, dynamic>;
      final const1Bits =
          (ports['mux_fn_const1_out'] as Map<String, dynamic>)['bits'] as List;
      final const0Bits =
          (ports['mux_fn_const0_out'] as Map<String, dynamic>)['bits'] as List;
      final aBits = (ports['a4'] as Map<String, dynamic>)['bits'] as List;
      final bBits = (ports['b4'] as Map<String, dynamic>)['bits'] as List;

      // Find the (non-$mux) driver of a port's bits: since `mux()` folded
      // away, the only thing between the port and its source signal is a
      // plain `$buf` passthrough (emitted whenever an output port aliases an
      // input directly), never a `$mux`.
      //
      // Note: `List`'s `==` is identity-based, not element-wise, so bit
      // lists must be compared with an explicit element-wise check.
      bool sameBits(List<dynamic> a, List<dynamic> b) {
        if (a.length != b.length) {
          return false;
        }
        for (var i = 0; i < a.length; i++) {
          if (a[i] != b[i]) {
            return false;
          }
        }
        return true;
      }

      Map<String, dynamic> driverOf(List<dynamic> outputBits) =>
          cells.values.cast<Map<String, dynamic>>().singleWhere((c) {
            final y = (c['connections'] as Map)['Y'];
            return y is List && sameBits(y, outputBits);
          });

      final const1Driver = driverOf(const1Bits);
      final const0Driver = driverOf(const0Bits);
      expect(const1Driver['type'], r'$buf');
      expect(const0Driver['type'], r'$buf');

      // mux(Const(1), a4, b4) folds to a4; mux(Const(0), a4, b4) folds to b4.
      expect((const1Driver['connections'] as Map)['A'], equals(aBits));
      expect((const0Driver['connections'] as Map)['A'], equals(bBits));
    });

    test(r'dynamic synchronous reset flip-flops lower to $mux + $dff/$dffe',
        () {
      // 8 explicit register cells (dff/dffe/sdff/sdffe/adff/adffe/aldff/
      // aldffe) + 2 lowered dynamic-sync-reset flops (1 dff-shaped, 1
      // dffe-shaped) = 9 $dff-family cells total (dffe used twice: q_dffe
      // and the lowered en-variant).
      expect(cellsOfType(r'$dff'), hasLength(2)); // q_dff, q_dynsync_noen
      expect(cellsOfType(r'$dffe'), hasLength(2)); // q_dffe, q_dynsync_en
      expect(cellsOfType(r'$sdff'), hasLength(1));
      expect(cellsOfType(r'$sdffe'), hasLength(1));
      expect(cellsOfType(r'$adff'), hasLength(1));
      expect(cellsOfType(r'$adffe'), hasLength(1));
      expect(cellsOfType(r'$aldff'), hasLength(1));
      expect(cellsOfType(r'$aldffe'), hasLength(1));
    });
  });
}
