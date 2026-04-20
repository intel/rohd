// Copyright (C) 2025-2026 Intel Corporation
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
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';
import 'package:vm_service/vm_service.dart' as vm;

part 'rohd_service_state.dart';

/// Cubit for managing ROHD service state.
class RohdServiceCubit extends Cubit<RohdServiceState> {
  /// The TreeService instance for ROHD.
  TreeService? treeService;

  /// The discovered ROHD isolate ID.
  ///
  /// Exposed so other consumers (e.g. waveform data source) can target the
  /// same isolate that contains the ROHD inspector_service library.
  String? get rohdIsolateId => _rohdIsolateId;
  String? _rohdIsolateId;

  /// Listener for service connection state changes.
  void Function()? _connectionListener;

  /// Constructor for RohdServiceCubit.
  RohdServiceCubit() : super(RohdServiceInitial()) {
    // Listen for service connection state changes.
    _connectionListener = _onConnectionStateChanged;
    serviceManager.connectedState.addListener(_connectionListener!);
    // Check if already connected (in case we missed the event).
    if (serviceManager.connectedState.value.connected) {
      unawaited(Future.microtask(evalModuleTree));
    }
  }

  void _onConnectionStateChanged() {
    final connected = serviceManager.connectedState.value.connected;
    if (connected) {
      // Reset tree service so we use the new connection.
      treeService = null;
      unawaited(evalModuleTree());
    } else {
      // VM disconnected — reset stale references.
      treeService = null;
      _rohdIsolateId = null;
      emit(RohdServiceInitial());
    }
  }

  @override
  Future<void> close() {
    if (_connectionListener != null) {
      serviceManager.connectedState.removeListener(_connectionListener!);
      _connectionListener = null;
    }
    return super.close();
  }

  /// Evaluate the module tree from the ROHD service.
  Future<void> evalModuleTree() async {
    await _handleModuleTreeOperation(
        (treeService) => treeService.evalModuleTree());
  }

  /// Refresh the module tree from the ROHD service.
  Future<void> refreshModuleTree() async {
    await _handleModuleTreeOperation(
        (treeService) => treeService.refreshModuleTree());
  }

  Future<void> _handleModuleTreeOperation(
      Future<TreeModel?> Function(TreeService) operation) async {
    try {
      emit(RohdServiceLoading());

      if (serviceManager.service == null) {
        // When not running in DevTools, emit loaded with null tree.
        emit(const RohdServiceLoaded(null));
        return;
      }

      if (treeService == null) {
        // Find the isolate that actually has the ROHD library loaded.
        // With `dart test`, the DevTools "selected" isolate is often the
        // test-runner controller which doesn't import package:rohd.  We
        // need to scan all isolates to find the one with inspector_service.
        final service = serviceManager.service!;
        ValueListenable<vm.IsolateRef?>? rohdIsolate;

        try {
          final vmInfo = await service.getVM();
          final isolates = vmInfo.isolates ?? [];

          for (final isoRef in isolates) {
            final id = isoRef.id;
            if (id == null) continue;
            try {
              final iso = await service.getIsolate(id);
              final libs = iso.libraries ?? [];
              final hasRohd = libs.any((lib) =>
                  lib.uri ==
                  'package:rohd/src/diagnostics/inspector_service.dart');
              if (hasRohd) {
                debugPrint('[RohdServiceCubit] Found ROHD in '
                    '${isoRef.name}');
                rohdIsolate = ValueNotifier(isoRef);
                _rohdIsolateId = id;
                break;
              }
            } on Exception {
              // Isolate not loaded yet — skip.
              continue;
            }
          }
        } on Exception catch (e) {
          debugPrint('[RohdServiceCubit] VM scan failed: $e');
        }

        if (rohdIsolate == null) {
          debugPrint('[RohdServiceCubit] ROHD isolate not found, '
              'falling back to selected isolate');
        }

        treeService = TreeService(
          EvalOnDartLibrary(
            'package:rohd/src/diagnostics/inspector_service.dart',
            service,
            serviceManager: serviceManager,
            isolate: rohdIsolate,
          ),
          Disposable(),
        );
      }

      final treeModel = await operation(treeService!);
      emit(RohdServiceLoaded(treeModel));
    } on Exception catch (error, trace) {
      // Reset treeService so next attempt re-scans for the ROHD isolate.
      treeService = null;
      _rohdIsolateId = null;
      emit(RohdServiceError(error.toString(), trace));
    }
  }
}
