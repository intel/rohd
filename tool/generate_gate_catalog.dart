// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// generate_gate_catalog.dart
// Regenerates the checked-in gate-catalog netlist asset
// (`test/fixtures/gate_catalog.rohd.json`) from `GateCatalog` (see
// `test/fixtures/gate_catalog_module.dart`) using the default
// [NetlistSynthesizerConfiguration].
//
// Usage:
//   dart run tool/generate_gate_catalog.dart
//
// After regenerating, review the diff to `test/fixtures/gate_catalog.rohd.json`
// before committing it, and re-run `dart test test/gate_catalog_test.dart` to
// confirm the fixture, determinism, and coverage checks all pass.
//
// 2026 August 20
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';

import '../test/fixtures/gate_catalog_module.dart';

/// Relative (to the package root) output path for the generated fixture.
const _fixturePath = 'test/fixtures/gate_catalog.rohd.json';

/// Builds a fresh [GateCatalog] with deterministic, freshly-allocated input
/// signals.
///
/// This must stay in sync with `_buildCatalog()` in
/// `test/gate_catalog_test.dart` so that the fixture this tool generates is
/// exactly what that test's byte-for-byte comparison expects.
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

Future<void> main() async {
  final catalog = _buildCatalog();
  await catalog.build();

  final synth = NetlistSynthesizer();
  // We will migrate to a new public API in a future PR
  // ignore: invalid_use_of_visible_for_testing_member
  final json = synth.synthesizeToJson(catalog);

  final fixtureFile = File(_fixturePath);
  fixtureFile.parent.createSync(recursive: true);
  fixtureFile.writeAsStringSync(json);

  stdout.writeln('Wrote $_fixturePath (${json.length} bytes).');

  await Simulator.reset();
}
