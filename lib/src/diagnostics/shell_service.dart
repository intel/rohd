// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// shell_service.dart
// Target-owned typed ROHD design-session VM service extension.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:rohd/src/diagnostics/design_command_shell.dart';
import 'package:rohd/src/diagnostics/design_session_protocol.dart';
import 'package:rohd/src/diagnostics/in_process_design_session.dart';
import 'package:rohd/src/diagnostics/module_services.dart';
import 'package:rohd/src/synthesizers/netlist/netlist_service.dart';

/// Hosts the typed ROHD design-session protocol in the debugged isolate.
///
/// The DTD shell, GUI, and other clients use this extension to operate on
/// occurrence handles owned by the target's live [NetlistService].
class RohdShellService {
  RohdShellService._();

  /// VM service extension for the typed design-session protocol.
  static const designSessionExtensionName =
      RohdDesignSessionProtocol.vmServiceExtensionName;

  static var _registered = false;
  static final _commandSessions = <String, RohdDesignCommandShell>{};

  /// Registers the typed design-session VM service extension once.
  static void register() {
    if (_registered) {
      return;
    }
    _registered = true;
    developer.registerExtension(
      designSessionExtensionName,
      _executeDesignSession,
    );
  }

  static Future<developer.ServiceExtensionResponse> _executeDesignSession(
    String _,
    Map<String, String> parameters,
  ) async =>
      developer.ServiceExtensionResponse.result(
        executeDesignSessionNow(
          parameters['method'] ?? '',
          parameters['parameters'] ?? '{}',
        ),
      );

  /// Invokes the typed design-session protocol in the debugged isolate.
  ///
  /// [parameters] is a JSON object because VM service extension arguments are
  /// strings. Occurrence references inside it are address-based DTOs and are
  /// resolved to handles owned by the shared [NetlistService] hierarchy.
  static Future<String> executeDesignSession(
    String method,
    String parameters,
  ) async =>
      executeDesignSessionNow(method, parameters);

  /// Invokes the typed protocol without awaiting the target event loop.
  ///
  /// VM debugger evaluation uses this entrypoint while an isolate is paused.
  static String executeDesignSessionNow(String method, String parameters) {
    try {
      final decoded = jsonDecode(parameters);
      if (decoded is! Map) {
        throw const FormatException('parameters must be a JSON object.');
      }
      final handler = RohdDesignSessionProtocolHandler(
        InProcessRohdDesignSession(_netlist()),
      );
      return jsonEncode(
        handler.callSynchronously(method, Map<String, Object?>.from(decoded)),
      );
    } on FormatException catch (error) {
      return _protocolError('invalidArgument', error.message);
      // ignore: avoid_catching_errors
    } on StateError catch (error) {
      return _protocolError('failedPrecondition', error.message);
    } on Object catch (error) {
      return _protocolError('internal', error.toString());
    }
  }

  /// Executes one canonical ROHD command for a frontend [sessionId].
  static String executeDesignCommandNow(String sessionId, String input) {
    try {
      final shell = _commandSessions.putIfAbsent(
        _sessionId(sessionId),
        () => RohdDesignCommandShell(_handler()),
      );
      return jsonEncode(shell.execute(input));
    } on FormatException catch (error) {
      return _protocolError('invalidArgument', error.message);
      // ignore: avoid_catching_errors
    } on StateError catch (error) {
      return _protocolError('failedPrecondition', error.message);
    } on Object catch (error) {
      return _protocolError('internal', error.toString());
    }
  }

  /// Returns canonical completion candidates for a frontend [sessionId].
  static String completeDesignCommandNow(
    String sessionId,
    String input,
    int cursor,
  ) {
    try {
      final shell = _commandSessions.putIfAbsent(
        _sessionId(sessionId),
        () => RohdDesignCommandShell(_handler()),
      );
      return jsonEncode({'ok': true, 'items': shell.complete(input, cursor)});
    } on FormatException catch (error) {
      return _protocolError('invalidArgument', error.message);
      // ignore: avoid_catching_errors
    } on StateError catch (error) {
      return _protocolError('failedPrecondition', error.message);
    } on Object catch (error) {
      return _protocolError('internal', error.toString());
    }
  }

  static RohdDesignSessionProtocolHandler _handler() =>
      RohdDesignSessionProtocolHandler(InProcessRohdDesignSession(_netlist()));

  static String _sessionId(String value) {
    if (value.isEmpty || value.length > 200) {
      throw const FormatException('sessionId must be a non-empty string.');
    }
    return value;
  }

  static String _protocolError(String code, String message) => jsonEncode({
        'schemaVersion': RohdDesignSessionProtocol.schemaVersion,
        'ok': false,
        'error': {'code': code, 'message': message},
      });

  static NetlistService _netlist() {
    final netlist = ModuleServices.instance.lookup<NetlistService>() ??
        NetlistService.current;
    if (netlist == null) {
      throw StateError('No synthesized netlist is available.');
    }
    return netlist;
  }
}
