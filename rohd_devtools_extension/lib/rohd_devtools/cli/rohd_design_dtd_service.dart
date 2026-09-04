// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_design_dtd_service.dart
// DTD bridge for the typed ROHD design-session protocol.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';

import 'package:dtd/dtd.dart';
import 'package:rohd/design_session_protocol.dart';
import 'package:rohd/rohd.dart' show RohdShellService;
import 'package:vm_service/vm_service.dart';

/// Sends a typed design-session protocol request to a debug target.
typedef RohdDesignTarget = Future<Map<String, Object?>> Function(
  String method,
  Map<String, Object?> parameters,
);

/// Target-backed command operations used by terminal and GUI clients.
abstract interface class RohdDesignCommandTarget {
  /// Executes a canonical target-owned command for [sessionId].
  Future<Map<String, Object?>> command(String sessionId, String input);

  /// Returns target-owned completion candidates.
  Future<Map<String, Object?>> complete(
    String sessionId,
    String input,
    int cursor,
  );
}

const _targetRequestTimeout = Duration(seconds: 10);

/// DTD client service that forwards external shell selections to DevTools.
const rohdCrossProbeDtdServiceName = 'rohdCrossProbe';

/// Method on [rohdCrossProbeDtdServiceName] that broadcasts signal paths.
const rohdCrossProbeSendDtdMethod = 'send';

/// DTD client service that exposes DevTools-selected signal display formats.
const rohdSignalFormatDtdServiceName = 'rohdSignalFormat';

/// Method on [rohdSignalFormatDtdServiceName] that resolves one signal path.
const rohdSignalFormatGetDtdMethod = 'get';

/// [RohdDesignCommandTarget] implementation for an in-process ROHD design.
///
/// Demo mode runs the design and DevTools in one isolate, so command execution
/// can use the same target-owned shell service without a DTD or VM connection.
class InProcessRohdDesignTarget implements RohdDesignCommandTarget {
  /// Creates a target backed directly by the in-process ROHD shell service.
  const InProcessRohdDesignTarget();

  @override
  Future<Map<String, Object?>> command(String sessionId, String input) async =>
      _decode(RohdShellService.executeDesignCommandNow(sessionId, input));

  @override
  Future<Map<String, Object?>> complete(
    String sessionId,
    String input,
    int cursor,
  ) async =>
      _decode(
        RohdShellService.completeDesignCommandNow(sessionId, input, cursor),
      );

  static Map<String, Object?> _decode(String response) =>
      Map<String, Object?>.from(jsonDecode(response) as Map);
}

/// [RohdDesignCommandTarget] implementation backed by a target VM service.
class VmServiceRohdDesignTarget implements RohdDesignCommandTarget {
  /// Creates a target proxy for [vmService] and its [isolateId].
  const VmServiceRohdDesignTarget(this.vmService, this.isolateId);

  /// Target VM service connection.
  final VmService vmService;

  /// Isolate that registered the typed design-session extension.
  final String isolateId;

  /// Ensures the target has loaded the typed design-session implementation.
  Future<void> register() async {
    await _diagnosticsLibraryId();
  }

  Future<String> _diagnosticsLibraryId() async {
    final isolate =
        await vmService.getIsolate(isolateId).timeout(_targetRequestTimeout);
    final library = (isolate.libraries ?? const <LibraryRef>[]).where(
      (candidate) =>
          candidate.uri ==
          'package:rohd/src/diagnostics/inspector_service.dart',
    );
    if (library.isEmpty || library.first.id == null) {
      throw StateError('ROHD diagnostics library is not loaded in the target.');
    }
    return library.first.id!;
  }

