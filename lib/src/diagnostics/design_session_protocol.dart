// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// design_session_protocol.dart
// Versioned, transport-neutral RPC protocol for ROHD design sessions.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/src/diagnostics/design_session.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

/// Versioned method names and response envelope fields for design sessions.
abstract final class RohdDesignSessionProtocol {
  /// The current protocol version.
  static const schemaVersion = 1;

  /// DTD service name reserved for this protocol.
  static const serviceName = 'rohdDesign';

  /// Target VM service extension that hosts this protocol.
  static const vmServiceExtensionName = 'ext.rohd.designSession';

  /// Returns session readiness and available capabilities.
  static const status = 'status';

  /// Resolves a cell occurrence from an absolute path.
  static const findCell = 'findCell';

  /// Resolves a signal occurrence from an absolute path.
  static const findSignal = 'findSignal';

  /// Resolves a port occurrence from an absolute path.
  static const findPort = 'findPort';

  /// Searches cell occurrences by regular expression.
  static const findCells = 'findCells';

  /// Searches signal occurrences by regular expression.
  static const findSignals = 'findSignals';

  /// Searches port occurrences by regular expression.
  static const findPorts = 'findPorts';

  /// Completes cell paths using the shared hierarchy search engine.
  static const completeCellPaths = 'completeCellPaths';

  /// Completes signal paths using the shared hierarchy search engine.
  static const completeSignalPaths = 'completeSignalPaths';

  /// Completes port paths using the shared hierarchy search engine.
  static const completePortPaths = 'completePortPaths';

  /// Traverses drivers from a signal occurrence handle.
  static const fanin = 'fanin';

  /// Traverses consumers from a signal occurrence handle.
  static const fanout = 'fanout';

  /// Gets a signal's waveform value at an optional simulation time.
  static const getSignalValue = 'getSignalValue';

  /// Expands an occurrence handle into its hierarchy name and metadata.
  static const name = 'name';

  /// Methods supported by the current protocol version.
  static const methods = <String>[
    status,
    findCell,
    findSignal,
    findPort,
    findCells,
    findSignals,
    findPorts,
    completeCellPaths,
    completeSignalPaths,
    completePortPaths,
    fanin,
    fanout,
    getSignalValue,
    name,
  ];
}

/// Converts [RohdDesignSession] calls to JSON-ready protocol envelopes.
///
/// Handles never cross the transport boundary as Dart objects. The protocol
/// serializes their [OccurrenceAddress] and resolves requests against the
/// [RohdDesignSession.hierarchy] owned by this session.
class RohdDesignSessionProtocolHandler {
  /// Creates a handler for [session].
  const RohdDesignSessionProtocolHandler(this.session);

  /// Session that owns the hierarchy occurrence handles.
  final RohdDesignSession session;

