@TestOn('browser')
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rohd_devtools_extension/src/modules/rohd_devtools_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/signal_service_provider.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/providers/tree_service_provider.dart';

import 'rohd_devtools_mocks.dart';

void main() {
  final mockTreeService = MockTreeService();
  final mockSignalService = MockSignalService();

  final container = ProviderContainer(overrides: [
    treeServiceProvider.overrideWith((ref) => mockTreeService),
    signalServiceProvider.overrideWith((ref) => mockSignalService),
  ]);

  testWidgets('RohdDevToolsModule widget tree contains expected widgets',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: RohdDevToolsModule(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify that the RohdDevToolsModule exists in the widget tree.
    expect(find.byType(RohdDevToolsModule), findsOneWidget,
        reason: 'RohdDevToolsModule is missing.');
  });

  tearDown(() {
    container.dispose();
  });
}
