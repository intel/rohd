// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// shell_command_registry.dart
// Declarative command bindings for the target-owned ROHD shell.

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// A Dart implementation registered for a manifest command binding.
typedef ShellCommandHandler = ShellCommandResult Function(
  ShellCommandInvocation invocation,
);

/// Converts a shell literal or live variable to a declared command argument.
typedef ShellArgumentParser = Object? Function(Object? value);

/// Input supplied to a registered shell command.
class ShellCommandInvocation {
  /// Creates an invocation with arguments resolved by the registry.
  const ShellCommandInvocation(this.arguments, this.namedArguments);

  /// Live objects supplied positionally to the command.
  ///
  /// An argument such as `$selection` resolves to its in-memory value, rather
  /// than a serialized copy. This supports occurrence wrappers and lists.
  final List<Object?> arguments;

  /// Live arguments keyed by their manifest-defined names.
  final Map<String, Object?> namedArguments;

  /// Returns a typed argument declared by the command manifest.
  T argument<T>(String name) {
    final value = namedArguments[name];
    if (value is! T) {
      throw StateError('Argument $name is not a $T.');
    }
    return value;
  }

  /// Returns a type-checked list argument with its live elements preserved.
  List<T> argumentList<T>(String name) {
    final value = namedArguments[name];
    if (value is List<T>) {
      return value;
    }
    if (value is List && value.every((element) => element is T)) {
      return value.cast<T>();
    }
    throw StateError('Argument $name is not a list of $T.');
  }
}

/// A command result that retains a live value and exposes a JSON-ready view.
class ShellCommandResult {
  /// Creates a command result.
  const ShellCommandResult({required this.value, required this.output});

  /// Value retained when a command is assigned with `let`.
  final Object? value;

  /// JSON-ready response written to the terminal client.
  final Map<String, Object?> output;
}

/// Registry of manifest-selected shell commands and their live variables.
///
/// A manifest never evaluates Dart identifiers. Instead, each `handler` must
/// name a handler provided to this registry's constructor.
class ShellCommandRegistry {
  /// Creates a registry from the set of Dart handlers allowed by manifests.
  ShellCommandRegistry({
    required Map<String, ShellCommandHandler> handlers,
    Map<String, ShellArgumentParser> argumentParsers = const {},
  })  : _handlers = Map<String, ShellCommandHandler>.from(handlers),
        _argumentParsers = <String, ShellArgumentParser>{
          'String': _parseString,
          ...argumentParsers,
        };

  final Map<String, ShellCommandHandler> _handlers;
  final Map<String, ShellArgumentParser> _argumentParsers;
  final Map<String, _ShellCommandBinding> _bindings =
      <String, _ShellCommandBinding>{};
  final Map<String, Object?> _variables = <String, Object?>{};

  /// Adds or replaces a variable while retaining its live object identity.
  void setVariable(String name, Object? value) {
    _validateName(name, 'Variable');
    _variables[name] = value;
  }

  /// Registers a Dart handler that a subsequent manifest may reference.
  void registerHandler(String name, ShellCommandHandler handler) {
    _validateName(name, 'Handler');
    _handlers[name] = handler;
  }

  /// Registers a parser for a manifest argument type such as
  /// `SignalOccurrence` or `HierarchyOccurrence`.
  void registerArgumentParser(String type, ShellArgumentParser parser) {
    if (type.trim().isEmpty) {
      throw const FormatException('Argument type names cannot be empty.');
    }
    _argumentParsers[type] = parser;
  }

  /// Loads command bindings from a JSON or YAML manifest at [path].
  List<String> loadFile(String path) =>
      loadManifestText(File(path).readAsStringSync());

