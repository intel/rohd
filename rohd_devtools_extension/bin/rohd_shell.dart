// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_shell.dart
// Terminal client for the target-owned ROHD DTD shell service.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dtd/dtd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_shell_output.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';

const _usage = r'''
Usage: rohd-shell --dtd <ws-uri> [--json] [shell command]
  rohd-shell --dtd <ws-uri> [--json] --file <script-path>
  rohd-shell --dtd <ws-uri> --list-vms

With a command, prints one human-readable response. Without one, starts an
interactive shell. With --file, prints one response for each non-empty script
line. Use --json to preserve the complete protocol response for scripts. The
DTD and a debugged ROHD design must be running. Interactive mode supports line
editing and Up/Down command history. Ctrl-C cancels a running command; Ctrl-D
closes the shell.

When several VMs are registered, select one interactively or use --vm
<name-or-uri>. The shell uses the typed ROHD design-session protocol only.

Typed commands:
  status
  find-cell <path>
  find-port <path>
  find-ports <hierarchy-regex> [root-alias] [transparent]
  find-signal <path>
  find-cells <hierarchy-regex> [root-alias] [transparent]
  find-signals <hierarchy-regex> [root-alias] [transparent]
  fanin <signal-alias> [transparent]
  fanout <signal-alias> [transparent]
  name <occurrence-alias>
  let <name> = find-cell|find-cells|find-port|find-ports|find-signal|find-signals ...

Occurrence results are compact address handles. `name` expands one handle with
its path and metadata. Entering `$name` displays an alias directly; lists show
only their count. Hierarchy regex/glob rules are shared with ROHD DevTools
widgets. Use * and ? as glob wildcards, ** to cross any number of hierarchy
levels, and regex operators within a path segment. Unqualified patterns search
at any depth.''';

Future<void> main(List<String> arguments) async {
  final unknownOption = _unknownOption(arguments);
  if (unknownOption != null) {
    stderr
      ..writeln('rohd-shell: unknown option: $unknownOption')
      ..writeln(_usage);
    exitCode = 64;
    return;
  }
  final command = _command(arguments);
  final jsonOutput = arguments.contains('--json');
  if (command == 'exit' || command == 'quit') {
    return;
  }
  final dtdUri = _dtdUri(arguments);
  if (dtdUri == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final vmSelector = _vmSelector(arguments);
  if (arguments.contains('--vm') && vmSelector == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (arguments.contains('--list-vms')) {
    await _listVmServices(dtdUri);
    return;
  }
  final scriptPath = _scriptPath(arguments);
  if (arguments.contains('--file') && scriptPath == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (scriptPath != null && command.isNotEmpty) {
    stderr.writeln('rohd-shell: specify a command or --file, not both.');
    exitCode = 64;
    return;
  }
  try {
    final session = await _connectTypedShell(dtdUri, vmSelector: vmSelector);
    try {
      if (scriptPath != null) {
        await _executeScriptAndWrite(
          session,
          await File(scriptPath).readAsString(),
          jsonOutput: jsonOutput,
        );
      } else if (command.isNotEmpty) {
        await _executeAndWrite(session, command, jsonOutput: jsonOutput);
      } else {
        await _runInteractive(session, jsonOutput: jsonOutput);
      }
    } finally {
      await session.dispose();
    }
  } on Object catch (error) {
    stderr.writeln('rohd-shell: $error');
    exitCode = 1;
  }
  exit(exitCode);
}

String? _unknownOption(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--json' || argument == '--list-vms') {
      continue;
    }
    if (argument == '--dtd' || argument == '--file' || argument == '--vm') {
      index++;
      continue;
    }
    if (argument.startsWith('--')) {
      return argument;
    }
  }
  return null;
}

String? _vmSelector(List<String> arguments) {
  final vmIndex = arguments.indexOf('--vm');
  if (vmIndex < 0 || vmIndex + 1 >= arguments.length) {
    return null;
  }
  return arguments[vmIndex + 1];
}

Uri? _dtdUri(List<String> arguments) {
  final dtdIndex = arguments.indexOf('--dtd');
  if (dtdIndex < 0 || dtdIndex + 1 >= arguments.length) {
    return null;
  }
  final uri = Uri.tryParse(arguments[dtdIndex + 1]);
  return uri != null && (uri.isScheme('ws') || uri.isScheme('wss'))
      ? uri
      : null;
}

String? _scriptPath(List<String> arguments) {
  final fileIndex = arguments.indexOf('--file');
  if (fileIndex < 0 || fileIndex + 1 >= arguments.length) {
    return null;
  }
  return arguments[fileIndex + 1];
}

String _command(List<String> arguments) {
  final words = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--json' || argument == '--list-vms') {
      continue;
    }
    if (argument == '--dtd' || argument == '--file' || argument == '--vm') {
      index++;
      continue;
    }
    words.add(argument);
  }
  return words.join(' ');
}

