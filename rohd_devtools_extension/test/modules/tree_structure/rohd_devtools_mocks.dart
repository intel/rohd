// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_devtools_mocks.dart
// All the mocks initialization for services and providers.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/rohd_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/selected_module_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/tree_service.dart';

class MockTreeModel extends Mock implements TreeModel {}

class MockRohdModuleTree extends Mock implements RohdModuleTree {}

class MockTreeService extends Mock implements TreeService {}

class MockSignalService extends Mock implements SignalService {}

class MockSelectedModule extends Mock implements SelectedModule {}