  /// Loads command bindings from a JSON or YAML [source].
  List<String> loadManifestText(String source) {
    final decoded = source.trimLeft().startsWith('{')
        ? jsonDecode(source)
        : loadYaml(source);
    final manifest = _asStringMap(decoded, 'Command manifest');
    final commandDefinitions = manifest['commands'];
    if (commandDefinitions is! List) {
      throw const FormatException(
        'A command manifest requires a commands list.',
      );
    }

    final loaded = <String>[];
    for (final definition in commandDefinitions) {
      final command = _asStringMap(definition, 'Command definition');
      final name = command['name'];
      final handler = command['handler'];
      final help = command['help'];
      final arguments = command['arguments'];
      if (name is! String || handler is! String || help is! String) {
        throw const FormatException(
          'Each command requires string name, handler, and help fields.',
        );
      }
      if (arguments is! List) {
        throw const FormatException('Each command requires an arguments list.');
      }
      _validateCommandName(name);
      final implementation = _handlers[handler];
      if (implementation == null) {
        throw FormatException('Unknown command handler: $handler');
      }
      _bindings[name] = _ShellCommandBinding(
        handler: implementation,
        help: help,
        arguments: [
          for (final argument in arguments)
            _ShellCommandArgument.fromManifest(argument),
        ],
      );
      loaded.add(name);
    }
    return loaded;
  }

  /// Evaluates an input line, including built-in help, load, and let commands.
  ShellCommandResult execute(String input) {
    final command = input.trim();
    if (command == 'help') {
      return ShellCommandResult(value: null, output: {'commands': help()});
    }
    if (command.startsWith('load ')) {
      final path = command.substring('load '.length).trim();
      if (path.isEmpty) {
        throw const FormatException('Usage: load <manifest-path>');
      }
      return ShellCommandResult(
        value: null,
        output: {'loaded': loadFile(path)},
      );
    }

    final assignment = RegExp(
      r'^let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(command);
    if (assignment != null) {
      final name = assignment.group(1)!;
      final result = execute(assignment.group(2)!);
      setVariable(name, result.value);
      return ShellCommandResult(
        value: result.value,
        output: {'variable': name, ...result.output},
      );
    }

    final words = _words(command);
    if (words.isEmpty) {
      throw const FormatException('Enter a command, help, or load <path>.');
    }
    final binding = _bindings[words.first];
    if (binding == null) {
      throw FormatException('Unknown command: ${words.first}');
    }
    final rawArguments = words.skip(1).map(_resolveArgument).toList();
    final requiredArguments =
        binding.arguments.where((argument) => argument.required).length;
    if (rawArguments.length < requiredArguments ||
        rawArguments.length > binding.arguments.length) {
      throw FormatException(
        '${words.first} expects $requiredArguments to '
        '${binding.arguments.length} arguments, '
        'got ${rawArguments.length}.',
      );
    }
    final arguments = <Object?>[];
    final namedArguments = <String, Object?>{};
    for (var index = 0; index < binding.arguments.length; index++) {
      final definition = binding.arguments[index];
      final rawValue = index < rawArguments.length
          ? rawArguments[index]
          : definition.defaultValue;
      final value = _parseArgument(rawValue, definition.type);
      arguments.add(value);
      namedArguments[definition.name] = value;
    }
    return binding.handler(ShellCommandInvocation(arguments, namedArguments));
  }

  /// Lists the commands exposed by currently loaded manifests.
  List<Map<String, Object?>> help() => [
        {
          'name': 'help',
          'help': 'List loaded commands.',
          'arguments': const <Object?>[],
        },
        {
          'name': 'load',
          'help': 'Load JSON or YAML command bindings.',
          'arguments': const [
            {'name': 'path', 'type': 'String'},
          ],
        },
        {
          'name': 'let',
          'help': 'Store a command result as a live variable.',
          'arguments': const <Object?>[],
        },
        for (final entry
            in _bindings.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key)))
          {
            'name': entry.key,
            'help': entry.value.help,
            'arguments': [
              for (final argument in entry.value.arguments)
                {
                  'name': argument.name,
                  'type': argument.type,
                  'required': argument.required,
                  if (!argument.required) 'default': argument.defaultValue,
                },
            ],
          },
      ];

  Object? _parseArgument(Object? value, String type) {
    final listMatch = RegExp(r'^list<(.+)>$').firstMatch(type);
    if (listMatch != null) {
      final elementType = listMatch.group(1)!;
      final rawValues = switch (value) {
        final List<Object?> values => values,
        final String encoded => _decodeList(encoded),
        _ => throw FormatException('$type requires a list value.'),
      };
      final parsed = rawValues
          .map((element) => _parseArgument(element, elementType))
          .toList();
      if (value is List && _hasIdenticalElements(value, parsed)) {
        return value;
      }
      return parsed;
    }
    final parser = _argumentParsers[type];
    if (parser == null) {
      throw FormatException('No parser is registered for argument type: $type');
    }
    return parser(value);
  }

  static String _parseString(Object? value) {
    if (value is String) {
      return value;
    }
    throw const FormatException('String arguments require string values.');
  }

  static List<Object?> _decodeList(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      throw const FormatException(
        'List arguments require a JSON list literal.',
      );
    }
    return List<Object?>.from(decoded);
  }

  static bool _hasIdenticalElements(List<Object?> left, List<Object?> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!identical(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  Object? _resolveArgument(String argument) {
    if (!argument.startsWith(r'$')) {
      return argument;
    }
    final name = argument.substring(1);
    _validateName(name, 'Variable');
    if (!_variables.containsKey(name)) {
      throw FormatException('Unknown variable: $argument');
    }
    return _variables[name];
  }

  static List<String> _words(String input) =>
      RegExp(r'''(?:"([^"]*)"|'([^']*)'|(\S+))''')
          .allMatches(input)
          .map((match) => match.group(1) ?? match.group(2) ?? match.group(3)!)
          .toList();

  static Map<String, Object?> _asStringMap(Object? value, String context) {
    if (value is! Map) {
      throw FormatException('$context must be a map.');
    }
    return Map<String, Object?>.from(value);
  }

  static void _validateName(String name, String kind) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      throw FormatException('$kind name is invalid: $name');
    }
  }

  static void _validateCommandName(String name) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(name)) {
      throw FormatException('Command name is invalid: $name');
    }
  }
}

