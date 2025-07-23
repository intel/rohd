// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_service_cubit.dart
// Cubit for the ROHD service.
//
// 2025 January 28
// Author: Roberto Torres <roberto.torres@intel.com>

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';

part 'rohd_service_state.dart';

class RohdServiceCubit extends Cubit<RohdServiceState> {
  TreeService? treeService;

  RohdServiceCubit() : super(RohdServiceInitial()) {
    evalModuleTree();
  }

  Future<void> evalModuleTree() async {
    await _handleModuleTreeOperation(
        (treeService) => treeService.evalModuleTree());
  }

  Future<void> refreshModuleTree() async {
    await _handleModuleTreeOperation(
        (treeService) => treeService.refreshModuleTree());
  }

  Future<void> _handleModuleTreeOperation(
      Future<TreeModel?> Function(TreeService) operation) async {
    try {
      emit(RohdServiceLoading());
      if (serviceManager.service == null) {
        throw Exception('ServiceManager is not initialized');
      }
      treeService ??= TreeService(
        EvalOnDartLibrary(
          'package:rohd/src/diagnostics/inspector_service.dart',
          serviceManager.service!,
          serviceManager: serviceManager,
        ),
        Disposable(),
      );
      final treeModel = await operation(treeService!);
      emit(RohdServiceLoaded(treeModel));
    } catch (error, trace) {
      emit(RohdServiceError(error.toString(), trace));
    }
  }
}