Future<void> _runInteractive(
  _ShellSession session, {
  required bool jsonOutput,
}) async {
  stdout.writeln('Connected to the ROHD shell. Type `exit` to close.');
  final editor = _TerminalLineEditor(session.completionCandidates);
  while (true) {
    final input = (await editor.readLine('rohd> '))?.trim();
    if (input == null) {
      stdout.writeln();
      return;
    }
    if (input == 'exit' || input == 'quit') {
      return;
    }
    if (input.isNotEmpty) {
      await _executeInteractiveAndWrite(
        session,
        input,
        jsonOutput: jsonOutput,
      );
    }
  }
}

Future<void> _executeInteractiveAndWrite(
  _ShellSession session,
  String input, {
  required bool jsonOutput,
}) async {
  if (!stdin.hasTerminal) {
    await _executeAndWrite(
      session,
      input,
      jsonOutput: jsonOutput,
    );
    return;
  }
  final interrupted = Completer<void>();
  final interruptSubscription = ProcessSignal.sigint.watch().listen((_) {
    if (!interrupted.isCompleted) {
      interrupted.complete();
    }
  });
  final command = session.execute(input);
  try {
    final outcome =
        await Future.any<({bool interrupted, Map<String, Object?>? response})>([
      command.then(
        (response) => (interrupted: false, response: response),
      ),
      interrupted.future.then(
        (_) => (interrupted: true, response: null),
      ),
    ]);
    if (!outcome.interrupted) {
      _writeResponse(outcome.response!, jsonOutput: jsonOutput);
      return;
    }
    await session.cancelActiveCommand();
    try {
      await command;
    } on Object {
      // Closing the command's connection rejects its in-flight request.
    }
    stdout.writeln('^C');
  } finally {
    await interruptSubscription.cancel();
  }
}

class _TerminalLineEditor {
  _TerminalLineEditor(this._completionCandidates);

  final List<String> _history = [];
  final Future<List<String>> Function(String input, int cursor)
      _completionCandidates;
  final StreamIterator<List<int>> _input = StreamIterator(stdin);
  final List<int> _pendingBytes = [];

