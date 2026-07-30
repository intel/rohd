// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// vm_service_signal_value_source.dart
// VM-backed adapter for the shared signal value source interface.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';
import 'dart:convert';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';
import 'package:vm_service/vm_service.dart' as vm;

/// VM-backed [SignalValueSource] that refreshes on debugger pause events.
class VmServiceSignalValueSource implements SignalValueSource {
  static const _moduleTreeHierarchyExpression =
      'ModuleTree.instance.hierarchyJSON';

  static const _currentTimeExpressions = <String>[
    'WaveformService.instance.currentTime',
  ];

  static const _currentTimeExtension = 'ext.rohd.currentTime';
  static const _snapshotExtension = 'ext.rohd.snapshotCompact';

  /// Eval wrapper for ROHD-side expressions.
  final EvalOnDartLibrary rohdControllerEval;

  /// Disposable token that keeps the eval alive.
  final Disposable evalDisposable;

  /// VM service used for debug-event subscriptions.
  final vm.VmService vmService;

  final StreamController<SignalValueUpdateEvent> _updatesController =
      StreamController<SignalValueUpdateEvent>.broadcast();

  StreamSubscription<vm.Event>? _debugEventSubscription;
  int _lastKnownTime = 0;
  int _syntheticUpdateTime = 0;

  /// Creates a VM-backed signal value source.
  VmServiceSignalValueSource({
    required this.rohdControllerEval,
    required this.evalDisposable,
    required this.vmService,
  }) {
    _debugEventSubscription = vmService.onDebugEvent.listen(
      _handleDebugEvent,
      onError: (Object e) {
        debugPrint('[VmSignalValueSource] Debug stream error: $e');
      },
    );
  }

  @override
  Stream<SignalValueUpdateEvent> get updates => _updatesController.stream;

  @override
  Future<int?> getCurrentTime() async {
    final extensionTime = await _readCurrentTimeFromExtension();
    if (extensionTime != null && extensionTime > 0) {
      _rememberTime(extensionTime);
      return extensionTime;
    }

    for (final expression in _currentTimeExpressions) {
      try {
        final value = await rohdControllerEval.evalInstance(
          expression,
          isAlive: evalDisposable,
        );
        final raw = value.valueAsString;
        if (raw == null || raw.isEmpty) {
          continue;
        }

        final parsedInt = int.tryParse(raw);
        if (parsedInt != null) {
          _rememberTime(parsedInt);
          return parsedInt;
        }

        final decoded = jsonDecode(raw);
        if (decoded is int) {
          _rememberTime(decoded);
          return decoded;
        }
        if (decoded is Map<String, dynamic> && decoded['currentTime'] is int) {
          final currentTime = decoded['currentTime'] as int;
          _rememberTime(currentTime);
          return currentTime;
        }
      } on Exception catch (e) {
        debugPrint(
          '[VmSignalValueSource] Current time eval failed '
          'for "$expression": $e',
        );
      }
    }

    return null;
  }

  @override
  Future<SignalSnapshotData?> getSnapshot(int time) async {
    final extensionSnapshot = await _readSnapshotFromExtension(time);
    if (extensionSnapshot != null) {
      return extensionSnapshot;
    }

    final snapshotExpressions = <String>[
      _moduleTreeHierarchyExpression,
      _moduleTreeSignalValuesExpression,
      _waveformSnapshotExpression(time),
    ];

    for (final expression in snapshotExpressions) {
      try {
        final value = await rohdControllerEval.evalInstance(
          expression,
          isAlive: evalDisposable,
        );
        final payload = value.valueAsString;
        if (payload == null || payload.isEmpty) {
          continue;
        }

        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        if (decoded['status'] == 'fail' || decoded['status'] == 'unavailable') {
          debugPrint(
            '[VmSignalValueSource] Snapshot unavailable: '
            '${decoded['message'] ?? decoded['reason'] ?? decoded['error']}',
          );
          continue;
        }

        if (expression == _moduleTreeHierarchyExpression) {
          final hierarchySignals = _decodeHierarchySnapshot(decoded);
          if (hierarchySignals != null) {
            return hierarchySignals;
          }
          continue;
        }

        final rawSignals = decoded['signals'] is Map<String, dynamic>
            ? decoded['signals'] as Map<String, dynamic>
            : decoded;

        final signals = <String, Map<String, dynamic>>{};
        for (final entry in rawSignals.entries) {
          final data = entry.value;
          if (data is Map<String, dynamic>) {
            signals[entry.key] = data;
          }
        }

        if (signals.isNotEmpty) {
          return signals;
        }
      } on Exception catch (e) {
        debugPrint(
          '[VmSignalValueSource] Snapshot eval failed '
          'for "$expression": $e',
        );
      }
    }

    return null;
  }

  /// Dispose stream subscriptions owned by this source.
  Future<void> dispose() async {
    await _debugEventSubscription?.cancel();
    _debugEventSubscription = null;
    await _updatesController.close();
  }

