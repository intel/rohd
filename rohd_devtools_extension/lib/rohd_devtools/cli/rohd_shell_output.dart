// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_shell_output.dart
// Human-readable presentation for ROHD shell protocol responses.

import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show SignalValueFormat, SignalValueFormatRegistry;

/// Resolves the selected display format for a signal occurrence path.
typedef RohdSignalFormatResolver = SignalValueFormat Function(String path);

/// A formatted ROHD shell response with its presentation status.
class RohdShellOutput {
  /// Creates formatted shell [text] with an error status.
  const RohdShellOutput({required this.text, required this.isError});

  /// Converts a structured shell [response] to concise human-readable text.
  factory RohdShellOutput.pretty(
    Map<String, Object?> response, {
    RohdSignalFormatResolver? formatForPath,
  }) {
    if (response['ok'] != true) {
      final error = _map(response['error']);
      final code = error?['code'];
      final message = error?['message'];
      final detail = message ?? 'The command did not complete.';
      return RohdShellOutput(
        text: code == null ? 'error: $detail' : 'error [$code]: $detail',
        isError: true,
      );
    }

    final alias = response['alias'];
    final result = response['result'];
    final commands = response['commands'];
    final prefix = alias is String ? 'ok: \$$alias = ' : 'ok: ';
    if (commands is List) {
      return RohdShellOutput(
        text: 'ok: commands\n${_lines(commands.whereType<String>())}',
        isError: false,
      );
    }
    return RohdShellOutput(
      text: _formatResult(result, prefix, formatForPath),
      isError: false,
    );
  }

  /// The human-readable response text.
  final String text;

  /// Whether the response represents a command failure.
  final bool isError;

  static String _formatResult(
    Object? result,
    String prefix,
    RohdSignalFormatResolver? formatForPath,
  ) {
    if (result == null) {
      return '${prefix}no matching occurrence';
    }
    final map = _map(result);
    if (map != null) {
      if (map.containsKey('value') && map['address'] is String) {
        final time = map['time'];
        final sampleTime = map['sampleTime'];
        final timing = time == null
            ? ''
            : sampleTime == null
                ? ' at $time'
                : ' at $time (sampled $sampleTime)';
        final rawValue = map['value'];
        final path = map['path'];
        final width = map['width'];
        final selectedFormat = map['format'];
        final displayValue = rawValue is String && width is int
            ? _formatValue(
                rawValue,
                selectedFormat is String
                    ? SignalValueFormatRegistry.formatFromString(
                          selectedFormat,
                        ) ??
                        SignalValueFormat.waveform
                    : path is String
                        ? formatForPath?.call(path) ??
                            SignalValueFormat.waveform
                        : SignalValueFormat.waveform,
                width,
              )
            : rawValue;
        return '${prefix}value ${_occurrenceLabel(map)} ${map['address']} = '
            '$displayValue$timing';
      }
      if (map['path'] is String && map['address'] is String) {
        final details = <String>[
          'path: ${map['path']}',
          if (map['name'] != null) 'name: ${map['name']}',
          if (map['definition'] != null) 'definition: ${map['definition']}',
          if (map['width'] != null) 'width: ${map['width']}',
          if (map['direction'] != null) 'direction: ${map['direction']}',
        ];
        return '${prefix}occurrence ${_occurrenceLabel(map)} '
            '${map['address']}\n${_lines(details)}';
      }
      if (map['address'] is String) {
        return '${prefix}occurrence ${_occurrenceLabel(map)} '
            '${map['address']}';
      }
      if (map['paths'] is List) {
        final count = (map['paths']! as List).whereType<String>().length;
        return '${prefix}sent $count ${count == 1 ? 'signal' : 'signals'}';
      }
      final items = map['items'];
      if (items is List) {
        return _formatItems(items, prefix, map['nextPageToken']);
      }
      if (map.containsKey('ready') || map.containsKey('epoch')) {
        return _formatStatus(map, prefix);
      }
      return '${prefix}result received';
    }
    if (result is List) {
      return _formatItems(result, prefix, null);
    }
    return '$prefix$result';
  }

  static String _formatValue(
    String value,
    SignalValueFormat format,
    int width,
  ) =>
      SignalValueFormatRegistry.formatValue(value, format, width);

  static String _formatItems(
    List<Object?> items,
    String prefix,
    Object? nextPageToken,
  ) {
    final occurrenceCount =
        items.where((item) => _map(item)?['address'] is String).length;
    final label = occurrenceCount == 1 ? 'occurrence' : 'occurrences';
    final continuation = nextPageToken == null ? '' : ' (more available)';
    if (occurrenceCount == items.length) {
      return '$prefix$occurrenceCount $label$continuation';
    }
    return '$prefix${items.length} results$continuation';
  }

  static String _formatStatus(Map<Object?, Object?> result, String prefix) {
    final capabilities = result['capabilities'];
    final details = <String>[
      if (result['designName'] != null) 'design: ${result['designName']}',
      if (result['ready'] != null) 'ready: ${result['ready']}',
      if (result['epoch'] != null) 'epoch: ${result['epoch']}',
      if (capabilities is List) 'capabilities: ${capabilities.join(', ')}',
    ];
    return '$prefix status${details.isEmpty ? '' : '\n${_lines(details)}'}';
  }

  static String _lines(Iterable<String> values) =>
      values.map((value) => '  $value').join('\n');

  static String _occurrenceLabel(Map<Object?, Object?> value) {
    final kind = value['kind'];
    return kind is String ? kind : 'unknown';
  }

  static Map<Object?, Object?>? _map(Object? value) =>
      value is Map ? value : null;
}
