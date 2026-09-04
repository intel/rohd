// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registeredBundledThirdPartyLicenses = false;

/// Registers license text for non-pub assets bundled by the viewer packages.
void registerBundledThirdPartyLicenses() {
  if (_registeredBundledThirdPartyLicenses) {
    return;
  }
  _registeredBundledThirdPartyLicenses = true;

  LicenseRegistry.addLicense(() async* {
    for (final bundledLicense in _bundledLicenses) {
      yield LicenseEntryWithLineBreaks(
        <String>[bundledLicense.packageName],
        await _loadLicenseText(bundledLicense),
      );
    }
  });
}

Future<String> _loadLicenseText(_BundledLicense bundledLicense) async {
  try {
    return await rootBundle.loadString(bundledLicense.assetPath);
  } on Object catch (error) {
    return 'Unable to load bundled license text from '
        '${bundledLicense.assetPath}: $error';
  }
}

const _bundledLicenses = <_BundledLicense>[
  _BundledLicense(
    packageName: 'ELK JavaScript layout engine',
    assetPath:
        'packages/rohd_schematic_viewer/assets/third_party/elkjs/LICENSES/EPL-2.0.txt',
  ),
  _BundledLicense(
    packageName: 'Wellen waveform bridge',
    assetPath:
        'packages/rohd_wave_viewer/assets/licenses/wellen_bridge_LICENSES.txt',
  ),
];

class _BundledLicense {
  final String packageName;
  final String assetPath;

  const _BundledLicense({
    required this.packageName,
    required this.assetPath,
  });
}
