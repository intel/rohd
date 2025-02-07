// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_mocks.dart
// All the mocks initialization for services and providers.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/tree_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/tree_service.dart';

class MockTreeModel extends Mock implements TreeModel {}

class MockTreeService extends Mock implements TreeService {}

class MockSignalService extends Mock implements SignalService {}

class MockRohdServiceCubit extends Mock implements RohdServiceCubit {}

class MockSelectedModuleCubit extends Mock implements SelectedModuleCubit {}

class MockTreeSearchTermCubit extends Mock implements TreeSearchTermCubit {}

class MockSignalSearchTermCubit extends Mock implements SignalSearchTermCubit {}