  /// Invokes [method] using JSON-ready [parameters].
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> parameters,
  ) async {
    try {
      final result = await _invoke(method, parameters);
      return {
        'schemaVersion': RohdDesignSessionProtocol.schemaVersion,
        'ok': true,
        'result': result,
      };
    } on FormatException catch (error) {
      return _error('invalidArgument', error.message);
      // Caller-provided protocol arguments become structured errors.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      return _error('invalidArgument', error.message?.toString() ?? '$error');
      // Invalid session state is a protocol precondition failure.
      // ignore: avoid_catching_errors
    } on StateError catch (error) {
      return _error('failedPrecondition', error.message);
    }
  }

  /// Invokes [method] without awaiting the target isolate's event loop.
  ///
  /// This is intended for debugger evaluation against an in-process session
  /// while its isolate is paused.
  Map<String, Object?> callSynchronously(
    String method,
    Map<String, Object?> parameters,
  ) {
    final synchronousSession = session;
    if (synchronousSession is! RohdSynchronousDesignSession) {
      throw StateError(
        'The design session does not support synchronous calls.',
      );
    }
    final now = synchronousSession as RohdSynchronousDesignSession;
    try {
      final result = switch (method) {
        RohdDesignSessionProtocol.status => _status(now.statusNow()),
        RohdDesignSessionProtocol.findCell => _cell(
            now.findCellNow(_string(parameters, 'path')),
          ),
        RohdDesignSessionProtocol.findSignal => _signal(
            now.findSignalNow(_string(parameters, 'path')),
          ),
        RohdDesignSessionProtocol.findPort => _signal(
            now.findPortNow(_string(parameters, 'path')),
          ),
        RohdDesignSessionProtocol.completeCellPaths => _paths(
            now.completeCellPathsNow(
              _string(parameters, 'prefix'),
              limit: _limit(parameters),
            ),
          ),
        RohdDesignSessionProtocol.completeSignalPaths => _paths(
            now.completeSignalPathsNow(
              _string(parameters, 'prefix'),
              limit: _limit(parameters),
            ),
          ),
        RohdDesignSessionProtocol.completePortPaths => _paths(
            now.completePortPathsNow(
              _string(parameters, 'prefix'),
              limit: _limit(parameters),
            ),
          ),
        RohdDesignSessionProtocol.findCells => _cells(
            now.findCellsNow(
              _string(parameters, 'pattern'),
              root: _cellHandle(parameters['root']),
              transparent: _bool(parameters, 'transparent'),
              options: _options(parameters),
            ),
          ),
        RohdDesignSessionProtocol.findSignals => _signals(
            now.findSignalsNow(
              _string(parameters, 'pattern'),
              root: _cellHandle(parameters['root']),
              transparent: _bool(parameters, 'transparent'),
              options: _options(parameters),
            ),
          ),
        RohdDesignSessionProtocol.findPorts => _signals(
            now.findPortsNow(
              _string(parameters, 'pattern'),
              root: _cellHandle(parameters['root']),
              transparent: _bool(parameters, 'transparent'),
              options: _options(parameters),
            ),
          ),
        RohdDesignSessionProtocol.fanin => _signals(
            now.faninNow(
              _signalHandle(parameters['signal']),
              transparent: _bool(parameters, 'transparent'),
              options: _options(parameters),
            ),
          ),
        RohdDesignSessionProtocol.fanout => _signals(
            now.fanoutNow(
              _signalHandle(parameters['signal']),
              transparent: _bool(parameters, 'transparent'),
              options: _options(parameters),
            ),
          ),
        RohdDesignSessionProtocol.getSignalValue => _value(
            now.getSignalValueNow(
              _signalHandle(parameters['signal']),
              time: _time(parameters),
            ),
          ),
        RohdDesignSessionProtocol.name => _name(parameters['occurrence']),
        _ => throw FormatException('Unknown design session method: $method'),
      };
      return {
        'schemaVersion': RohdDesignSessionProtocol.schemaVersion,
        'ok': true,
        'result': result,
      };
    } on FormatException catch (error) {
      return _error('invalidArgument', error.message);
      // Caller-provided protocol arguments become structured errors.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      return _error('invalidArgument', error.message?.toString() ?? '$error');
      // Invalid session state is a protocol precondition failure.
      // ignore: avoid_catching_errors
    } on StateError catch (error) {
      return _error('failedPrecondition', error.message);
    }
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> parameters,
  ) async {
    switch (method) {
      case RohdDesignSessionProtocol.status:
        return _status(await session.status());
      case RohdDesignSessionProtocol.findCell:
        return _cell(await session.findCell(_string(parameters, 'path')));
      case RohdDesignSessionProtocol.findSignal:
        return _signal(await session.findSignal(_string(parameters, 'path')));
      case RohdDesignSessionProtocol.findPort:
        return _signal(await session.findPort(_string(parameters, 'path')));
      case RohdDesignSessionProtocol.completeCellPaths:
        return _paths(
          await session.completeCellPaths(
            _string(parameters, 'prefix'),
            limit: _limit(parameters),
          ),
        );
      case RohdDesignSessionProtocol.completeSignalPaths:
        return _paths(
          await session.completeSignalPaths(
            _string(parameters, 'prefix'),
            limit: _limit(parameters),
          ),
        );
      case RohdDesignSessionProtocol.completePortPaths:
        return _paths(
          await session.completePortPaths(
            _string(parameters, 'prefix'),
            limit: _limit(parameters),
          ),
        );
      case RohdDesignSessionProtocol.findCells:
        return _cells(
          await session.findCells(
            _string(parameters, 'pattern'),
            root: _cellHandle(parameters['root']),
            transparent: _bool(parameters, 'transparent'),
            options: _options(parameters),
          ),
        );
      case RohdDesignSessionProtocol.findSignals:
        return _signals(
          await session.findSignals(
            _string(parameters, 'pattern'),
            root: _cellHandle(parameters['root']),
            transparent: _bool(parameters, 'transparent'),
            options: _options(parameters),
          ),
        );
      case RohdDesignSessionProtocol.findPorts:
        return _signals(
          await session.findPorts(
            _string(parameters, 'pattern'),
            root: _cellHandle(parameters['root']),
            transparent: _bool(parameters, 'transparent'),
            options: _options(parameters),
          ),
        );
      case RohdDesignSessionProtocol.fanin:
        return _signals(
          await session.fanin(
            _signalHandle(parameters['signal']),
            transparent: _bool(parameters, 'transparent'),
            options: _options(parameters),
          ),
        );
      case RohdDesignSessionProtocol.fanout:
        return _signals(
          await session.fanout(
            _signalHandle(parameters['signal']),
            transparent: _bool(parameters, 'transparent'),
            options: _options(parameters),
          ),
        );
      case RohdDesignSessionProtocol.getSignalValue:
        return _value(
          await session.getSignalValue(
            _signalHandle(parameters['signal']),
            time: _time(parameters),
          ),
        );
      case RohdDesignSessionProtocol.name:
        return _name(parameters['occurrence']);
      default:
        throw FormatException('Unknown design session method: $method');
    }
  }

  Map<String, Object?> _error(String code, String message) => {
        'schemaVersion': RohdDesignSessionProtocol.schemaVersion,
        'ok': false,
        'error': {'code': code, 'message': message},
      };

  Map<String, Object?> _status(RohdDesignStatus status) => {
        'epoch': status.epoch.value,
        'ready': status.isReady,
        if (status.designName != null) 'designName': status.designName,
        'capabilities': status.capabilities.map((value) => value.name).toList()
          ..sort(),
      };

  Map<String, Object?>? _cell(HierarchyOccurrence? value) =>
      value == null ? null : _cellHandleDto(value);

  Map<String, Object?>? _signal(SignalOccurrence? value) =>
      value == null ? null : _signalHandleDto(value);

  Map<String, Object?> _cells(RohdPage<HierarchyOccurrence> page) => {
        'items': page.items.map(_cellHandleDto).toList(),
        if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
      };

  Map<String, Object?> _signals(RohdPage<SignalOccurrence> page) => {
        'items': page.items.map(_signalHandleDto).toList(),
        if (page.nextPageToken != null) 'nextPageToken': page.nextPageToken,
      };

  Map<String, Object?> _paths(List<String> paths) => {'items': paths};

  Map<String, Object?> _value(RohdSignalValue value) => {
        ..._signalHandleDto(value.signal),
        'path': value.signal.path(),
        'width': value.signal.width,
        'time': value.time,
        'value': value.value,
        if (value.sampleTime != null) 'sampleTime': value.sampleTime,
      };

  Map<String, Object?> _cellHandleDto(HierarchyOccurrence value) {
    final address = value.address;
    if (address == null) {
      throw StateError('Cell occurrence has no address.');
    }
    return {'address': address.toDotString(), 'kind': 'cell'};
  }

  Map<String, Object?> _signalHandleDto(SignalOccurrence value) {
    final address = value.address;
    if (address == null) {
      throw StateError('Signal occurrence has no address.');
    }
    return {
      'address': address.toDotString(),
      'kind': value.isPort ? 'port' : 'signal',
    };
  }

  Map<String, Object?> _name(Object? value) {
    final address = _address(value, 'occurrence');
    final kind = _occurrenceKind(value, 'occurrence');
    if (kind == 'cell') {
      final cell = session.hierarchy.occurrenceByAddress(address);
      if (cell == null) {
        throw const FormatException('Unknown cell occurrence address.');
      }
      return {
        ..._cellHandleDto(cell),
        'path': cell.path(),
        'name': cell.name,
        if (cell.definition != null) 'definition': cell.definition,
        'primitive': cell.isPrimitive,
      };
    }
    final signal = session.hierarchy.signalByAddress(address);
    if (signal == null) {
      throw const FormatException('Unknown signal occurrence address.');
    }
    if ((kind == 'port') != signal.isPort) {
      throw const FormatException(
        'Occurrence handle kind does not match address.',
      );
    }
    return {
      ..._signalHandleDto(signal),
      'path': signal.path(),
      'name': signal.name,
      'width': signal.width,
      if (signal.direction != null) 'direction': signal.direction,
    };
  }

  HierarchyOccurrence? _cellHandle(Object? value) {
    if (value == null) {
      return null;
    }
    final address = _address(value, 'root');
    final occurrence = session.hierarchy.occurrenceByAddress(address);
    if (occurrence == null) {
      throw const FormatException('Unknown cell occurrence address.');
    }
    return occurrence;
  }

  SignalOccurrence _signalHandle(Object? value) {
    final address = _address(value, 'signal');
    final signal = session.hierarchy.signalByAddress(address);
    if (signal == null) {
      throw const FormatException('Unknown signal occurrence address.');
    }
    return signal;
  }

  static OccurrenceAddress _address(Object? value, String parameter) {
    if (value is! Map) {
      throw FormatException('$parameter must be an occurrence handle.');
    }
    final address = value['address'];
    if (address is! String) {
      throw FormatException('$parameter handle requires an address.');
    }
    try {
      return OccurrenceAddress.fromDotString(address);
    } on FormatException {
      throw FormatException('$parameter handle has an invalid address.');
    }
  }

  static String _occurrenceKind(Object? value, String parameter) {
    if (value is! Map || value['kind'] is! String) {
      throw FormatException('$parameter handle requires a kind.');
    }
    final kind = value['kind'] as String;
    if (kind != 'cell' && kind != 'signal' && kind != 'port') {
      throw FormatException('$parameter handle has an invalid kind.');
    }
    return kind;
  }

  static RohdQueryOptions _options(Map<String, Object?> parameters) {
    final pageSize = parameters['pageSize'] ?? 100;
    final pageToken = parameters['pageToken'];
    if (pageSize is! int) {
      throw const FormatException('pageSize must be an integer.');
    }
    if (pageToken != null && pageToken is! String) {
      throw const FormatException('pageToken must be a string.');
    }
    return RohdQueryOptions(
      pageSize: pageSize,
      pageToken: pageToken as String?,
    );
  }

  static int _limit(Map<String, Object?> parameters) {
    final limit = parameters['limit'] ?? 20;
    if (limit is! int || limit < 1 || limit > 100) {
      throw const FormatException('limit must be an integer from 1 to 100.');
    }
    return limit;
  }

  static String _string(Map<String, Object?> parameters, String name) {
    final value = parameters[name];
    if (value is! String || value.isEmpty) {
      throw FormatException('$name must be a non-empty string.');
    }
    return value;
  }

  static bool _bool(Map<String, Object?> parameters, String name) {
    final value = parameters[name] ?? false;
    if (value is! bool) {
      throw FormatException('$name must be a bool.');
    }
    return value;
  }

  static int? _time(Map<String, Object?> parameters) {
    final value = parameters['time'];
    if (value == null) {
      return null;
    }
    if (value is! int || value < 0) {
      throw const FormatException('time must be a non-negative integer.');
    }
    return value;
  }
}
