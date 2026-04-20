// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtools_help_button.dart
// Help button widget for the ROHD DevTools app bar.
//
// Content is loaded from assets/help/devtools_help.md.
// Edit that markdown file to update hover tooltip and dialog content.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// A help button for the ROHD DevTools app bar.
///
/// Content is driven by `assets/help/devtools_help.md`.
/// Edit that file to update the hover tooltip and click-open dialog.
class DevToolsHelpButton extends StatelessWidget {
  /// Whether the current theme is dark mode.
  final bool isDark;

  /// Create a [DevToolsHelpButton].
  const DevToolsHelpButton({required this.isDark, super.key});

  @override
  Widget build(BuildContext context) => MarkdownHelpButton(
        assetPath: 'assets/help/devtools_help.md',
        isDark: isDark,
      );
}
