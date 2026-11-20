// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// yosys_netlist_miter.dart
// Compare a ROHD JSON netlist with its SystemVerilog using Yosys.
//
// 2026 November 20
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

String _yosysPath(String path, String workingDirectory) {
  final file = File(path).absolute;
  final name = file.parent.path == workingDirectory
      ? file.uri.pathSegments.last
      : file.path;
  if (RegExp(r'["\\;\r\n]').hasMatch(name)) {
    throw ArgumentError.value(
        path, 'path', 'Unsupported Yosys path character.');
  }
  return '"$name"';
}

Future<void> main(List<String> args) async {
  if ((args.length != 3 && args.length != 4) ||
      !RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(args[2])) {
    stderr.writeln('Usage: dart run tool/yosys_netlist_miter.dart '
        '<netlist.json> <design.sv> <top> [techmap.v]');
    exitCode = 64;
    return;
  }

  final netlist = await File(args[0]).readAsString();
  final document = jsonDecode(netlist) as Map<String, dynamic>;
  final modules = document['modules'] as Map<String, dynamic>;
  final top = modules[args[2]] as Map<String, dynamic>?;
  if (top == null) {
    throw ArgumentError('Netlist does not contain top module ${args[2]}.');
  }
  final ports = top['ports'] as Map<String, dynamic>;
  if (!ports.values.cast<Map<String, dynamic>>().any((port) =>
      port['direction'] == 'output' && (port['bits'] as List).isNotEmpty)) {
    throw ArgumentError('The top module must have a nonempty output.');
  }

  final workingDirectory = File(args[0]).absolute.parent.path;
  final commands = [
    'read_json ${_yosysPath(args[0], workingDirectory)}',
    if (args.length == 4)
      'techmap -map ${_yosysPath(args[3], workingDirectory)}',
    'hierarchy -check -top ${args[2]}',
    'flatten',
    'check -assert',
    'rename ${args[2]} gold',
    'design -stash gold',
    'read_verilog -sv ${_yosysPath(args[1], workingDirectory)}',
    'hierarchy -check -top ${args[2]}',
    'proc',
    'flatten',
    'check -assert',
    'rename ${args[2]} gate',
    'design -stash gate',
    'design -copy-from gold gold',
    'design -copy-from gate gate',
    'miter -equiv -flatten gold gate miter',
    'hierarchy -top miter',
    'sat -verify -prove trigger 0 miter',
  ];
  final result = await Process.run(
    Platform.environment['ROHD_YOSYS'] ?? 'yosys',
    ['-p', commands.join('; ')],
    workingDirectory: workingDirectory,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}
