// Copyright (C) 2025-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// slim_incremental_equivalence_test.dart
// Validates that assembling full data from slim + per-module fetches
// produces the same result as pulling the full netlist in one shot.

import 'dart:convert';

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

import '../example/example.dart' as ex;
import '../example/filter_bank.dart';
import '../example/fir_filter.dart';
import '../example/oven_fsm.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
    ModuleServices.instance.reset();
  });

  /// Builds [module] with netlist synthesis, then verifies that
  /// reassembling the full netlist from slim + per-module fetches
  /// produces a result equivalent to [toFullJson].
  ///
  /// For each module definition in the slim netlist:
  ///  1. Cell keys, types, and ordering must match the full netlist.
  ///  2. Port definitions (direction, bit indices) must match.
  ///  3. Fetching full data via [moduleJson] adds connections
  ///     that exactly match those in the full netlist.
  Future<void> validateSlimIncrementalEquivalence(Module module) async {
    await module.build();
    final netSvc = await NetlistService.create(module);

    // ── Pull full netlist in one shot ─────────────────────────────
    final fullJsonStr = netSvc.toJson();
    final fullNetlist = jsonDecode(fullJsonStr) as Map<String, dynamic>;
    final fullModules = fullNetlist['modules'] as Map<String, dynamic>;

    // ── Pull slim netlist ─────────────────────────────────────────
    final slimJsonStr = netSvc.slimJson;
    final slimUnified = jsonDecode(slimJsonStr) as Map<String, dynamic>;
    final slimNetlist = slimUnified['netlist'] as Map<String, dynamic>;
    final slimModules = slimNetlist['modules'] as Map<String, dynamic>;

    // ── Same set of module definition keys ────────────────────────
    expect(
      slimModules.keys.toSet(),
      equals(fullModules.keys.toSet()),
      reason: 'Slim and full should have identical module keys',
    );

    // ── Per-module comparison ─────────────────────────────────────
    final errors = <String>[];

    for (final moduleKey in fullModules.keys) {
      final fullMod = fullModules[moduleKey] as Map<String, dynamic>;
      final slimMod = slimModules[moduleKey] as Map<String, dynamic>;

      final fullCells = fullMod['cells'] as Map<String, dynamic>? ?? {};
      final slimCells = slimMod['cells'] as Map<String, dynamic>? ?? {};

      // ── Cell keys and ordering ──────────────────────────────────
      final fullCellKeys = fullCells.keys.toList();
      final slimCellKeys = slimCells.keys.toList();
      if (!_listsEqual(fullCellKeys, slimCellKeys)) {
        errors.add(
          '$moduleKey: cell keys differ — '
          'full=$fullCellKeys, slim=$slimCellKeys',
        );
        continue; // Skip deeper checks for this module
      }

      // ── Cell types match ────────────────────────────────────────
      for (final cellKey in fullCellKeys) {
        final fullCell = fullCells[cellKey] as Map<String, dynamic>;
        final slimCell = slimCells[cellKey] as Map<String, dynamic>;
        if (fullCell['type'] != slimCell['type']) {
          errors.add(
            '$moduleKey.$cellKey: type mismatch — '
            'full="${fullCell['type']}", slim="${slimCell['type']}"',
          );
        }
      }

      // ── Port definitions match ──────────────────────────────────
      final fullPorts = fullMod['ports'] as Map<String, dynamic>? ?? {};
      final slimPorts = slimMod['ports'] as Map<String, dynamic>? ?? {};
      if (!_listsEqual(fullPorts.keys.toList(), slimPorts.keys.toList())) {
        errors.add(
          '$moduleKey: port keys differ — '
          'full=${fullPorts.keys.toList()}, '
          'slim=${slimPorts.keys.toList()}',
        );
      } else {
        for (final portKey in fullPorts.keys) {
          final fullPort = fullPorts[portKey] as Map<String, dynamic>;
          final slimPort = slimPorts[portKey] as Map<String, dynamic>;
          if (fullPort['direction'] != slimPort['direction']) {
            errors.add('$moduleKey port $portKey: direction mismatch');
          }
          final fullBits = fullPort['bits'] as List?;
          final slimBits = slimPort['bits'] as List?;
          if (!_listsEqual(fullBits ?? [], slimBits ?? [])) {
            errors.add(
              '$moduleKey port $portKey: bits mismatch — '
              'full=$fullBits, slim=$slimBits',
            );
          }
        }
      }

      // ── Slim cells must NOT have connections ────────────────────
      for (final cellKey in slimCellKeys) {
        final slimCell = slimCells[cellKey] as Map<String, dynamic>;
        if (slimCell.containsKey('connections')) {
          errors.add(
            '$moduleKey.$cellKey: slim cell has connections '
            '(should be stripped)',
          );
        }
      }

      // ── Full cells must have connections ────────────────────────
      for (final cellKey in fullCellKeys) {
        final fullCell = fullCells[cellKey] as Map<String, dynamic>;
        if (!fullCell.containsKey('connections')) {
          errors.add('$moduleKey.$cellKey: full cell missing connections');
        }
      }

      // ── Fetch full data via moduleJson ─────────────────────────
      // This is the incremental-loading contract: for EVERY module
      // in the slim netlist, fetching full data must recover the
      // exact connections present in the one-shot full netlist.
      final fetchedStr = netSvc.moduleJson(moduleKey);
      final fetchedJson = jsonDecode(fetchedStr) as Map<String, dynamic>;
      if (fetchedJson.containsKey('status')) {
        errors.add('$moduleKey: moduleJson returned not_found');
        continue;
      }

      // The fetched result is {"creator":..., "modules": {key: data}}.
      final fetchedModules =
          fetchedJson['modules'] as Map<String, dynamic>? ?? fetchedJson;
      final fetchedMod = (fetchedModules[moduleKey] ??
          fetchedModules.values.first) as Map<String, dynamic>;

      final fetchedCells = fetchedMod['cells'] as Map<String, dynamic>? ?? {};

      // ── Fetched cell keys must match full ───────────────────────
      if (!_listsEqual(fetchedCells.keys.toList(), fullCellKeys)) {
        errors.add(
          '$moduleKey: fetched cell keys differ from full — '
          'fetched=${fetchedCells.keys.toList()}, '
          'full=$fullCellKeys',
        );
        continue;
      }

      // ── Fetched connections must match full exactly ─────────────
      for (final cellKey in fullCellKeys) {
        final fullCell = fullCells[cellKey] as Map<String, dynamic>;
        final fetchedCell = fetchedCells[cellKey] as Map<String, dynamic>;

        final fullConns =
            fullCell['connections'] as Map<String, dynamic>? ?? {};
        final fetchedConns =
            fetchedCell['connections'] as Map<String, dynamic>? ?? {};

        if (!_connectionsEqual(fullConns, fetchedConns)) {
          errors.add(
            '$moduleKey.$cellKey: connections mismatch — '
            'full=$fullConns, fetched=$fetchedConns',
          );
        }
      }

      // ── Fetched ports must match full ───────────────────────────
      final fetchedPorts = fetchedMod['ports'] as Map<String, dynamic>? ?? {};
      for (final portKey in fullPorts.keys) {
        final fullPort = fullPorts[portKey] as Map<String, dynamic>;
        final fetchedPort = fetchedPorts[portKey] as Map<String, dynamic>?;
        if (fetchedPort == null) {
          errors.add('$moduleKey port $portKey: missing in fetched data');
          continue;
        }
        if (fullPort['direction'] != fetchedPort['direction']) {
          errors.add(
            '$moduleKey port $portKey: direction mismatch '
            'in fetched data',
          );
        }
        final fullBits = fullPort['bits'] as List?;
        final fetchedBits = fetchedPort['bits'] as List?;
        if (!_listsEqual(fullBits ?? [], fetchedBits ?? [])) {
          errors.add(
            '$moduleKey port $portKey: bits mismatch — '
            'full=$fullBits, fetched=$fetchedBits',
          );
        }
      }
    }

    // ── Report ────────────────────────────────────────────────────
    if (errors.isNotEmpty) {
      fail('Slim incremental equivalence errors:\n${errors.join('\n')}');
    }
  }

  test('Counter: slim + incremental fetch == full', () async {
    final en = Logic(name: 'en');
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;
    final counter = ex.Counter(en, reset, clk);
    await validateSlimIncrementalEquivalence(counter);
  });

  test('FIR filter: slim + incremental fetch == full', () async {
    final en = Logic(name: 'en');
    final resetB = Logic(name: 'resetB');
    final clk = SimpleClockGenerator(10).clk;
    final inputVal = Logic(name: 'inputVal', width: 8);
    final fir = FirFilter(en, resetB, clk, inputVal, [0, 0, 0, 1], bitWidth: 8);
    await validateSlimIncrementalEquivalence(fir);
  });

  test('OvenModule: slim + incremental fetch == full', () async {
    final button = Logic(name: 'button', width: 2);
    final reset = Logic(name: 'reset');
    final clk = SimpleClockGenerator(10).clk;
    final oven = OvenModule(button, reset, clk);
    await validateSlimIncrementalEquivalence(oven);
  });

  test('FilterBank: slim + incremental fetch == full', () async {
    const dataWidth = 16;
    final clk = SimpleClockGenerator(10).clk;
    final reset = Logic(name: 'reset');
    final start = Logic(name: 'start');
    final samplesIn = LogicArray([2], dataWidth, name: 'samplesIn');
    final validIn = Logic(name: 'validIn');
    final inputDone = Logic(name: 'inputDone');

    final dut = FilterBank(
      clk,
      reset,
      start,
      samplesIn,
      validIn,
      inputDone,
      numTaps: 3,
      dataWidth: dataWidth,
      coefficients: [
        [1, 2, 1],
        [1, -2, 1],
      ],
    );
    await validateSlimIncrementalEquivalence(dut);
  });
}

/// Deep-compare two lists element by element.
bool _listsEqual(List<dynamic> a, List<dynamic> b) {
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

/// Compare two connection maps: {portName: [bit indices]}.
///
/// All bit indices are numeric IDs; order within each port's list matters
/// because it encodes the wire mapping.
bool _connectionsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final key in a.keys) {
    if (!b.containsKey(key)) {
      return false;
    }
    final aBits = a[key] as List?;
    final bBits = b[key] as List?;
    if (aBits == null && bBits == null) {
      continue;
    }
    if (aBits == null || bBits == null) {
      return false;
    }
    if (!_listsEqual(aBits, bBits)) {
      return false;
    }
  }
  return true;
}
