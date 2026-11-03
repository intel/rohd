// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_design_shell.dart
// Terminal-style DevTools client for target-owned ROHD commands.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_shell_output.dart';

/// Obtains the current paused-target command proxy.
typedef RohdDesignCommandTargetProvider = Future<RohdDesignCommandTarget?>
    Function();

/// Obtains optional shell script contents from a user-selected file.
typedef RohdShellScriptLoader = Future<String?> Function();

/// Broadcasts signal paths selected by a shell command.
typedef RohdShellSignalSender = void Function(List<String> signalPaths);

class _CompleteCommandIntent extends Intent {
  const _CompleteCommandIntent();
}

/// A persistent terminal-style client for target-owned ROHD commands.
class RohdDesignShell extends StatefulWidget {
  /// Creates a shell that resolves a command target as commands are submitted.
  const RohdDesignShell({
    required this.targetProvider,
    this.headerActions = const [],
    this.scriptLoader,
    this.onSendSignals,
    this.formatForPath,
    super.key,
  });

  /// Provides the current debug target without duplicating command semantics.
  final RohdDesignCommandTargetProvider targetProvider;

  /// Actions displayed at the end of the shell header.
  final List<Widget> headerActions;

  /// Optional script loader used instead of the platform file picker.
  final RohdShellScriptLoader? scriptLoader;

  /// Receives paths returned by a successful `send` shell command.
  final RohdShellSignalSender? onSendSignals;

  /// Resolves the selected display format for a signal path.
  final RohdSignalFormatResolver? formatForPath;

  @override
  State<RohdDesignShell> createState() => _RohdDesignShellState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<RohdDesignCommandTargetProvider>(
          'targetProvider',
          targetProvider,
        ),
      )
      ..add(IterableProperty<Widget>('headerActions', headerActions))
      ..add(
        ObjectFlagProperty<RohdShellScriptLoader>.has(
          'scriptLoader',
          scriptLoader,
        ),
      )
      ..add(
        ObjectFlagProperty<RohdShellSignalSender>.has(
          'onSendSignals',
          onSendSignals,
        ),
      )
      ..add(
        ObjectFlagProperty<RohdSignalFormatResolver>.has(
          'formatForPath',
          formatForPath,
        ),
      );
  }
}

