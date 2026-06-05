// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_service_cubit.dart
// Cubit for the ROHD service.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'dart:async';

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_value_source_binding.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';
import 'package:vm_service/vm_service.dart' as vm;

part 'rohd_service_state.dart';

/// Cubit for managing ROHD service state.
class RohdServiceCubit extends Cubit<RohdServiceState> {
  final bool _manageServiceManager;
  ServiceManager<vm.VmService>? _localServiceManager;

  /// Completer used to signal teardown of the standalone VM service to the
  /// local [ServiceManager].
  Completer<void>? _localServiceClosedSignal;

  /// The TreeService instance for ROHD.
  TreeService? treeService;

  /// Shared value source for live signal overlays, when available.
  SignalValueSource? get signalValueSource => _signalValueSource;
  SignalValueSource? _signalValueSource;

  /// The discovered ROHD isolate ID.
  ///
  /// Exposed so other consumers (e.g. waveform data source) can target the
  /// same isolate that contains the ROHD inspector_service library.
  String? get rohdIsolateId => _rohdIsolateId;
  String? _rohdIsolateId;

  /// Listener for service connection state changes.
  void Function()? _connectionListener;

  /// Constructor for RohdServiceCubit.
  RohdServiceCubit({bool manageServiceManager = true})
      : _manageServiceManager = manageServiceManager,
        super(RohdServiceInitial()) {
    if (_manageServiceManager) {
      _connectionListener = _onConnectionStateChanged;
      serviceManager.connectedState.addListener(_connectionListener!);
      if (serviceManager.connectedState.value.connected) {
        unawaited(Future.microtask(evalModuleTree));
      }
    }
  }

  /// Configure a standalone VM service session without relying on the global
  /// DevTools extension [serviceManager].
  Future<void> configureStandaloneVmService(
    vm.VmService vmService,
    String isolateId,
  ) async {
    _rohdIsolateId = null;
    _disposeSignalValueSource();

    if (_localServiceManager != null &&
        _localServiceClosedSignal != null &&
        !_localServiceClosedSignal!.isCompleted) {
      _localServiceClosedSignal!.complete();
    }

    _localServiceManager = ServiceManager<vm.VmService>();
    final localManager = _localServiceManager!;
    _localServiceClosedSignal = Completer<void>();

    await localManager.vmServiceOpened(
      vmService,
      onClosed: _localServiceClosedSignal!.future,
    );

    final vmInfo = await vmService.getVM();
    final isolates = vmInfo.isolates ?? const <vm.IsolateRef>[];
    for (final ref in isolates) {
      if (ref.id == isolateId) {
        localManager.isolateManager.selectIsolate(ref);
        break;
      }
    }

    treeService = null;
    _rohdIsolateId = null;
  }

  void _onConnectionStateChanged() {
    final connected = serviceManager.connectedState.value.connected;
    debugPrint(
      '[RohdServiceCubit] Connection state changed: '
      'connected=$connected',
    );
    if (connected) {
      // Reset tree service so we use the new connection
      treeService = null;
      unawaited(evalModuleTree());
    } else {
      // VM disconnected — reset so tree page can tear down waveforms
      // and other stale references.
      treeService = null;
      _disposeSignalValueSource();
      _rohdIsolateId = null;
      emit(RohdServiceInitial());
    }
  }

  @override
  Future<void> close() {
    if (_connectionListener != null && _manageServiceManager) {
      serviceManager.connectedState.removeListener(_connectionListener!);
      _connectionListener = null;
    }
    if (_localServiceClosedSignal != null &&
        !_localServiceClosedSignal!.isCompleted) {
      _localServiceClosedSignal!.complete();
    }
    _disposeSignalValueSource();
    _localServiceManager = null;
    return super.close();
  }

  /// Evaluate the module tree from the ROHD service.
  Future<void> evalModuleTree() async {
    debugPrint('[RohdServiceCubit] evalModuleTree called');
    await _handleModuleTreeOperation(
      (treeService) => treeService.evalModuleTree(),
    );
  }

