// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// design_command_shell.dart
// Target-owned textual command adapter for the ROHD design session.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/src/diagnostics/design_session_protocol.dart';

/// Canonical ROHD textual command language for terminal and debugger clients.
class RohdDesignCommandShell {
  /// Creates a command shell over a target-owned typed protocol handler.
  RohdDesignCommandShell(this._handler);

  final RohdDesignSessionProtocolHandler _handler;
  final Map<String, Object> _aliases = {};

  /// Canonical command names accepted by this shell.
  static const commands = <String>[
    'exit',
    'fanin',
    'fanout',
    'find-cell',
    'find-cells',
    'find-port',
    'find-ports',
    'find-signal',
    'find-signals',
    'get-value',
    'help',
    'let',
    'name',
    'quit',
    'send',
    'status',
  ];

  static const _assignmentHelp = 'let <name> = '
      'find-cell|find-cells|find-port|find-ports|find-signal|find-signals ...';

  /// Executes [input] synchronously for a paused debugger target.
  Map<String, Object?> execute(String input) {
    final assignment = RegExp(
      r'^let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    final expression = assignment?.group(2) ?? input.trim();
    if (expression == 'help') {
      return {'ok': true, 'commands': help()};
    }
    if (expression.startsWith(r'$') && !expression.contains(RegExp(r'\s'))) {
      final alias = _alias(expression);
      return {
        'ok': true,
        'result': alias is List ? {'items': alias} : alias,
      };
    }
    final words = _words(expression);
    if (words.isEmpty) {
      throw const FormatException('Enter a command or help.');
    }
    final response = _executeWords(words);
    if (assignment != null && response['ok'] == true) {
      _aliases[assignment.group(1)!] = _assignableResult(response['result']);
      return {...response, 'alias': assignment.group(1)};
    }
    return response;
  }

  /// Provides bounded candidates for [input] at [cursor].
  List<String> complete(String input, int cursor) {
    final boundedCursor = cursor.clamp(0, input.length);
    final start = _tokenStart(input, boundedCursor);
    final prefix = input.substring(start, boundedCursor);
    final before = input.substring(0, start).trim();
    final words = before.isEmpty ? const <String>[] : _words(before);
    final commandWords = _assignmentCommandWords(words);
    if (commandWords.isNotEmpty &&
        (commandWords.last == 'find-cell' ||
            commandWords.last == 'find-signal' ||
            commandWords.last == 'find-port')) {
      final method = commandWords.last == 'find-cell'
          ? RohdDesignSessionProtocol.completeCellPaths
          : commandWords.last == 'find-signal'
              ? RohdDesignSessionProtocol.completeSignalPaths
              : RohdDesignSessionProtocol.completePortPaths;
      final response = _handler.callSynchronously(method, {
        'prefix': prefix,
        'limit': 20,
      });
      final result = response['result'];
      if (response['ok'] == true && result is Map && result['items'] is List) {
        return (result['items'] as List).whereType<String>().toList();
      }
      return const [];
    }
    final options = words.length == 3 && words[0] == 'let' && words[2] == '='
        ? const [
            'find-cell',
            'find-cells',
            'find-port',
            'find-ports',
            'find-signal',
            'find-signals',
          ]
        : prefix.startsWith(r'$')
            ? _aliases.keys.map((alias) => r'$' + alias)
            : words.isEmpty
                ? commands
                : words.first == 'fanin' ||
                        words.first == 'fanout' ||
                        words.first == 'find-cells' ||
                        words.first == 'find-ports' ||
                        words.first == 'find-signals'
                    ? const ['transparent']
                    : const <String>[];
    return options.where((option) => option.startsWith(prefix)).toList()
      ..sort();
  }

  /// Lists the supported commands from the canonical command catalog.
  List<String> help() => const [
        'status',
        'find-cell <path>',
        'find-port <path>',
        r'find-ports <hierarchy-regex> [$root] [transparent]',
        'find-signal <path>',
        r'find-cells <hierarchy-regex> [$root] [transparent]',
        r'find-signals <hierarchy-regex> [$root] [transparent]',
        'fanin <signal> [transparent]',
        'fanout <signal> [transparent]',
        'get-value <signal> [time]',
        'name <occurrence>',
        'send <signal>',
        _assignmentHelp,
        'let creates an alias for one occurrence or an occurrence list.',
        r'Use $name, $name[index], or $name.length to inspect an alias.',
      ];

  Map<String, Object?> _executeWords(List<String> words) {
    switch (words.first) {
      case 'status':
        _expect(words, 1);
        return _call(RohdDesignSessionProtocol.status, const {});
      case 'find-cell':
        _expect(words, 2);
        return _call(RohdDesignSessionProtocol.findCell, {'path': words[1]});
      case 'find-signal':
        _expect(words, 2);
        if (words[1].contains('*') || words[1].contains('?')) {
          throw const FormatException(
            'find-signal resolves one exact path. '
            "'Use find-signals '.*' to search.",
          );
        }
        return _call(RohdDesignSessionProtocol.findSignal, {'path': words[1]});
      case 'find-port':
        _expect(words, 2);
        return _call(RohdDesignSessionProtocol.findPort, {'path': words[1]});
      case 'find-ports':
        return _find(words, RohdDesignSessionProtocol.findPorts);
      case 'find-cells':
        return _find(words, RohdDesignSessionProtocol.findCells);
      case 'find-signals':
        return _find(words, RohdDesignSessionProtocol.findSignals);
      case 'fanin':
        return _traverse(words, RohdDesignSessionProtocol.fanin);
      case 'fanout':
        return _traverse(words, RohdDesignSessionProtocol.fanout);
      case 'get-value':
        return _value(words);
      case 'name':
        _expect(words, 2);
        return _call(RohdDesignSessionProtocol.name, {
          'occurrence': _alias(words[1]),
        });
      case 'send':
        return _send(words);
      default:
        throw FormatException('Unknown ROHD command: ${words.first}');
    }
  }

  Map<String, Object?> _find(List<String> words, String method) {
    if (words.length < 2 || words.length > 4) {
      throw FormatException(
        '${words.first} expects a hierarchy regex, optional root, '
        'and optional transparent mode.',
      );
    }
    final transparent = words.last == 'transparent';
    if (words.length == 4 && !transparent) {
      throw const FormatException('Find mode must be transparent.');
    }
    final rootIndex =
        words.length == 4 || (words.length == 3 && !transparent) ? 2 : null;
    return _call(method, {
      'pattern': words[1],
      if (rootIndex != null) 'root': _alias(words[rootIndex]),
      if (transparent) 'transparent': true,
    });
  }

  Map<String, Object?> _traverse(List<String> words, String method) {
    if (words.length < 2 || words.length > 3) {
      throw FormatException(
        '${words.first} expects a signal and optional transparent mode.',
      );
    }
    final transparent = words.length == 3 && words[2] == 'transparent';
    if (words.length == 3 && !transparent) {
      throw const FormatException('Traversal mode must be transparent.');
    }
    return _call(method, {
      'signal': _alias(words[1]),
      if (transparent) 'transparent': true,
    });
  }

  Map<String, Object?> _value(List<String> words) {
    if (words.length < 2 || words.length > 3) {
      throw const FormatException(
        'get-value expects a signal and optional time.',
      );
    }
    final time = words.length == 3 ? int.tryParse(words[2]) : null;
    if (words.length == 3 && (time == null || time < 0)) {
      throw const FormatException('time must be a non-negative integer.');
    }
    return _call(RohdDesignSessionProtocol.getSignalValue, {
      'signal': _alias(words[1]),
      if (time != null) 'time': time,
    });
  }

  Map<String, Object?> _send(List<String> words) {
    _expect(words, 2);
    final alias = _alias(words[1]);
    final occurrences = alias is List ? alias : [alias];
    final paths = <String>[];

    for (final occurrence in occurrences) {
      final response = _call(RohdDesignSessionProtocol.name, {
        'occurrence': occurrence,
      });
      if (response['ok'] != true) {
        return response;
      }
      final result = response['result'];
      if (result is! Map ||
          result['path'] is! String ||
          (result['kind'] != 'signal' && result['kind'] != 'port')) {
        throw const FormatException(
          'send expects a signal or port alias, or a list of them.',
        );
      }
      paths.add(result['path']! as String);
    }

    return {
      'ok': true,
      'result': {'paths': paths},
    };
  }

  Map<String, Object?> _call(String method, Map<String, Object?> parameters) =>
      _handler.callSynchronously(method, parameters);

  Object _alias(String reference) {
    final match = RegExp(r'^\$([A-Za-z_][A-Za-z0-9_]*)(?:\[(\d+)\]|\.length)?$')
        .firstMatch(reference);
    if (match == null) {
      throw FormatException('Expected an occurrence alias, got: $reference');
    }
    final alias = _aliases[match.group(1)!];
    if (alias == null) {
      throw FormatException('Unknown occurrence alias: $reference');
    }
    final index = match.group(2);
    if (reference.endsWith('.length')) {
      if (alias is List) {
        return alias.length;
      }
      throw FormatException('Occurrence alias is not a list: $reference');
    }
    if (index != null) {
      if (alias is! List) {
        throw FormatException('Occurrence alias is not a list: $reference');
      }
      final value = int.parse(index);
      if (value >= alias.length) {
        throw FormatException(
          'Occurrence alias index is out of range: '
          '$reference',
        );
      }
      return alias[value] as Object;
    }
    return alias;
  }

  static Object _assignableResult(Object? result) {
    if (_isOccurrenceHandle(result)) {
      return _copyOccurrenceHandle(result);
    }
    if (result is Map && result['items'] is List) {
      final items = result['items'] as List;
      if (items.every(_isOccurrenceHandle)) {
        return items.map(_copyOccurrenceHandle).toList(growable: false);
      }
    }
    throw const FormatException(
      'Only an occurrence or a list of occurrences can be assigned.',
    );
  }

  static bool _isOccurrenceHandle(Object? value) =>
      value is Map && value['address'] is String;

  static Map<String, Object?> _copyOccurrenceHandle(Object? value) {
    if (value is! Map) {
      throw StateError('Expected an occurrence handle.');
    }
    return Map<String, Object?>.from(value);
  }

  static void _expect(List<String> words, int length) {
    if (words.length != length) {
      throw FormatException('${words.first} expects ${length - 1} arguments.');
    }
  }

  static List<String> _words(String input) =>
      RegExp(r'''(?:"([^"]*)"|'([^']*)'|(\S+))''')
          .allMatches(input)
          .map((match) => match.group(1) ?? match.group(2) ?? match.group(3)!)
          .toList();

  static List<String> _assignmentCommandWords(List<String> words) {
    if (words.length >= 3 && words[0] == 'let' && words[2] == '=') {
      return words.sublist(3);
    }
    return words;
  }

  static int _tokenStart(String input, int cursor) {
    var start = cursor;
    while (start > 0 && !RegExp(r'\s').hasMatch(input[start - 1])) {
      start--;
    }
    return start;
  }
}
