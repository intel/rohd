// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_design_shell_test.dart
// Tests for the target-backed DevTools command shell.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_design_dtd_service.dart';
import 'package:rohd_devtools_extension/rohd_devtools/ui/rohd_design_shell.dart';

class _FakeTarget implements RohdDesignCommandTarget {
  final commands = <({String sessionId, String input})>[];

  @override
  Future<Map<String, Object?>> command(String sessionId, String input) async {
    commands.add((sessionId: sessionId, input: input));
    return {'ok': true, 'input': input};
  }

  @override
  Future<Map<String, Object?>> complete(
    String sessionId,
    String input,
    int cursor,
  ) async =>
      {'ok': true, 'items': const <String>[]};
}

void main() {
  testWidgets('submits successive commands through one target session', (
    tester,
  ) async {
    final target = _FakeTarget();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: RohdDesignShell(targetProvider: () async => target),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'status');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'help');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(target.commands.map((command) => command.input), ['status', 'help']);
    expect(target.commands[0].sessionId, target.commands[1].sessionId);
    expect(find.text('ok: no matching occurrence'), findsNWidgets(2));
  });
}
