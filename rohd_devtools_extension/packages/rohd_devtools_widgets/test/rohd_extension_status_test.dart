// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_extension_status_test.dart
// Tests for ROHD extension status models and null client.
//
// 2026 July
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  group('RohdModuleInfo', () {
    test('round-trips JSON and exposes usable format helpers', () {
      final info = RohdModuleInfo.fromJson({
        'extensionAvailable': true,
        'module': 'Counter',
        'dtdHealthy': true,
        'dtdRegistrationConflict': true,
        'dtdStatusMessage': 'using ROHD bridge',
        'fstLoading': true,
        'formats': {
          'rohd': {
            'available': true,
            'fileFound': true,
            'path': '/tmp/counter.dart',
          },
          'sv': {
            'available': true,
            'fileFound': false,
            'path': '/tmp/counter.sv',
          },
          'fst': {
            'available': true,
            'fileFound': true,
            'path': '/tmp/counter.fst',
          },
          'unknown': {'available': true, 'fileFound': true},
        },
      });

      expect(info.extensionAvailable, isTrue);
      expect(info.module, 'Counter');
      expect(info.dtdHealthy, isTrue);
      expect(info.dtdRegistrationConflict, isTrue);
      expect(info.dtdStatusMessage, 'using ROHD bridge');
      expect(info.fstLoading, isTrue);
      expect(info.hasRohd, isTrue);
      expect(info.hasSv, isFalse);
      expect(info.hasSc, isFalse);
      expect(info.hasFst, isTrue);
      expect(info.hasAnySource, isTrue);
      expect(info.availableFormatNames, ['rohd', 'fst']);
      expect(info.navigableSourceFormats, [RohdSourceFormat.rohd]);

      expect(info.toJson(), {
        'extensionAvailable': true,
        'module': 'Counter',
        'formats': {
          'rohd': {
            'available': true,
            'fileFound': true,
            'path': '/tmp/counter.dart',
          },
          'sv': {
            'available': true,
            'fileFound': false,
            'path': '/tmp/counter.sv',
          },
          'fst': {
            'available': true,
            'fileFound': true,
            'path': '/tmp/counter.fst',
          },
        },
        'dtdHealthy': true,
        'dtdRegistrationConflict': true,
        'dtdStatusMessage': 'using ROHD bridge',
        'fstLoading': true,
      });
    });

    test('uses display labels and unavailable sentinel defaults', () {
      expect(RohdModuleInfo.formatLabel(RohdSourceFormat.rohd), 'ROHD (Dart)');
      expect(RohdModuleInfo.formatLabel(RohdSourceFormat.sv), 'SystemVerilog');
      expect(RohdModuleInfo.formatLabel(RohdSourceFormat.sc), 'SystemC');
      expect(
          RohdModuleInfo.formatLabel(RohdSourceFormat.fst), 'Waveform (FST)');

      const unavailable = RohdModuleInfo.unavailable;
      expect(unavailable.extensionAvailable, isFalse);
      expect(unavailable.availableFormatNames, isEmpty);
      expect(unavailable.navigableSourceFormats, isEmpty);
      expect(unavailable.toJson(), {
        'extensionAvailable': false,
        'formats': <String, dynamic>{},
        'fstLoading': false,
      });
    });
  });

  group('NullExtensionClient', () {
    test('reports unavailable and returns empty lookup results', () async {
      final client = NullExtensionClient();
      addTearDown(client.dispose);

      expect(client.isAvailable.value, isFalse);
      expect(client.currentModuleInfo.value, isNull);
      expect(await client.ping(), isFalse);
      expect(await client.queryModule('Counter'), RohdModuleInfo.unavailable);
      expect(
        await client.lookupSignalFrames(
          signals: [
            {'module': 'Counter', 'name': 'clk'},
          ],
          format: 'rohd',
        ),
        isEmpty,
      );

      client.openSourceLocation(file: '/tmp/counter.dart', line: 12);
      expect(client.isAvailable.value, isFalse);
      expect(client.currentModuleInfo.value, isNull);
    });
  });
}