class _RohdDesignShellState extends State<RohdDesignShell> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _inputScrollController = ScrollController();
  final _outputController = ScrollController();
  final _entries = <_ShellEntry>[];
  final _history = <String>[];
  final _sessionId = 'devtools-${DateTime.now().microsecondsSinceEpoch}';
  var _historyIndex = 0;
  var _running = false;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _inputScrollController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _inputController.text.trim();
    _inputController.clear();
    await _execute(input);
  }

  Future<void> _execute(String input) async {
    if (input.isEmpty || _running) {
      return;
    }
    setState(() {
      _entries.add(_ShellEntry(input, isInput: true));
      _history.add(input);
      _historyIndex = _history.length;
      _running = true;
    });
    _scrollToEnd();

    try {
      final target = await widget.targetProvider();
      if (target == null) {
        throw StateError('No ROHD debug target is connected.');
      }
      final response = await target.command(_sessionId, input);
      if (!mounted) {
        return;
      }
      final sentPaths = _sentPaths(input, response);
      if (sentPaths != null) {
        widget.onSendSignals?.call(sentPaths);
      }
      final output = RohdShellOutput.pretty(
        response,
        formatForPath: widget.formatForPath,
      );
      setState(
        () => _entries.add(
          _ShellEntry(
            output.text,
            isError: output.isError,
            isSuccess: !output.isError,
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _entries.add(_ShellEntry('$error', isError: true)));
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
        _focusPromptAfterBuild();
        _scrollToEnd();
      }
    }
  }

  static List<String>? _sentPaths(String input, Map<String, Object?> response) {
    if (!RegExp(r'^send(?:\s|$)').hasMatch(input.trim()) ||
        response['ok'] != true) {
      return null;
    }
    final result = response['result'];
    if (result is! Map || result['paths'] is! List) {
      return null;
    }
    return (result['paths'] as List).whereType<String>().toList();
  }

  Future<void> _loadScript() async {
    if (_running) {
      return;
    }
    try {
      final script = await (widget.scriptLoader ?? _pickScript)();
      if (script == null || !mounted) {
        return;
      }
      for (final line in script.split(RegExp(r'\r?\n'))) {
        final input = line.trim();
        if (input.isEmpty || input.startsWith('#')) {
          continue;
        }
        await _execute(input);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _entries.add(_ShellEntry('$error', isError: true)));
        _scrollToEnd();
      }
    }
  }

  static Future<String?> _pickScript() async {
    const typeGroup = XTypeGroup(
      label: 'ROHD shell scripts',
      extensions: ['rohd', 'rohdsh', 'txt'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    return await file?.readAsString();
  }

  Future<void> _complete() async {
    if (_running) {
      return;
    }
    final selection = _inputController.selection;
    final cursor =
        selection.isValid ? selection.baseOffset : _inputController.text.length;
    final target = await widget.targetProvider();
    if (target == null || !mounted) {
      return;
    }
    try {
      final response = await target.complete(
        _sessionId,
        _inputController.text,
        cursor,
      );
      final items = response['items'];
      if (response['ok'] != true || items is! List) {
        return;
      }
      final candidates = items.whereType<String>().toList();
      if (candidates.isEmpty) {
        return;
      }
      final start = _tokenStart(_inputController.text, cursor);
      final replacement = _sharedPrefix(candidates);
      final prefix = _inputController.text.substring(start, cursor);
      if (replacement.length > prefix.length) {
        final value = _inputController.text;
        _inputController.value = TextEditingValue(
          text:
              value.substring(0, start) + replacement + value.substring(cursor),
          selection: TextSelection.collapsed(
            offset: start + replacement.length,
          ),
        );
        _scrollInputToEnd();
      } else if (candidates.length > 1 && mounted) {
        setState(() => _entries.add(_ShellEntry(candidates.join('  '))));
        _scrollToEnd();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _entries.add(_ShellEntry('$error', isError: true)));
      }
    }
  }

  void _moveHistory(int delta) {
    if (_history.isEmpty) {
      return;
    }
    final index = (_historyIndex + delta).clamp(0, _history.length);
    setState(() {
      _historyIndex = index;
      _inputController.text = index == _history.length ? '' : _history[index];
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    });
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      unawaited(_complete());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHistory(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHistory(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputController.hasClients) {
        _outputController.jumpTo(_outputController.position.maxScrollExtent);
      }
    });
  }

  void _scrollInputToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputScrollController.hasClients) {
        _inputScrollController.jumpTo(
          _inputScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _focusPrompt() {
    if (!_running && !_inputFocus.hasFocus) {
      _inputFocus.requestFocus();
    }
  }

  void _focusPromptAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusPrompt();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => _focusPrompt(),
      onHover: (_) => _focusPrompt(),
      child: Material(
        color: colors.surface,
        child: Column(
          children: [
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: colors.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'ROHD Debug Shell',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file),
                    onPressed: _running ? null : _loadScript,
                    tooltip: 'Load shell script',
                  ),
                  ...widget.headerActions,
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _outputController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final outputColor = entry.isError
                      ? colors.error
                      : entry.isSuccess
                          ? colors.brightness == Brightness.dark
                              ? Colors.lightGreenAccent.shade400
                              : Colors.green.shade800
                          : null;
                  return SelectableText(
                    entry.isInput ? 'rohd> ${entry.value}' : entry.value,
                    style: TextStyle(
                      color: outputColor,
                      fontFamily: 'monospace',
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.tab):
                    _CompleteCommandIntent(),
              },
              child: Actions(
                actions: {
                  _CompleteCommandIntent:
                      CallbackAction<_CompleteCommandIntent>(
                    onInvoke: (_) {
                      unawaited(_complete());
                      return null;
                    },
                  ),
                },
                child: Focus(
                  onKeyEvent: _handleKey,
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    scrollController: _inputScrollController,
                    autofocus: true,
                    enabled: !_running,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      prefixText: 'rohd> ',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.tab),
                            onPressed: _running ? null : _complete,
                            tooltip: 'Complete command',
                          ),
                          IconButton(
                            icon: _running
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward),
                            onPressed: _running ? null : _submit,
                            tooltip: 'Run command',
                          ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
}

class _ShellEntry {
  const _ShellEntry(
    this.value, {
    this.isInput = false,
    this.isError = false,
    this.isSuccess = false,
  });

  final String value;
  final bool isInput;
  final bool isError;
  final bool isSuccess;
}
