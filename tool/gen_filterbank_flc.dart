// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Regenerates the checked-in FilterBank netlist and FLC assets.
//
// Usage:
//   dart run tool/gen_filterbank_flc.dart

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';

import '../example/filter_bank/filter_bank_modules.dart';

Future<void> main() async {
  SourceTracer.activate();

  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final start = Logic(name: 'start');
  final samples = List.generate(2, (ch) => FilterSample(name: 'sample$ch'));
  final inputDone = Logic(name: 'inputDone');

  final dut = FilterBank(
    clk,
    reset,
    start,
    samples,
    inputDone,
    numTaps: 3,
    dataWidth: 16,
    coefficients: const [
      [1, 2, 1],
      [1, -2, 1],
    ],
  );
  await dut.build();

  final packageRoot = Directory.current.path;
  final sv = SystemVerilogService(dut, register: false);
  final trace = TraceService(
    dut,
    svService: sv,
    packageRoot: packageRoot,
    register: false,
  );
  final netlist = NetlistService(
    dut,
    packageRoot: packageRoot,
    register: false,
  );

  final temporaryDir = Directory.systemTemp.createTempSync(
    'filterbank-assets-',
  );
  try {
    trace.write(temporaryDir.path);
    final flc =
        File('${temporaryDir.path}/FilterBank.flc.json').readAsStringSync();
    final netlistJson =
        const JsonEncoder.withIndent('  ').convert(jsonDecode(netlist.json));

    for (final directory in const [
      'rohd_devtools_extension/assets',
      'rohd_devtools_extension/web/assets',
    ]) {
      Directory(directory).createSync(recursive: true);
      File('$directory/FilterBank.rohd.json').writeAsStringSync(netlistJson);
      File('$directory/FilterBank.traced.rohd.json')
          .writeAsStringSync(netlistJson);
      File('$directory/FilterBank.flc.json').writeAsStringSync(flc);
      File('$directory/FilterBank.traced.flc.json').writeAsStringSync(flc);
      stdout.writeln('Wrote FilterBank netlist and FLC assets to $directory');
    }

    final releaseAsset = File(
      '${Platform.environment['HOME']}/release/rohd-schematic-viewer/'
      'assets/FilterBank.rohd.json',
    );
    releaseAsset.parent.createSync(recursive: true);
    releaseAsset.writeAsStringSync(netlistJson);
    stdout.writeln('Wrote ${releaseAsset.path}');
  } finally {
    temporaryDir.deleteSync(recursive: true);
    await Simulator.reset();
  }
}