  /// Forwards a typed request through debugger evaluation.
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> parameters,
  ) =>
      _evaluateJson('RohdShellService.executeDesignSessionNow('
          '${_dartStringLiteral(method)}, '
          '${_dartStringLiteral(jsonEncode(parameters))})');

  @override
  Future<Map<String, Object?>> command(String sessionId, String input) =>
      _evaluateJson('RohdShellService.executeDesignCommandNow('
          '${_dartStringLiteral(sessionId)}, ${_dartStringLiteral(input)})');

  @override
  Future<Map<String, Object?>> complete(
    String sessionId,
    String input,
    int cursor,
  ) =>
      _evaluateJson('RohdShellService.completeDesignCommandNow('
          '${_dartStringLiteral(sessionId)}, ${_dartStringLiteral(input)}, '
          '$cursor)');

  Future<Map<String, Object?>> _evaluateJson(String expression) async {
    final libraryId = await _diagnosticsLibraryId();
    final response = await vmService
        .evaluate(isolateId, libraryId, expression)
        .timeout(_targetRequestTimeout);
    if (response is! InstanceRef) {
      throw StateError('Target design-session evaluation returned no string.');
    }
    var json = response.valueAsString;
    if (json == null || (response.valueAsStringIsTruncated ?? false)) {
      final responseId = response.id;
      if (responseId != null) {
        final fullResponse = await vmService
            .getObject(isolateId, responseId)
            .timeout(_targetRequestTimeout);
        if (fullResponse is Instance) {
          json = fullResponse.valueAsString;
        }
      }
    }
    if (json == null) {
      throw StateError('Target design-session evaluation returned no JSON.');
    }
    return Map<String, Object?>.from(jsonDecode(json) as Map);
  }
}

/// Encodes [value] as a Dart string literal for debugger evaluation.
String _dartStringLiteral(String value) =>
    jsonEncode(value).replaceAll(r'$', r'\$');

/// DTD service that forwards typed ROHD design-session calls to a target.
///
/// The DTD boundary uses JSON-ready maps. The target resolves occurrence
/// address DTOs into canonical hierarchy handles.
class RohdDesignDtdService {
  /// Creates a DTD bridge that forwards requests to [target].
  RohdDesignDtdService(this.target);

  /// Target endpoint to which protocol calls are forwarded.
  RohdDesignTarget target;
  Future<void>? _registration;

  /// Registers the protocol's single DTD forwarding method.
  Future<void> register(DartToolingDaemon dtd) async {
    if (dtd.isClosed) {
      throw StateError('Cannot register a design service on a closed DTD.');
    }
    final services = await dtd.getRegisteredServices();
    final isRegistered = services.clientServices.any(
      (service) =>
          service.name == RohdDesignSessionProtocol.serviceName &&
          service.methods.containsKey('call'),
    );
    if (isRegistered) {
      return;
    }
    final inProgress = _registration;
    if (inProgress != null) {
      await inProgress;
      return;
    }

    final registration = dtd.registerService(
      RohdDesignSessionProtocol.serviceName,
      'call',
      (parameters) async => {
        'type': 'RohdDesignSessionResponse',
        ...await execute(
          parameters['method'].asString,
          parameters['parameters'].asString,
        ),
      },
      capabilities: const {
        'rohdDesignSession': RohdDesignSessionProtocol.schemaVersion,
        'commands': ['call'],
        'methods': RohdDesignSessionProtocol.methods,
      },
    );
    _registration = registration;
    try {
      await registration;
    } finally {
      if (identical(_registration, registration)) {
        _registration = null;
      }
    }
  }

  /// Forwards a serialized parameter map to [target].
  ///
  /// This method makes the bridge testable without a running DTD daemon.
  Future<Map<String, Object?>> execute(
    String method,
    String encodedParameters,
  ) async {
    try {
      final decoded = jsonDecode(encodedParameters);
      if (decoded is! Map) {
        throw const FormatException('parameters must be a JSON object.');
      }
      return await target(method, Map<String, Object?>.from(decoded));
    } on FormatException catch (error) {
      return _error('invalidArgument', error.message);
    } on Object catch (error) {
      return _error('internal', error.toString());
    }
  }

  Map<String, Object?> _error(String code, String message) => {
        'schemaVersion': RohdDesignSessionProtocol.schemaVersion,
        'ok': false,
        'error': {'code': code, 'message': message},
      };
}

/// DTD client for the typed design-session protocol.
///
/// Responses remain DTOs at this boundary. A client resolves returned
/// occurrence addresses against its own hierarchy before using them as handles.
class RohdDesignDtdClient {
  /// Creates a client over an established [dtd] connection.
  const RohdDesignDtdClient(this.dtd);

  /// DTD connection that hosts [RohdDesignSessionProtocol.serviceName].
  final DartToolingDaemon dtd;

  /// Invokes a typed design-session [method].
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> parameters,
  ) async {
    final response = await dtd.call(
      RohdDesignSessionProtocol.serviceName,
      'call',
      params: {
        'method': method,
        'parameters': jsonEncode(parameters),
      },
    );
    final result = Map<String, Object?>.from(response.result)..remove('type');
    return result;
  }
}
