// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// design_query_language.dart
// Typed query language for interactive ROHD design traversal.
//
// 2026 August 7
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

// RegExp's implementation-only deprecation is incorrectly reported at use
// sites by some Dart analysis-server versions.
// ignore_for_file: deprecated_member_use, unnecessary_ignore

import 'package:rohd_devtools_extension/rohd_devtools/cli/waveform_cli.dart';

import 'package:rohd_hierarchy/rohd_hierarchy.dart';
import 'package:rohd_schematic_viewer/schematic_connectivity.dart';

/// Small typed query language for interactive design traversal.
///
/// The language intentionally supports handles and query pipelines only; it
/// does not provide control flow, user-defined functions, or file execution.
class DesignQueryLanguage {
  /// Creates an evaluator backed by schematic connectivity.
  DesignQueryLanguage({required SchematicTraversalCli connectivity})
      : _connectivity = connectivity;

  final SchematicTraversalCli _connectivity;
  final Map<String, SignalOccurrence> _handles = {};

  /// Resolves an alias (`@name` or `$name`) or an address/path to a live signal
  /// handle.
  SignalOccurrence resolveSignalHandle(String reference) {
    final trimmed = reference.trim();
    if (trimmed.startsWith('@') || trimmed.startsWith(r'$')) {
      final handle = _handles[trimmed.substring(1)];
      if (handle == null) {
        throw FormatException('Unknown signal handle: $trimmed');
      }
      return handle;
    }
    final signal = _connectivity.resolveSignalHandle(trimmed);
    if (signal == null) {
      throw FormatException('Signal not found: $trimmed');
    }
    return signal;
  }

  /// Evaluates one query and returns a structured result.
  ///
  /// Supported forms are:
  ///
  /// * `select signal <address-or-path>`
  /// * `let <name> = select signal <address-or-path>`
  /// * `@<name> | fanin`
  /// * `@<name> | fanin transparent`
  /// * `@<name> | fanout`
  /// * `@<name> | fanout transparent`
  /// * `select signal <address-or-path> | fanin|fanout`
  DesignQueryResult evaluate(String input) {
    final assignment = RegExp(
      r'^let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    final expression = assignment?.group(2) ?? input.trim();
    final parts = expression.split('|').map((part) => part.trim()).toList();
    if (parts.isEmpty || parts.any((part) => part.isEmpty)) {
      throw const FormatException('A query must contain at least one stage.');
    }

    var value = _selectSignal(parts.first);
    for (final stage in parts.skip(1)) {
      value = _applyStage(value, stage);
    }
    if (assignment != null) {
      if (value is! SignalOccurrence) {
        throw const FormatException('Only a selected signal can be assigned.');
      }
      _handles[assignment.group(1)!] = value;
      return DesignQueryResult.signal(
        CliSignal.fromOccurrence(value),
        alias: assignment.group(1),
      );
    }
    return switch (value) {
      final SignalOccurrence signal => DesignQueryResult.signal(
          CliSignal.fromOccurrence(signal),
        ),
      final CliConnectivity connectivity => DesignQueryResult.connectivity(
          connectivity,
        ),
      _ => throw StateError('Unsupported query result.'),
    };
  }

  Object _selectSignal(String stage) {
    if (stage.startsWith('@')) {
      return resolveSignalHandle(stage);
    }
    final match = RegExp(
      r'^select\s+signal\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(stage);
    if (match == null) {
      throw const FormatException(
        'Start with `select signal <address-or-path>` or `@<handle>`.',
      );
    }
    return resolveSignalHandle(match.group(1)!);
  }

  Object _applyStage(Object value, String stage) {
    if (value is! SignalOccurrence) {
      throw const FormatException('Only a signal can be traversed.');
    }
    return switch (stage.toLowerCase()) {
      'fanin' => _connectivity.faninSignal(value),
      'fanin transparent' => _connectivity.faninSignal(
          value,
          mode: SchematicTraversalMode.transparent,
        ),
      'fanout' => _connectivity.fanoutSignal(value),
      'fanout transparent' => _connectivity.fanoutSignal(
          value,
          mode: SchematicTraversalMode.transparent,
        ),
      _ => throw FormatException('Unsupported query stage: $stage'),
    };
  }
}

/// Structured result returned by [DesignQueryLanguage].
class DesignQueryResult {
  const DesignQueryResult._({this.alias, this.signal, this.connectivity});

  /// Creates a selected signal result.
  const DesignQueryResult.signal(CliSignal signal, {String? alias})
      : this._(alias: alias, signal: signal);

  /// Creates a fan-in or fan-out result.
  const DesignQueryResult.connectivity(CliConnectivity connectivity)
      : this._(connectivity: connectivity);

  /// Alias assigned by a `let` expression, when applicable.
  final String? alias;

  /// Selected signal, when the query ends at selection.
  final CliSignal? signal;

  /// Connectivity result, when the query ends at traversal.
  final CliConnectivity? connectivity;

  /// Converts the result to a JSON-ready object.
  Map<String, dynamic> toJson() => {
        if (alias != null) 'alias': alias,
        if (signal != null) 'signal': signal!.toJson(),
        if (connectivity != null) ...connectivity!.toJson(),
      };
}
