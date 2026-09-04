// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter_test/flutter_test.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_extension_client.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/flc_service.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

void main() {
  test('RohdModuleInfo preserves DTD health diagnostics', () {
    final info = RohdModuleInfo.fromJson({
      'extensionAvailable': true,
      'module': 'Adder',
      'formats': {
        'rohd': {'available': true, 'fileFound': true},
      },
      'dtdHealthy': false,
      'dtdRegistrationConflict': true,
      'dtdStatusMessage': 'DTD service rohd is owned elsewhere.',
    });

    expect(info.extensionAvailable, isTrue);
    expect(info.hasRohd, isTrue);
    expect(info.dtdHealthy, isFalse);
    expect(info.dtdRegistrationConflict, isTrue);
    expect(info.dtdStatusMessage, contains('owned elsewhere'));

    expect(info.toJson(), containsPair('dtdHealthy', false));
    expect(info.toJson(), containsPair('dtdRegistrationConflict', true));
    expect(
      info.toJson(),
      containsPair('dtdStatusMessage', 'DTD service rohd is owned elsewhere.'),
    );
  });

  test(
      'queryModule keeps definition name when formats come from '
      'instance fallback', () async {
    final flcService = FlcService(
      fetchModuleFlc: (definitionName) async {
        if (definitionName == 'floatingpoint_adder_singlepath') {
          return {
            'version': 5,
            'files': ['lib/src/floating_point.dart'],
            'modules': {
              'floatingpoint_adder_singlepath': {
                'svFile': 'FloatingPointAdderSinglePath.sv',
                'tree': [
                  ['0:10:5', 'sum@20:3'],
                ],
              },
            },
          };
        }
        return {
          'version': 5,
          'files': <String>[],
          'modules': <String, Object>{},
        };
      },
      fetchFlcHierarchy: () async => null,
    );
    final client = FlcExtensionClient(flcService: flcService);

    final info = await client.queryModule(
      'FloatingPointAdderSinglePath_E4M4',
      instancePath: ['top', 'floatingpoint_adder_singlepath'],
    );

    expect(info.module, 'FloatingPointAdderSinglePath_E4M4');
    expect(info.formats.keys, contains(RohdSourceFormat.sv));
    expect(
      client.currentModuleInfo.value?.module,
      'FloatingPointAdderSinglePath_E4M4',
    );
  });
}