class _ShellCommandBinding {
  const _ShellCommandBinding({
    required this.handler,
    required this.help,
    required this.arguments,
  });

  final ShellCommandHandler handler;
  final String help;
  final List<_ShellCommandArgument> arguments;
}

class _ShellCommandArgument {
  const _ShellCommandArgument({
    required this.name,
    required this.type,
    required this.required,
    this.defaultValue,
  });

  factory _ShellCommandArgument.fromManifest(Object? value) {
    final definition = ShellCommandRegistry._asStringMap(
      value,
      'Command argument definition',
    );
    final name = definition['name'];
    final type = definition['type'];
    final requiredValue = definition['required'];
    final hasDefault = definition.containsKey('default');
    if (name is! String || type is! String) {
      throw const FormatException(
        'Each command argument requires string name and type fields.',
      );
    }
    ShellCommandRegistry._validateName(name, 'Argument');
    if (type.trim().isEmpty) {
      throw const FormatException('Argument types cannot be empty.');
    }
    if (requiredValue != null && requiredValue is! bool) {
      throw const FormatException('Argument required must be a bool.');
    }
    final required = requiredValue as bool? ?? !hasDefault;
    if (required && hasDefault) {
      throw const FormatException(
        'Required command arguments cannot define a default.',
      );
    }
    if (!required && !hasDefault) {
      throw const FormatException(
        'Optional command arguments require a default.',
      );
    }
    return _ShellCommandArgument(
      name: name,
      type: type,
      required: required,
      defaultValue: definition['default'],
    );
  }

  final String name;
  final String type;
  final bool required;
  final Object? defaultValue;
}
