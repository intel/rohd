// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cubit/hierarchy_cubit.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/module_search_overlay.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

HierarchyOccurrence _rootWithChild(String childName) => HierarchyOccurrence(
      name: 'top',
      children: [
        HierarchyOccurrence(name: childName),
      ],
    );

void main() {
  testWidgets('selects the submitted search result and clears the filter', (
    tester,
  ) async {
    final root = _rootWithChild('controller');
    final hierarchyCubit = DevToolsHierarchyCubit()..loadFromNode(root);
    addTearDown(hierarchyCubit.close);
    final terms = <String>[];

    await tester.pumpWidget(
      BlocProvider.value(
        value: hierarchyCubit,
        child: MaterialApp(
          home: Scaffold(
            body: ModuleSearchField(
              hierarchy: hierarchyCubit.currentService,
              onSearchTermChanged: terms.add,
            ),
          ),
        ),
      ),
    );

    final search = find.byType(TextField);
    await tester.enterText(search, 'controller');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.text('controller'),
      ),
      findsOneWidget,
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(hierarchyCubit.selectedModule, same(root.children.single));
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(terms, containsAllInOrder(['controller', '']));
    expect(terms.last, isEmpty);
  });

  testWidgets('rebuilds local results when its hierarchy service changes', (
    tester,
  ) async {
    final firstRoot = _rootWithChild('first');
    final secondRoot = _rootWithChild('second');
    final hierarchyCubit = DevToolsHierarchyCubit()..loadFromNode(firstRoot);
    addTearDown(hierarchyCubit.close);

    Future<void> pumpSearch(HierarchyService hierarchy) => tester.pumpWidget(
          BlocProvider.value(
            value: hierarchyCubit,
            child: MaterialApp(
              home: Scaffold(
                body: ModuleSearchField(
                  key: const ValueKey('module-search'),
                  hierarchy: hierarchy,
                ),
              ),
            ),
          ),
        );

    await pumpSearch(hierarchyCubit.currentService!);
    final search = find.byType(TextField);
    await tester.enterText(search, 'first');
    await tester.pump();
    expect(
      find.descendant(of: find.byType(InkWell), matching: find.text('first')),
      findsOneWidget,
    );

    final replacementHierarchy = BaseHierarchyAdapter.fromTree(secondRoot);
    await pumpSearch(replacementHierarchy);
    await tester.pump();

    expect(
      find.descendant(of: find.byType(InkWell), matching: find.text('first')),
      findsNothing,
    );
  });
}
