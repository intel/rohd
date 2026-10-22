// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

@TestOn('vm')
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_shell_output.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/io_vm_connection_strategy.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/rohd_design_shell.dart';

import 'support/filter_bank_vm_target.dart';

class _RecordedTarget implements RohdDesignCommandTarget {
  final List<Map<String, Object?>> commandResponses;
  final List<Map<String, Object?>> completionResponses;
  final commands = <({String sessionId, String input})>[];
  final completions = <({String sessionId, String input, int cursor})>[];

  _RecordedTarget({
    required this.commandResponses,
    required this.completionResponses,
  });

  @override
  Future<Map<String, Object?>> command(String sessionId, String input) async {
    commands.add((sessionId: sessionId, input: input));
    return commandResponses.removeAt(0);
  }

  @override
  Future<Map<String, Object?>> complete(
    String sessionId,
    String input,
    int cursor,
  ) async {
    completions.add((sessionId: sessionId, input: input, cursor: cursor));
    return completionResponses.removeAt(0);
  }
}

void main() {
  testWidgets(
    'renders real VM command results and completions in the DevTools shell',
    (tester) async {
      final target = await tester.runAsync(startFilterBankVmTarget);
      expect(target, isNotNull);
      final vmTarget = target!;
      addTearDown(vmTarget.dispose);

      final connection = await tester.runAsync(
        () => IoVmConnectionStrategy(
          retryDelay: const Duration(milliseconds: 50),
        ).connect(vmTarget.serviceUri),
      );
      expect(connection, isNotNull);
      final vmConnection = connection!;
      addTearDown(vmConnection.vmService.dispose);
      final vmTargetProxy = VmServiceRohdDesignTarget(
        vmConnection.vmService,
        vmConnection.isolateId,
      );
      final commandResponse = await tester.runAsync(
        () => vmTargetProxy.command('shell-ui', 'find-ports .*'),
      );
      final scriptCommandResponses = await tester.runAsync(
        () => Future.wait([
          vmTargetProxy.command('shell-ui', 'find-ports clk'),
          vmTargetProxy.command('shell-ui', 'find-ports reset'),
        ]),
      );
      final completionResponse = await tester.runAsync(
        () => vmTargetProxy.complete('shell-ui', 'find-p', 6),
      );
      expect(commandResponse, isNotNull);
      expect(completionResponse, isNotNull);
      final targetProxy = _RecordedTarget(
        commandResponses: [
          commandResponse!,
          ...scriptCommandResponses!,
        ],
        completionResponses: [completionResponse!],
      );
      const script = '''
# Query the real FilterBank target.

find-ports clk
find-ports reset
''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 420,
              child: RohdDesignShell(
                targetProvider: () async => targetProxy,
                scriptLoader: () async => script,
              ),
            ),
          ),
        ),
      );

      final prompt = find.byType(TextField);
      expect(prompt, findsOneWidget);
      await tester.enterText(prompt, 'find-ports .*');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(targetProxy.commands, hasLength(1));
      expect(targetProxy.commands.single.input, 'find-ports .*');
      expect(
        targetProxy.commands.single.sessionId,
        isNotEmpty,
      );
      final expectedOutput = RohdShellOutput.pretty(commandResponse).text;
      expect(find.text(expectedOutput), findsOneWidget);

      await tester.enterText(prompt, 'find-p');
      await tester.tap(find.byTooltip('Complete command'));
      await tester.pump();
      await tester.pump();

      expect(targetProxy.completions, hasLength(1));
      expect(targetProxy.completions.single.input, 'find-p');
      final completedText = tester.widget<TextField>(prompt).controller!.text;
      expect(completedText, startsWith('find-p'));

      await tester.tap(find.byTooltip('Load shell script'));
      await tester.pumpAndSettle();

      expect(
        targetProxy.commands.map((command) => command.input),
        ['find-ports .*', 'find-ports clk', 'find-ports reset'],
      );
      final sessionId = targetProxy.commands.first.sessionId;
      expect(
        targetProxy.commands.every((command) => command.sessionId == sessionId),
        isTrue,
      );
      expect(find.text('rohd> find-ports clk'), findsOneWidget);
      expect(find.text('rohd> find-ports reset'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        tester.widget<TextField>(prompt).controller!.text,
        'find-ports reset',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tester.widget<TextField>(prompt).controller!.text, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