  static String _waveformSnapshotExpression(int time) =>
      'WaveformService.instance.getSnapshotCompactJSON($time)';

  static const _moduleTreeSignalValuesExpression =
      'ModuleTree.instance.signalValuesJSON';

  Future<int?> _readCurrentTimeFromExtension() async {
    final response = await _callExtension(_currentTimeExtension);
    if (response == null) {
      return null;
    }

    final currentTime = response['currentTime'];
    if (currentTime is int) {
      return currentTime;
    }
    return null;
  }

  Future<SignalSnapshotData?> _readSnapshotFromExtension(int time) async {
    final response = await _callExtension(
      _snapshotExtension,
      args: {'time': time.toString()},
    );
    if (response == null) {
      return null;
    }

    return _decodeSnapshotPayload(response);
  }

  Future<Map<String, dynamic>?> _callExtension(
    String method, {
    Map<String, String>? args,
  }) async {
    try {
      final response = await vmService.callServiceExtension(method, args: args);
      return response.json;
    } on Exception {
      return null;
    }
  }

  SignalSnapshotData? _decodeSnapshotPayload(Map<String, dynamic> decoded) {
    if (decoded['status'] == 'fail' || decoded['status'] == 'unavailable') {
      debugPrint(
        '[VmSignalValueSource] Snapshot unavailable: '
        '${decoded['message'] ?? decoded['reason'] ?? decoded['error']}',
      );
      return null;
    }

    final rawSignals = decoded['signals'] is Map<String, dynamic>
        ? decoded['signals'] as Map<String, dynamic>
        : decoded;

    final signals = <String, Map<String, dynamic>>{};
    for (final entry in rawSignals.entries) {
      final data = entry.value;
      if (data is Map<String, dynamic>) {
        signals[entry.key] = data;
      }
    }

    return signals.isEmpty ? null : signals;
  }

  SignalSnapshotData? _decodeHierarchySnapshot(Map<String, dynamic> decoded) {
    final signals = <String, Map<String, dynamic>>{};
    _collectHierarchySignals(decoded, signals, parentPath: '');
    return signals.isEmpty ? null : signals;
  }

  void _collectHierarchySignals(
    Map<String, dynamic> moduleJson,
    Map<String, Map<String, dynamic>> signals, {
    required String parentPath,
  }) {
    final moduleName = moduleJson['name'] as String?;
    final modulePath = moduleName == null || moduleName.isEmpty
        ? parentPath
        : parentPath.isEmpty
            ? moduleName
            : '$parentPath.$moduleName';

    _collectSignalGroup(
      moduleJson['inputs'],
      direction: 'Input',
      modulePath: modulePath,
      signals: signals,
    );
    _collectSignalGroup(
      moduleJson['outputs'],
      direction: 'Output',
      modulePath: modulePath,
      signals: signals,
    );
    _collectSignalGroup(
      moduleJson['inouts'],
      direction: 'Inout',
      modulePath: modulePath,
      signals: signals,
    );

    final subModules = moduleJson['subModules'];
    if (subModules is! List) {
      return;
    }

    for (final child in subModules) {
      if (child is Map<String, dynamic>) {
        _collectHierarchySignals(child, signals, parentPath: modulePath);
      }
    }
  }

  void _collectSignalGroup(
    Object? groupJson, {
    required String direction,
    required String modulePath,
    required Map<String, Map<String, dynamic>> signals,
  }) {
    if (groupJson is! Map<String, dynamic>) {
      return;
    }

    for (final entry in groupJson.entries) {
      final signalName = entry.key;
      final data = entry.value;
      if (data is! Map<String, dynamic>) {
        continue;
      }

      final signalPath =
          modulePath.isEmpty ? signalName : '$modulePath.$signalName';
      signals[signalPath] = {
        'name': signalName,
        'value': data['value']?.toString() ?? '?',
        'width': _decodeWidth(data['width']),
        'direction': direction,
      };
    }
  }

  int _decodeWidth(Object? widthValue) {
    if (widthValue is int) {
      return widthValue;
    }
    if (widthValue is String) {
      return int.tryParse(widthValue) ?? 1;
    }
    return 1;
  }

  void _rememberTime(int time) {
    if (time <= 0) {
      return;
    }

    _lastKnownTime = time;
    if (_syntheticUpdateTime < time) {
      _syntheticUpdateTime = time;
    }
  }

  int _nextUpdateTime() {
    if (_lastKnownTime > _syntheticUpdateTime) {
      _syntheticUpdateTime = _lastKnownTime;
    }

    return ++_syntheticUpdateTime;
  }

  void _handleDebugEvent(vm.Event event) {
    final kind = event.kind;

    if (kind == null || !kind.startsWith('Pause')) {
      return;
    }

    unawaited(_emitPauseUpdate(kind));
  }

  Future<void> _emitPauseUpdate(String reason) async {
    if (_updatesController.isClosed) {
      return;
    }

    final time = _nextUpdateTime();

    _updatesController.add(
      SignalValueUpdateEvent(upToTime: time, hasData: true, reason: reason),
    );
  }
}
