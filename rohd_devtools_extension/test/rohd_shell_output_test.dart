// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_shell_output_test.dart
// Tests for ROHD design shell output.
//
// 2026 September 15
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/cli/rohd_shell_output.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

void main() {
  tearDown(SignalValueFormatRegistry.clear);

  group('RohdShellOutput.pretty', () {
    test('labels an occurrence by address without printing its DTO', () {
      final output = RohdShellOutput.pretty({
        'ok': true,
        'result': {'address': '0.1.2', 'kind': 'port'},
      });

      expect(output.isError, isFalse);
      expect(output.text, 'ok: occurrence port 0.1.2');
      expect(output.text, isNot(contains('path:')));
    });

    test('shows a path only for an explicit name expansion', () {
      final output = RohdShellOutput.pretty({
        'ok': true,
        'result': {
          'address': '0.1.2',
          'kind': 'signal',
          'path': 'top/alu/sum',
          'name': 'sum',
          'width': 32,
        },
      });

      expect(
        output.text,
        'ok: occurrence signal 0.1.2\n'
        '  path: top/alu/sum\n'
        '  name: sum\n'
        '  width: 32',
      );
    });

    test('labels assigned occurrence lists without printing addresses', () {
      final output = RohdShellOutput.pretty({
        'ok': true,
        'alias': 'selected',
        'result': {
          'items': [
            {'address': '0.1'},
            {'address': '0.2', 'kind': 'signal'},
          ],
        },
      });

      expect(output.isError, isFalse);
      expect(output.text, r'ok: $selected = 2 occurrences');
      expect(output.text, isNot(contains('0.1')));
      expect(output.text, isNot(contains('0.2')));
    });

    test('formats protocol errors for a terminal or GUI entry', () {
      final output = RohdShellOutput.pretty({
        'ok': false,
        'error': {
          'code': 'invalidArgument',
          'message': r'Unknown occurrence alias: $missing',
        },
      });

      expect(output.isError, isTrue);
      expect(
        output.text,
        r'error [invalidArgument]: Unknown occurrence alias: $missing',
      );
    });

    test('retains a signal value and sampling time', () {
      final output = RohdShellOutput.pretty({
        'ok': true,
        'result': {
          'address': '0.1.2',
          'kind': 'port',
          'value': '1',
          'time': 20,
          'sampleTime': 18,
        },
      });

      expect(output.text, 'ok: value port 0.1.2 = 1 at 20 (sampled 18)');
    });

    test('uses the selected occurrence format for a value', () {
      SignalValueFormatRegistry.setFormatFor([
        const OccurrenceAddress([0, 1, 2]),
      ], SignalValueFormat.unsignedDecimal);

      final output = RohdShellOutput.pretty(
        {
          'ok': true,
          'result': {
            'address': '0.1.2',
            'kind': 'signal',
            'path': 'top/alu/sum',
            'width': 4,
            'value': '0x0',
          },
        },
        formatForPath: (_) => SignalValueFormatRegistry.formatFor(
          const OccurrenceAddress([0, 1, 2]),
        ),
      );

      expect(output.text, 'ok: value signal 0.1.2 = 0');
    });

    test('uses an explicitly bridged format over its local registry', () {
      final output = RohdShellOutput.pretty({
        'ok': true,
        'result': {
          'address': '0.1.2',
          'kind': 'signal',
          'path': 'top/alu/sum',
          'width': 4,
          'value': '0x0',
          'format': 'unsignedDecimal',
        },
      });

      expect(output.text, 'ok: value signal 0.1.2 = 0');
    });

    test('summarizes signals sent to other panes', () {
      final output = RohdShellOutput.pretty({
        'ok': true,
        'result': {
          'paths': ['top/alu/sum'],
        },
      });

      expect(output.isError, isFalse);
      expect(output.text, 'ok: sent 1 signal');
    });
  });
}
