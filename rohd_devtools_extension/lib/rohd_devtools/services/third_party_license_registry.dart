// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

bool _registeredBundledThirdPartyLicenses = false;

/// Registers license text for non-pub assets bundled by the viewer packages.
void registerBundledThirdPartyLicenses() {
  if (_registeredBundledThirdPartyLicenses) {
    return;
  }
  _registeredBundledThirdPartyLicenses = true;

  LicenseRegistry.addLicense(() async* {
    for (final bundledLicense in _bundledLicenses) {
      yield LicenseEntryWithLineBreaks(<String>[
        bundledLicense.packageName,
      ], await _loadLicenseText(bundledLicense));
    }
  });
}

/// Opens the licenses page with the debugger's theme and localizations.
void showRohdLicensePage(BuildContext context) {
  registerBundledThirdPartyLicenses();
  final navigator = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final locale = Localizations.localeOf(context);

  navigator.push(
    MaterialPageRoute<void>(
      builder: (context) => themes.wrap(
        Localizations.override(
          context: context,
          locale: locale,
          delegates: const [DefaultMaterialLocalizations.delegate],
          child: const LicensePage(),
        ),
      ),
    ),
  );
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
        'packages/rohd_schematic_viewer/assets/licenses/elkjs_LICENSES.txt',
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

  const _BundledLicense({required this.packageName, required this.assetPath});
}
