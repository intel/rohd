// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';

import 'package:rohd/src/diagnostics/shell_command_registry.dart';
import 'package:test/test.dart';

class _TestSignalOccurrence {
  const _TestSignalOccurrence(this.id);

  final String id;
}

void main() {
  test('parses typed occurrence arguments and preserves live lists', () {
    const signalA = _TestSignalOccurrence('top/a');
    const signalB = _TestSignalOccurrence('top/b');
    const signals = {'top/a': signalA, 'top/b': signalB};
    final registry = ShellCommandRegistry(
      argumentParsers: {
        'SignalOccurrence': (value) {
          if (value is _TestSignalOccurrence) {
            return value;
          }
          if (value is String && signals.containsKey(value)) {
            return signals[value]!;
          }
          throw FormatException('Unknown signal occurrence: $value');
        },
      },
      handlers: {
        'identity': (invocation) {
          final selection = invocation.argumentList<_TestSignalOccurrence>(
            'selection',
          );
          return ShellCommandResult(
            value: invocation.argument<List<Object?>>('selection'),
            output: {
              'ids': selection
                  .cast<_TestSignalOccurrence>()
                  .map((signal) => signal.id)
                  .toList(),
            },
          );
        },
      },
    );
    final occurrenceList = <Object?>[signalA, signalB];
    registry
      ..loadManifestText('''
commands:
  - name: inspect
    handler: identity
    help: Inspect a live occurrence wrapper.
    arguments:
      - name: selection
        type: list<SignalOccurrence>
''')
      ..setVariable('selection', occurrenceList);

    final variableResult = registry.execute(r'inspect $selection');
    final literalResult = registry.execute('''inspect '["top/a", "top/b"]' ''');

    expect(identical(variableResult.value, occurrenceList), isTrue);
    expect(literalResult.output, {
      'ids': ['top/a', 'top/b'],
    });
    expect(
      registry.help().any((command) {
        if (command['name'] != 'inspect') {
          return false;
        }
        final arguments = command['arguments']! as List<Object?>;
        final argumentValue = arguments.single;
        if (argumentValue is! Map) {
          return false;
        }
        final argument = Map<String, Object?>.from(argumentValue);
        return argument['name'] == 'selection' &&
            argument['type'] == 'list<SignalOccurrence>';
      }),
      isTrue,
    );
  });

  test('loads JSON bindings and assigns live command results', () {
    final value = Object();
    final registry = ShellCommandRegistry(
      argumentParsers: {'Occurrence': (value) => value},
      handlers: {
        'lookup': (_) =>
            ShellCommandResult(value: value, output: {'id': 'top/a'}),
        'same': (invocation) => ShellCommandResult(
              value: null,
              output: {
                'sameObject': identical(invocation.arguments.single, value)
              },
            ),
      },
    );
    final result = (registry
          ..loadManifestText('''
{"commands":[
  {"name":"lookup","handler":"lookup","help":"Look up a signal.","arguments":[]},
  {"name":"same","handler":"same","help":"Compare a signal.","arguments":[{"name":"signal","type":"Occurrence"}]}
]}
''')
          ..execute('let signal = lookup'))
        .execute(r'same $signal');

    expect(result.output, {'sameObject': true});
  });

  test('loads command bindings from a manifest file', () {
    final manifest = File(
      '${Directory.systemTemp.path}/rohd-shell-${DateTime.now().microsecondsSinceEpoch}.yaml',
    )..writeAsStringSync('''
commands:
  - name: inspect
    handler: status
    help: Inspect target state.
    arguments: []
''');
    addTearDown(manifest.deleteSync);
    final registry = ShellCommandRegistry(
      handlers: {
        'status': (_) =>
            const ShellCommandResult(value: null, output: {'ready': true}),
      },
    );

    final loadResult = registry.execute('load ${manifest.path}');
    final commandResult = registry.execute('inspect');

    expect(loadResult.output['loaded'], ['inspect']);
    expect(commandResult.output, {'ready': true});
  });

  test('binds a handler registered after registry creation', () {
    final registry = ShellCommandRegistry(
      handlers: const <String, ShellCommandHandler>{},
    );
    final result = (registry
          ..registerHandler(
            'lookup',
            (_) => const ShellCommandResult(
              value: 'occurrence',
              output: {'id': 'top/a'},
            ),
          )
          ..loadManifestText('''
commands:
  - name: signal
    handler: lookup
    help: Look up a signal.
    arguments: []
'''))
        .execute('signal');

    expect(result.output, {'id': 'top/a'});
  });

  test('uses typed defaults for optional manifest arguments', () {
    final registry = ShellCommandRegistry(
      handlers: {
        'search': (invocation) => ShellCommandResult(
              value: null,
              output: {
                'query': invocation.argument<String>('query'),
                'root': invocation.argument<String>('root'),
              },
            ),
      },
    )..loadManifestText('''
commands:
  - name: find
    handler: search
    help: Find occurrences.
    arguments:
      - name: query
        type: String
      - name: root
        type: String
        default: top
''');

    expect(registry.execute('find clock').output, {
      'query': 'clock',
      'root': 'top',
    });
    expect(registry.execute('find clock child').output, {
      'query': 'clock',
      'root': 'child',
    });
    expect(
      () => registry.loadManifestText('''
commands:
  - name: invalid
    handler: search
    help: Invalid optional argument.
    arguments:
      - name: root
        type: String
        required: false
'''),
      throwsFormatException,
    );
  });
}