  Future<String?> readLine(String prompt) async {
    if (!stdin.hasTerminal) {
      stdout.write(prompt);
      return stdin.readLineSync();
    }

    var buffer = '';
    var cursor = 0;
    var historyIndex = _history.length;
    stdout.write(prompt);
    final previousEcho = stdin.echoMode;
    final previousLineMode = stdin.lineMode;
    stdin
      ..echoMode = false
      ..lineMode = false;
    try {
      while (true) {
        final byte = await _readByte();
        if (byte < 0) {
          return null;
        }
        switch (byte) {
          case 1:
            cursor = 0;
          case 5:
            cursor = buffer.length;
          case 3:
            return null;
          case 4:
            if (buffer.isEmpty) {
              return null;
            }
            if (cursor < buffer.length) {
              buffer =
                  buffer.substring(0, cursor) + buffer.substring(cursor + 1);
            }
          case 11:
            buffer = buffer.substring(0, cursor);
          case 12:
            stdout.write('\x1b[2J\x1b[H');
          case 14:
            if (historyIndex < _history.length) {
              historyIndex++;
              buffer =
                  historyIndex == _history.length ? '' : _history[historyIndex];
              cursor = buffer.length;
            }
          case 16:
            if (historyIndex > 0) {
              buffer = _history[--historyIndex];
              cursor = buffer.length;
            }
          case 21:
            buffer = buffer.substring(cursor);
            cursor = 0;
          case 23:
            final start = _previousWordStart(buffer, cursor);
            buffer = buffer.substring(0, start) + buffer.substring(cursor);
            cursor = start;
          case 10:
          case 13:
            stdout.writeln();
            if (buffer.isNotEmpty) {
              _history.add(buffer);
            }
            return buffer;
          case 8:
          case 127:
            if (cursor > 0) {
              buffer =
                  buffer.substring(0, cursor - 1) + buffer.substring(cursor);
              cursor--;
            }
          case 9:
            final completion = await _complete(buffer, cursor);
            buffer = completion.buffer;
            cursor = completion.cursor;
            if (completion.candidates.isEmpty) {
              stdout.write('\x07');
            } else if (completion.showCandidates) {
              stdout
                ..writeln()
                ..writeln(completion.candidates.join('  '));
            }
          case 27:
            final next = await _readByte();
            final key = next == 91 || next == 79 ? await _readByte() : -1;
            switch (key) {
              case 65:
                if (historyIndex > 0) {
                  buffer = _history[--historyIndex];
                  cursor = buffer.length;
                }
              case 66:
                if (historyIndex < _history.length) {
                  historyIndex++;
                  buffer = historyIndex == _history.length
                      ? ''
                      : _history[historyIndex];
                  cursor = buffer.length;
                }
              case 67:
                if (cursor < buffer.length) {
                  cursor++;
                }
              case 68:
                if (cursor > 0) {
                  cursor--;
                }
              case 72:
                cursor = 0;
              case 70:
                cursor = buffer.length;
              case 51:
                if (await _readByte() == 126 && cursor < buffer.length) {
                  buffer = buffer.substring(0, cursor) +
                      buffer.substring(cursor + 1);
                }
            }
          default:
            if (byte >= 32) {
              final character = String.fromCharCode(byte);
              buffer = buffer.substring(0, cursor) +
                  character +
                  buffer.substring(cursor);
              cursor++;
            }
        }
        _redraw(prompt, buffer, cursor);
      }
    } finally {
      stdin
        ..echoMode = previousEcho
        ..lineMode = previousLineMode;
    }
  }

  Future<
      ({
        String buffer,
        int cursor,
        List<String> candidates,
        bool showCandidates,
      })> _complete(String buffer, int cursor) async {
    final candidates = await _completionCandidates(buffer, cursor);
    if (candidates.isEmpty) {
      return (
        buffer: buffer,
        cursor: cursor,
        candidates: candidates,
        showCandidates: false,
      );
    }
    final start = _tokenStart(buffer, cursor);
    final prefix = buffer.substring(start, cursor);
    final replacement = _sharedPrefix(candidates);
    if (replacement.length > prefix.length) {
      return (
        buffer:
            buffer.substring(0, start) + replacement + buffer.substring(cursor),
        cursor: start + replacement.length,
        candidates: candidates,
        showCandidates: false,
      );
    }
    return (
      buffer: buffer,
      cursor: cursor,
      candidates: candidates,
      showCandidates: candidates.length > 1,
    );
  }

  static int _tokenStart(String input, int cursor) {
    var start = cursor.clamp(0, input.length);
    while (start > 0 && !RegExp(r'\s').hasMatch(input[start - 1])) {
      start--;
    }
    return start;
  }

  static String _sharedPrefix(Iterable<String> candidates) {
    final values = candidates.toList(growable: false);
    if (values.isEmpty) {
      return '';
    }
    var prefix = values.first;
    for (final value in values.skip(1)) {
      var length = 0;
      while (length < prefix.length &&
          length < value.length &&
          prefix.codeUnitAt(length) == value.codeUnitAt(length)) {
        length++;
      }
      prefix = prefix.substring(0, length);
    }
    return prefix;
  }

  Future<int> _readByte() async {
    if (_pendingBytes.isNotEmpty) {
      return _pendingBytes.removeAt(0);
    }
    if (!await _input.moveNext()) {
      return -1;
    }
    _pendingBytes.addAll(_input.current);
    return _pendingBytes.removeAt(0);
  }

