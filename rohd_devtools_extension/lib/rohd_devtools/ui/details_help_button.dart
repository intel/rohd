// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// details_help_button.dart
// Help button widget for the Details tab.
//
// Content is loaded from assets/help/details_help.md.
// Edit that markdown file to update hover tooltip and dialog content.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// A help button for the Details tab.
///
/// Content is driven by `assets/help/details_help.md`.
/// Edit that file to update the hover tooltip and click-open dialog.
class DetailsHelpButton extends StatelessWidget {
  /// Whether the current theme is dark mode.
  final bool isDark;

  /// Create a [DetailsHelpButton].
  const DetailsHelpButton({required this.isDark, super.key});

  @override
  Widget build(BuildContext context) => MarkdownHelpButton(
        assetPath: 'assets/help/details_help.md',
        isDark: isDark,
      );
}
