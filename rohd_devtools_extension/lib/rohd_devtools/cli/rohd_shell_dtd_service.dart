// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_shell_dtd_service.dart
// DTD bridge for the DevTools-owned ROHD design shell.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:dtd/dtd.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/design_query_language.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/waveform_cli.dart';

import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// DTD service hosted by DevTools for executing design shell commands.
///
/// DevTools supplies diagnostics-loaded netlist data through [configure]. The
/// service keeps aliases and their live occurrence handles in the interpreter
/// until the design changes, at which point the design epoch advances and the
/// interpreter is replaced.
class RohdShellDtdService {
  /// The DTD service name advertised by DevTools.
  static const serviceName = 'rohdDevtoolsShell';

  /// Creates a shell DTD service without a loaded design.
  RohdShellDtdService({CrossProbeService? crossProbeService})
      : _crossProbeService = crossProbeService;

  Future<void>? _registration;
  final CrossProbeService? _crossProbeService;
  DesignQueryLanguage? _interpreter;
  String? _designName;
  var _designEpoch = 0;

  /// Configures the current DevTools design from diagnostics netlist JSON.
  void configure(Map<String, dynamic> netlist, {String? designName}) {
    final connectivity = SchematicTraversalCli.fromNetlist(netlist);
    _interpreter = DesignQueryLanguage(connectivity: connectivity);
    _designName = designName;
    _designEpoch++;
  }

  /// Clears live design state and invalidates all shell aliases.
  void clearDesign() {
    _interpreter = null;
    _designName = null;
    _designEpoch++;
  }

  /// Registers the shell service on [dtd].
  ///
  /// Re-registering against the same connection is a no-op. A failed
  /// registration is not retained, so a later hot reload can retry. DTD
  /// unregisters service methods automatically when its client connection
  /// closes.
  Future<void> register(DartToolingDaemon dtd) async {
    if (dtd.isClosed) {
      throw StateError('Cannot register a shell service on a closed DTD.');
    }
    final services = await dtd.getRegisteredServices();
    final hasExecuteMethod = services.clientServices.any(
      (service) =>
          service.name == serviceName && service.methods.containsKey('execute'),
    );
    if (hasExecuteMethod) {
      return;
    }
    final inProgress = _registration;
    if (inProgress != null) {
      await inProgress;
      return;
    }

    const capabilities = <String, Object?>{
      'rohdDevtoolsShell': 1,
      'commands': ['execute']
    };
    final registration = dtd.registerService(
        serviceName,
        'execute',
        (parameters) async => {
              'type': 'RohdShellResponse',
              ...execute(parameters['input'].asString)
            },
        capabilities: capabilities);
    _registration = registration;
    try {
      await registration;
    } finally {
      if (identical(_registration, registration)) {
        _registration = null;
      }
    }
  }

  /// Returns JSON-ready status for DTD clients and embedded shell UI.
  Map<String, Object?> status() => {
        'schemaVersion': 1,
        'ready': _interpreter != null,
        'designName': _designName,
        'designEpoch': _designEpoch,
        'capabilities': {
          'schematic': _interpreter != null,
          'hierarchy': false,
          'waveform': false,
          'sendSignals': _crossProbeService?.isActive.value ?? false
        },
        'commands': const [
          'select signal',
          'let',
          'fanin',
          'fanout',
          'fanin transparent',
          'fanout transparent',
          'send'
        ]
      };

  /// Lists commands supported by the current shell protocol.
  Map<String, Object?> commands() =>
      {'schemaVersion': 1, 'commands': status()['commands']};

  /// Executes one shell input line against the current design session.
  Map<String, Object?> execute(String input) {
    switch (input.trim()) {
      case 'status':
        return {'ok': true, ...status()};
      case 'commands':
        return {'ok': true, ...commands()};
    }
    final interpreter = _interpreter;
    if (interpreter == null) {
      return {
        'ok': false,
        'error': 'No schematic design is loaded in DevTools.',
        ...status()
      };
    }
    try {
      if (input.trimLeft().startsWith('send ')) {
        return _sendSignals(interpreter, input);
      }
      return {
        'ok': true,
        'designEpoch': _designEpoch,
        'result': interpreter.evaluate(input).toJson()
      };
    } on FormatException catch (error) {
      return {'ok': false, 'designEpoch': _designEpoch, 'error': error.message};
    }
  }

  Map<String, Object?> _sendSignals(
      DesignQueryLanguage interpreter, String input) {
    final crossProbeService = _crossProbeService;
    if (crossProbeService == null || !crossProbeService.isActive.value) {
      return {
        'ok': false,
        'designEpoch': _designEpoch,
        'error': 'Signal send is unavailable in this shell session.',
        ...status()
      };
    }
    final references = input
        .trim()
        .substring('send'.length)
        .split(' ')
        .where((reference) => reference.isNotEmpty)
        .toList();
    if (references.isEmpty) {
      throw const FormatException('Usage: send <signal-path-or-alias>...');
    }
    final paths = references
        .map(interpreter.resolveSignalHandle)
        .map((signal) => signal.path())
        .toSet()
        .toList()
      ..sort();
    crossProbeService.send(paths, source: 'rohd-shell');
    return {'ok': true, 'designEpoch': _designEpoch, 'sentSignals': paths};
  }
}
