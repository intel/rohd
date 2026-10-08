// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// generate_gate_catalog.dart
// Generates a gate-catalog netlist from `GateCatalog` using the default
// [NetlistSynthesizerConfiguration].
//
// Usage:
//   dart run tool/generate_gate_catalog.dart [output-path]
//
// 2026 August 20
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';

import 'gate_catalog.dart';

/// Default output path relative to the current working directory.
const _defaultOutputPath = 'gate_catalog.rohd.json';

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

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln(
      'Usage: dart run tool/generate_gate_catalog.dart [output-path]',
    );
    exitCode = 64;
    return;
  }
  final outputPath = arguments.isEmpty ? _defaultOutputPath : arguments.single;
  final catalog = _buildCatalog();
  await catalog.build();

  final synth = NetlistSynthesizer();
  final json = synth.synthesizeToJson(catalog);

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(json);

  stdout.writeln('Wrote $outputPath (${json.length} bytes).');

  await Simulator.reset();
}