  /// Refresh the module tree from the ROHD service.
  Future<void> refreshModuleTree() async {
    debugPrint('[RohdServiceCubit] refreshModuleTree called');
    await _handleModuleTreeOperation(
      (treeService) => treeService.refreshModuleTree(),
    );
  }

  Future<void> _handleModuleTreeOperation(
    Future<TreeModel?> Function(TreeService) operation,
  ) async {
    try {
      debugPrint(
        '[RohdServiceCubit] _handleModuleTreeOperation - emitting loading',
      );
      emit(RohdServiceLoading());

      final activeServiceManager =
          _manageServiceManager ? serviceManager : _localServiceManager;
      final activeService = activeServiceManager?.service;

      if (activeService == null) {
        debugPrint(
          '[RohdServiceCubit] ServiceManager is not initialized - '
          'emitting loaded with null',
        );
        // When not running in DevTools, just emit loaded with null tree
        // This prevents constant error states and allows the UI to work
        emit(const RohdServiceLoaded(null));
        return;
      }

      debugPrint('[RohdServiceCubit] Creating TreeService...');
      if (treeService == null) {
        // Find the isolate that actually has the ROHD library loaded.
        // With `dart test`, the DevTools "selected" isolate is often the
        // test-runner controller which doesn't import package:rohd.  We
        // need to scan all isolates to find the one with inspector_service.
        final service = activeService;
        ValueListenable<vm.IsolateRef?>? rohdIsolate;

        try {
          final vmInfo = await service.getVM();
          final isolates = vmInfo.isolates ?? [];
          debugPrint(
            '[RohdServiceCubit] Scanning ${isolates.length} '
            'isolate(s) for ROHD library...',
          );

          for (final isoRef in isolates) {
            final id = isoRef.id;
            if (id == null) {
              continue;
            }
            try {
              final iso = await service.getIsolate(id);
              final libs = iso.libraries ?? [];
              debugPrint(
                '[RohdServiceCubit]   Isolate ${isoRef.name} '
                '(${isoRef.id}): ${libs.length} libraries',
              );
              final hasRohd = libs.any(
                (lib) =>
                    lib.uri ==
                    'package:rohd/src/diagnostics/inspector_service.dart',
              );
              if (hasRohd) {
                debugPrint(
                  '[RohdServiceCubit]   → Found ROHD in '
                  '${isoRef.name}',
                );
                rohdIsolate = ValueNotifier(isoRef);
                _rohdIsolateId = id;
                break;
              }
            } on Exception catch (e) {
              debugPrint(
                '[RohdServiceCubit]   Isolate ${isoRef.name} '
                'scan error: $e',
              );
            }
          }
        } on Exception catch (e) {
          debugPrint('[RohdServiceCubit] VM scan failed: $e');
        }

        if (rohdIsolate == null) {
          debugPrint(
            '[RohdServiceCubit] ROHD isolate not found, '
            'falling back to selected isolate',
          );
        }

        treeService = TreeService(
          EvalOnDartLibrary(
            'package:rohd/src/diagnostics/inspector_service.dart',
            service,
            serviceManager: activeServiceManager!,
            isolate: rohdIsolate,
          ),
          Disposable(),
          vmService: service,
          isolateId: _rohdIsolateId,
        );

        _disposeSignalValueSource();
        _signalValueSource = createSignalValueSourceBinding(
          treeService: treeService!,
          vmService: service,
        );
      }

      debugPrint('[RohdServiceCubit] Calling operation...');
      final treeModel = await operation(treeService!);

      debugPrint('[RohdServiceCubit] Operation complete, emitting loaded');
      emit(RohdServiceLoaded(treeModel));
    } on Exception catch (error, trace) {
      debugPrint('[RohdServiceCubit] Error: $error');
      // Reset treeService so next attempt re-scans for the ROHD isolate.
      treeService = null;
      _disposeSignalValueSource();
      _rohdIsolateId = null;
      emit(RohdServiceError(error.toString(), trace));
    }
  }

  void _disposeSignalValueSource() {
    unawaited(disposeSignalValueSourceBinding(_signalValueSource));
    _signalValueSource = null;
  }
}
