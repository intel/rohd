// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_website_button.dart
// App bar logo linking to the ROHD website.
//
// 2026 November 10
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/utils/browser_window.dart';

/// The ROHD project website.
const rohdWebsiteUrl = 'https://intel.github.io/rohd-website/';

/// An app bar logo that opens the ROHD website.
class RohdWebsiteButton extends StatelessWidget {
  /// Opens a URL in the user's browser.
  final ValueChanged<String> openUrl;

  /// Creates a clickable ROHD logo.
  const RohdWebsiteButton({super.key, this.openUrl = openBrowserTab});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Open ROHD website',
        onPressed: () => openUrl(rohdWebsiteUrl),
        icon: Image.asset(
          'assets/rohd_icon.png',
          width: 28,
          height: 28,
          fit: BoxFit.contain,
        ),
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<ValueChanged<String>>.has(
      'openUrl',
      openUrl,
    ));
  }
}
