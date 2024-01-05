// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tree_service_provider.dart
// Provider to communicate with tree service.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/tree_service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_app_shared/service.dart';

part 'tree_service_provider.g.dart';

@riverpod
TreeService treeService(TreeServiceRef ref) {
  final rohdControllerEval = EvalOnDartLibrary(
    'package:rohd/src/diagnostics/inspector_service.dart',
    serviceManager.service!,
    serviceManager: serviceManager,
  );
  final evalDisposable = Disposable();
  return TreeService(rohdControllerEval, evalDisposable);
}
