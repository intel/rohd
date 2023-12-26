@TestOn('browser')
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/signal_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/module_tree_card.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/module_tree_details_navbar.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/signal_details_card.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/view/tree_structure_page.dart';

import 'fixtures/tree_model.stub.dart';
import 'rohd_devtools_mocks.dart';

void main() {
  final mockTreeService = MockTreeService();
  final mockSignalService = MockSignalService();

  final container = ProviderContainer(overrides: [
    treeServiceProvider.overrideWith((ref) => mockTreeService),
    signalServiceProvider.overrideWith((ref) => mockSignalService),
  ]);

  testWidgets('TreeStructurePage contains expected widgets',
      (WidgetTester tester) async {
    // Build your app for testing.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: TreeStructurePage(
            screenSize: const Size(2225, 1000),
            futureModuleTree: AsyncValue.data(
                TreeModelStub.simpleTreeModel), // Provide a mock tree model
            selectedModule: null,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify the presence of widgets in TreeStructurePage
    expect(find.byType(ModuleTreeCard), findsOneWidget,
        reason: 'No ModuleTreeCard!');
    expect(find.byType(SignalDetailsCard), findsOneWidget,
        reason: 'No SignalDetailsCard!');
  });

  tearDown(() {
    container.dispose();
  });
}
