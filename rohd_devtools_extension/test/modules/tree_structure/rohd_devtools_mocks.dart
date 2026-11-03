// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_mocks.dart
// All the mocks initialization for services and providers.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/hierarchy_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';

class MockTreeModel extends Mock implements TreeModel {}

class MockSignalModel extends Mock implements SignalModel {}

class MockTreeService extends Mock implements TreeService {}

class MockRohdServiceCubit extends Mock implements RohdServiceCubit {}

class MockDevToolsHierarchyCubit extends Mock
    implements DevToolsHierarchyCubit {}

class MockTreeSearchTermCubit extends Mock implements TreeSearchTermCubit {}

class MockSignalSearchTermCubit extends Mock implements SignalSearchTermCubit {}
