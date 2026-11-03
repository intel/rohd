// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// truncation_warning_test.dart
// Tests diagnostics for integer constant truncation.
//
// 2026 November
// Author: Desmond Kirkpatrick <desmond.kirkpatrick@intel.com>

import 'package:logging/logging.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

const _truncationWarning = 'Truncating integer constant';

void main() {
  tearDown(Simulator.reset);

  test('warns when integer constants are truncated', () {
    final warnings = <LogRecord>[];
    final subscription = Simulator.logger.onRecord.listen((record) {
      if (record.level == Level.WARNING &&
          record.message.contains(_truncationWarning)) {
        warnings.add(record);
      }
    });
    addTearDown(subscription.cancel);

    expect(Const(0x10, width: 4).value, LogicValue.ofInt(0, 4));
    expect(
      LogicValue.of(BigInt.from(0x10), width: 4),
      LogicValue.ofInt(0, 4),
    );

    expect(warnings, hasLength(2));
  });

  test('allows intentional and signed truncation without warnings', () {
    final warnings = <LogRecord>[];
    final subscription = Simulator.logger.onRecord.listen((record) {
      if (record.level == Level.WARNING &&
          record.message.contains(_truncationWarning)) {
        warnings.add(record);
      }
    });
    addTearDown(subscription.cancel);

    expect(
      Const(0x10, width: 4, allowTruncation: true).value,
      LogicValue.ofInt(0, 4),
    );
    expect(
      LogicValue.of(0x10, width: 4, allowTruncation: true),
      LogicValue.ofInt(0, 4),
    );
    expect(Const(-1, width: 1).value, LogicValue.one);
    expect(LogicValue.of(-1, width: 1), LogicValue.one);

    expect(warnings, isEmpty);
  });
}
