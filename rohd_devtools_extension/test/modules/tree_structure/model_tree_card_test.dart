// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// model_tree_card_test.dart
// The tests for model tree card functionality.
//
// 2024 January 9
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/selected_module_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/module_tree_card.dart';

import 'fixtures/tree_model.stub.dart';
import 'rohd_devtools_mocks.dart';

void main() {
  final mockTreeService = MockTreeService();
  final mockSelectedModule = MockSelectedModule();

  final container = ProviderContainer(overrides: [
    treeServiceProvider.overrideWith((ref) => mockTreeService),
    selectedModuleProvider.overrideWith(() => mockSelectedModule),
  ]);

  setUpAll(() {
    // Register a fallback value for TreeModel
    registerFallbackValue(TreeModelStub.selectedModule);
  });

  testWidgets('ModuleTreeCard renders tree correctly',
      (WidgetTester tester) async {
    // Initialize the futureModuleTree
    final futureModuleTree =
        AsyncValue<TreeModel>.data(TreeModelStub.simpleTreeModel);

    // Wrap the ModuleTreeCard widget in ProviderScope for Riverpod Providers
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ModuleTreeCard(futureModuleTree: futureModuleTree),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Validate that the TreeView widget is present
    expect(find.text('counter'), findsOneWidget);
  });
}