  static int _previousWordStart(String buffer, int cursor) {
    var start = cursor;
    while (start > 0 && buffer[start - 1].trim().isEmpty) {
      start--;
    }
    while (start > 0 && buffer[start - 1].trim().isNotEmpty) {
      start--;
    }
    return start;
  }

  void _redraw(String prompt, String buffer, int cursor) {
    stdout.write('\r$prompt$buffer\x1b[K');
    final remaining = buffer.length - cursor;
    if (remaining > 0) {
      stdout.write('\x1b[${remaining}D');
    }
  }
}

Future<_ShellSession> _connectTypedShell(
  Uri dtdUri, {
  String? vmSelector,
}) async {
  final dtd = await DartToolingDaemon.connect(dtdUri);
  try {
    final connected = await _connectTypedTarget(dtdUri, vmSelector: vmSelector);
    return _TypedShellSession(
      dtd,
      () async {
        final commandTarget = await _connectTypedTarget(
          dtdUri,
          vmSelector: connected.selector,
        );
        return commandTarget.target;
      },
      initialTarget: connected.target,
    );
  } catch (_) {
    await dtd.close();
    rethrow;
  }
}

class _ConnectedTypedTarget {
  const _ConnectedTypedTarget(this.target, this.selector);

  final VmServiceRohdDesignTarget target;
  final String selector;
}

Future<void> _listVmServices(Uri dtdUri) async {
  final dtd = await DartToolingDaemon.connect(dtdUri);
  try {
    final services = (await dtd.getVmServices()).vmServicesInfos;
    stdout.writeln(
      jsonEncode({
        'vms': [
          for (final service in services)
            {
              'name': service.name,
              'uri': service.uri,
              if (service.exposedUri != null) 'exposedUri': service.exposedUri,
            },
        ],
      }),
    );
  } finally {
    await dtd.close();
  }
}

Future<_ConnectedTypedTarget> _connectTypedTarget(
  Uri dtdUri, {
  String? vmSelector,
}) async {
  final directVmUri = _directVmUri(vmSelector);
  if (directVmUri != null) {
    final target = await _connectTypedVm(directVmUri);
    return target;
  }
  final dtd = await DartToolingDaemon.connect(dtdUri);
  try {
    var services = (await dtd.getVmServices()).vmServicesInfos;
    if (services.isEmpty) {
      throw StateError('DTD has no registered VM services.');
    }
    var selection = vmSelector;
    var candidates = _selectVmServices(services, selection);
    if (candidates.isEmpty) {
      throw StateError(
        'No DTD VM matches "$vmSelector". Run --list-vms to inspect targets.',
      );
    }
    if (selection == null && candidates.length > 1) {
      final selected = await _chooseVmService(candidates);
      selection = selected.name ?? selected.exposedUri ?? selected.uri;
      candidates = [selected];
    }
    final failures = <String>[];
    const attemptCount = 5;
    for (var attempt = 1; attempt <= attemptCount; attempt++) {
      for (final service in candidates) {
        final endpoints = <String>[
          service.uri,
          if (service.exposedUri != null) service.exposedUri!,
        ];
        for (final vmServiceUri in endpoints) {
          VmServiceRohdDesignTarget? target;
          try {
            final result = await IoVmConnectionStrategy().connect(vmServiceUri);
            target =
                VmServiceRohdDesignTarget(result.vmService, result.isolateId);
            await target.register();
            return _ConnectedTypedTarget(
              target,
              selection ?? service.name ?? service.uri,
            );
          } on Object catch (error) {
            await target?.vmService.dispose();
            failures.add('${service.name ?? vmServiceUri}: $error');
          }
        }
      }
      if (attempt == attemptCount) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      services = (await dtd.getVmServices()).vmServicesInfos;
      candidates = _selectVmServices(services, selection);
      if (candidates.isEmpty) {
        failures.add('DTD no longer reports "$selection".');
      }
    }
    throw StateError(
      'Selected ROHD VM did not become available after $attemptCount '
      'attempts. ${failures.join('; ')}',
    );
  } finally {
    await dtd.close();
  }
}

