// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_service_test.dart
// Tests for signal filtering service behavior.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/models/signal_model.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/signal_service.dart';

void main() {
  final signals = [
    SignalModel(
      name: 'ClockEnable',
      direction: 'Input',
      value: "1'h1",
      width: 1,
    ),
    SignalModel(
      name: 'counterValue',
      direction: 'Output',
      value: "8'h2a",
      width: 8,
    ),
    SignalModel(
      name: 'reset',
      direction: 'Input',
      value: "1'h0",
      width: 1,
    ),
  ];

  group('SignalService.filterSignals', () {
    test('matches names case insensitively and retains source order', () {
      final filtered = SignalService.filterSignals(signals, 'C');

      expect(filtered, [signals[0], signals[1]]);
    });

    test('returns all signals for an empty search term', () {
      expect(SignalService.filterSignals(signals, ''), signals);
    });

    test('returns no signals when no name matches', () {
      expect(SignalService.filterSignals(signals, 'missing'), isEmpty);
    });
  });
}
