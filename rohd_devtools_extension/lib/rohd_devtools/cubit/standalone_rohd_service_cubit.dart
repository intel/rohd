// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// standalone_rohd_service_cubit.dart
// Cubit for ROHD service in standalone (non-web) mode.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/standalone_tree_service.dart';
import 'package:vm_service/vm_service.dart';

part 'standalone_rohd_service_state.dart';

/// Cubit for managing ROHD service state in standalone mode.
/// This version uses VmService directly without devtools_app_shared.
class StandaloneRohdServiceCubit extends Cubit<StandaloneRohdServiceState> {
  StandaloneTreeService? _treeService;
  VmService? _vmService;
  String? _isolateId;

  /// Constructor for [StandaloneRohdServiceCubit].
  StandaloneRohdServiceCubit() : super(StandaloneRohdServiceInitial());

  /// Initialize with a connected VM service
  Future<void> initialize(VmService vmService, String isolateId) async {
    _vmService = vmService;
    _isolateId = isolateId;
    _treeService = StandaloneTreeService(
      vmService: vmService,
      isolateId: isolateId,
    );
    await evalModuleTree();
  }

  /// Check if the cubit is initialized with a VM service
  bool get isInitialized => _vmService != null && _isolateId != null;

  /// Evaluate the module tree
  Future<void> evalModuleTree() async {
    if (!isInitialized) {
      emit(
        StandaloneRohdServiceError(
          'Not connected to VM service',
          StackTrace.current,
        ),
      );
      return;
    }

    try {
      emit(StandaloneRohdServiceLoading());
      final treeModel = await _treeService!.evalModuleTree();
      emit(StandaloneRohdServiceLoaded(treeModel));
    } on Exception catch (error, trace) {
      emit(StandaloneRohdServiceError(error.toString(), trace));
    }
  }

  /// Refresh the module tree
  Future<void> refreshModuleTree() async {
    if (!isInitialized) {
      emit(
        StandaloneRohdServiceError(
          'Not connected to VM service',
          StackTrace.current,
        ),
      );
      return;
    }

    try {
      emit(StandaloneRohdServiceLoading());
      final treeModel = await _treeService!.refreshModuleTree();
      emit(StandaloneRohdServiceLoaded(treeModel));
    } on Exception catch (error, trace) {
      emit(StandaloneRohdServiceError(error.toString(), trace));
    }
  }

  /// Disconnect and reset state
  void disconnect() {
    _vmService = null;
    _isolateId = null;
    _treeService = null;
    emit(StandaloneRohdServiceInitial());
  }

  @override
  Future<void> close() {
    disconnect();
    return super.close();
  }
}