/// Connects to an explicitly selected VM service without DTD discovery.
Future<_ConnectedTypedTarget> _connectTypedVm(String vmServiceUri) async {
  VmServiceRohdDesignTarget? target;
  try {
    final result = await IoVmConnectionStrategy().connect(vmServiceUri);
    target = VmServiceRohdDesignTarget(result.vmService, result.isolateId);
    await target.register();
    return _ConnectedTypedTarget(target, vmServiceUri);
  } on Object {
    await target?.vmService.dispose();
    rethrow;
  }
}

/// Returns [selector] when it is a direct VM service endpoint.
String? _directVmUri(String? selector) {
  final uri = selector == null ? null : Uri.tryParse(selector);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  return uri.isScheme('ws') ||
          uri.isScheme('wss') ||
          uri.isScheme('http') ||
          uri.isScheme('https')
      ? selector
      : null;
}

Future<VmServiceInfo> _chooseVmService(List<VmServiceInfo> services) async {
  if (!stdin.hasTerminal) {
    throw StateError(
      'Multiple DTD VM services are available. Specify --vm <name-or-uri>.',
    );
  }
  stdout.writeln('Available ROHD VM services:');
  for (var index = 0; index < services.length; index++) {
    final service = services[index];
    final uri = service.exposedUri ?? service.uri;
    stdout.writeln('  ${index + 1}. ${service.name ?? 'Unnamed VM'} ($uri)');
  }
  final editor = _TerminalLineEditor((_, __) async => const []);
  while (true) {
    final input =
        (await editor.readLine('Select VM [1-${services.length}]: '))?.trim();
    final selected = input == null ? null : int.tryParse(input);
    if (selected != null && selected >= 1 && selected <= services.length) {
      return services[selected - 1];
    }
    stdout.writeln('Enter a number from 1 to ${services.length}.');
  }
}

List<VmServiceInfo> _selectVmServices(
  List<VmServiceInfo> services,
  String? selector,
) {
  if (selector == null) {
    return services;
  }
  return services
      .where((service) =>
          service.name == selector ||
          service.uri == selector ||
          service.exposedUri == selector)
      .toList();
}

Future<void> _executeAndWrite(
  _ShellSession session,
  String input, {
  required bool jsonOutput,
}) async {
  final result = await session.execute(input);
  _writeResponse(result, jsonOutput: jsonOutput);
}

Future<void> _executeScriptAndWrite(
  _ShellSession session,
  String script, {
  required bool jsonOutput,
}) async {
  for (final result in await session.executeScript(script)) {
    _writeResponse(result, jsonOutput: jsonOutput);
  }
}

void _writeResponse(
  Map<String, Object?> response, {
  required bool jsonOutput,
}) {
  if (jsonOutput) {
    stdout.writeln(jsonEncode(response));
    return;
  }
  final output = RohdShellOutput.pretty(response);
  if (!stdout.hasTerminal) {
    stdout.writeln(output.text);
    return;
  }
  final color = output.isError ? '\x1b[1;31m' : '\x1b[32m';
  stdout.writeln('$color${output.text}\x1b[0m');
}

abstract class _ShellSession {
  Future<Map<String, Object?>> execute(String input);

  Future<void> cancelActiveCommand() async {}

  Future<List<String>> completionCandidates(String input, int cursor) async =>
      const [];

  Future<List<Map<String, Object?>>> executeScript(String script) async {
    final responses = <Map<String, Object?>>[];
    for (final line in script.split(RegExp(r'\r?\n'))) {
      final input = line.trim();
      if (input.isEmpty || input.startsWith('#')) {
        continue;
      }
      responses.add(await execute(input));
    }
    return responses;
  }

  Future<void> dispose();
}

class _TypedShellSession extends _ShellSession {
  _TypedShellSession(
    this._dtd,
    this._connectTarget, {
    VmServiceRohdDesignTarget? initialTarget,
  }) : _initialTarget = initialTarget;

  final DartToolingDaemon _dtd;
  final Future<VmServiceRohdDesignTarget> Function() _connectTarget;
  VmServiceRohdDesignTarget? _initialTarget;
  final _sessionId = 'terminal-${DateTime.now().microsecondsSinceEpoch}';
  VmServiceRohdDesignTarget? _activeTarget;
  var _cancelRequested = false;
  var _disposed = false;

