// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// yosys_loader_io.dart
// VM implementation using Process to spawn node.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Result of running the Yosys loader.
class YosysLoaderResult {
  /// Whether the load was successful.
  final bool success;

  /// Number of root children modules.
  final int? rootChildren;

  /// Top node ID.
  final String? topNodeId;

  /// Number of top node ports.
  final int? topNodePorts;

  /// Error message if unsuccessful.
  final String? error;

  /// Stack trace if available.
  final String? stack;

  /// Creates a [YosysLoaderResult].
  YosysLoaderResult({
    required this.success,
    this.rootChildren,
    this.topNodeId,
    this.topNodePorts,
    this.error,
    this.stack,
  });

  /// Creates a [YosysLoaderResult] from JSON map [j].
  factory YosysLoaderResult.fromJson(Map<String, dynamic> j) =>
      YosysLoaderResult(
        success: j['success'] as bool,
        rootChildren: j['rootChildren'] as int?,
        topNodeId: j['topNodeId'] as String?,
        topNodePorts: j['topNodePorts'] as int?,
        error: j['error'] as String?,
        stack: j['stack'] as String?,
      );

  @override
  String toString() => success
      ? 'YosysLoaderResult(success, rootChildren: $rootChildren, '
          'topNodeId: $topNodeId, topNodePorts: $topNodePorts)'
      : 'YosysLoaderResult(failed: $error)';
}

/// VM implementation: run loader on a file path.
Future<YosysLoaderResult> runYosysLoader(String jsonPath) async {
  const node = 'node';
  const script =
      'lib/src/synthesizers/schematic/yosys/_yosys_loader_runner.mjs';
  ProcessResult result;
  try {
    result = await Process.run(node, [script, jsonPath]);
  } on Exception catch (e) {
    return YosysLoaderResult(success: false, error: 'Process.run failed: $e');
  }
  if (result.exitCode == 0) {
    final out = result.stdout.toString().trim();
    final map = json.decode(out) as Map<String, dynamic>;
    return YosysLoaderResult.fromJson(map);
  } else {
    final errOut = result.stderr.toString().trim();
    try {
      final map = json.decode(errOut) as Map<String, dynamic>;
      return YosysLoaderResult.fromJson(map);
    } on FormatException {
      return YosysLoaderResult(
          success: false,
          error: 'node runner failed: ${result.stderr}\n${result.stdout}');
    }
  }
}

/// VM implementation: spawn node process and pipe JSON via stdin.
Future<YosysLoaderResult> runYosysLoaderFromString(String jsonString) async {
  const node = 'node';
  const script =
      'lib/src/synthesizers/schematic/yosys/_yosys_loader_runner.mjs';
  ProcessResult result;
  try {
    final proc = await Process.start(node, [script, '-']);
    proc.stdin.write(jsonString);
    await proc.stdin.close();
    final exitCode = await proc.exitCode;
    final out = await proc.stdout.transform(const Utf8Decoder()).join();
    final err = await proc.stderr.transform(const Utf8Decoder()).join();
    result = ProcessResult(proc.pid, exitCode, out, err);
  } on Exception catch (e) {
    return YosysLoaderResult(success: false, error: 'Process.start failed: $e');
  }
  if (result.exitCode == 0) {
    final out = result.stdout.toString().trim();
    final map = json.decode(out) as Map<String, dynamic>;
    return YosysLoaderResult.fromJson(map);
  } else {
    final errOut = result.stderr.toString().trim();
    try {
      final map = json.decode(errOut) as Map<String, dynamic>;
      return YosysLoaderResult.fromJson(map);
    } on FormatException {
      return YosysLoaderResult(
          success: false,
          error: 'node runner failed: ${result.stderr}\n${result.stdout}');
    }
  }
}

/// Main entry point for command-line testing.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print(
        'Usage: dart run lib/src/synthesizers/schematic/yosys/yosys_loader_helper.dart <path-to-json>');
    return;
  }
  final result = await runYosysLoader(args[0]);
  print('success: ${result.success}');
  if (result.success) {
    print('rootChildren: ${result.rootChildren}');
    print('topNodeId: ${result.topNodeId}');
    print('topNodePorts: ${result.topNodePorts}');
  } else {
    print('error: ${result.error}');
    if (result.stack != null) {
      print('stack:\n${result.stack}');
    }
  }
}