  @override
  Future<Map<String, Object?>> execute(String input) async {
    var response = await _withTarget(
      (target) => target.command(_sessionId, input),
    );
    response = await _applyDevToolsFormat(input, response);
    await _broadcastSentPaths(input, response);
    return response;
  }

  Future<Map<String, Object?>> _applyDevToolsFormat(
    String input,
    Map<String, Object?> response,
  ) async {
    if (response['ok'] != true || response['result'] is! Map) {
      return response;
    }
    final result = Map<Object?, Object?>.from(response['result']! as Map);
    if (result['value'] is! String) {
      return response;
    }
    if (result['path'] is! String || result['width'] is! int) {
      final metadata = await _valueMetadata(input);
      if (metadata != null) {
        result
          ..['path'] = metadata['path']
          ..['width'] = metadata['width'];
      }
    }
    final path = result['path'];
    if (path is! String) {
      return {...response, 'result': result};
    }
    try {
      final formatResponse = await _dtd.call(
        rohdSignalFormatDtdServiceName,
        rohdSignalFormatGetDtdMethod,
        params: {'path': path},
      );
      final format = formatResponse.result['format'];
      if (format is! String) {
        return response;
      }
      result['format'] = format;
      return {...response, 'result': result};
    } on Object {
      // DevTools is optional; retain local default formatting when absent.
      return {...response, 'result': result};
    }
  }

  Future<Map<Object?, Object?>?> _valueMetadata(String input) async {
    final match = RegExp(r'^\s*get-value\s+(\S+)').firstMatch(input);
    if (match == null) {
      return null;
    }
    try {
      final response = await _withTarget(
        (target) => target.command(_sessionId, 'name ${match.group(1)}'),
      );
      final result = response['result'];
      if (response['ok'] != true ||
          result is! Map ||
          result['path'] is! String ||
          result['width'] is! int) {
        return null;
      }
      return Map<Object?, Object?>.from(result);
    } on Object {
      return null;
    }
  }

  Future<void> _broadcastSentPaths(
    String input,
    Map<String, Object?> response,
  ) async {
    if (!RegExp(r'^send(?:\s|$)').hasMatch(input.trim()) ||
        response['ok'] != true) {
      return;
    }
    final result = response['result'];
    if (result is! Map || result['paths'] is! List) {
      return;
    }
    final paths = (result['paths'] as List).whereType<String>().toList();
    if (paths.isEmpty) {
      return;
    }
    try {
      await _dtd.call(
        rohdCrossProbeDtdServiceName,
        rohdCrossProbeSendDtdMethod,
        params: {'paths': jsonEncode(paths)},
      );
    } on Object {
      // The GUI host is optional; target-owned `send` remains successful.
    }
  }

  Future<Map<String, Object?>> _withTarget(
    Future<Map<String, Object?>> Function(VmServiceRohdDesignTarget target)
        operation,
  ) async {
    if (_disposed) {
      throw StateError('The shell session is closed.');
    }
    _cancelRequested = false;
    VmServiceRohdDesignTarget? target;
    try {
      target = _initialTarget;
      _initialTarget = null;
      target ??= await _connectTarget();
      _activeTarget = target;
      if (_cancelRequested || _disposed) {
        throw StateError('The shell command was cancelled.');
      }
      return await operation(target);
    } finally {
      if (identical(_activeTarget, target)) {
        _activeTarget = null;
      }
      await target?.vmService.dispose();
    }
  }

  @override
  Future<void> cancelActiveCommand() async {
    _cancelRequested = true;
    await _activeTarget?.vmService.dispose();
  }

  @override
  Future<List<String>> completionCandidates(String input, int cursor) async {
    final response = await _withTarget(
      (target) => target.complete(_sessionId, input, cursor),
    );
    final items = response['items'];
    if (response['ok'] != true || items is! List) {
      return const [];
    }
    return items.whereType<String>().toList();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await cancelActiveCommand();
    await _initialTarget?.vmService.dispose();
    _initialTarget = null;
    try {
      await _dtd.close().timeout(const Duration(milliseconds: 250));
    } on TimeoutException {
      // The shell must not wait indefinitely for a DTD close handshake.
    }
  }
}
