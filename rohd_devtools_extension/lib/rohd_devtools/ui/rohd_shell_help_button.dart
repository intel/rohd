// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_shell_help_button.dart
// Help button for the target-backed ROHD debug shell.

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';

/// A help button for the ROHD debug shell command reference.
class RohdShellHelpButton extends StatelessWidget {
  /// Creates a shell command reference button.
  const RohdShellHelpButton({
    required this.isDark,
    this.hasColorEmoji = true,
    super.key,
  });

  /// Whether the current theme is dark mode.
  final bool isDark;

  /// Whether color emoji rendering is available on this platform.
  final bool hasColorEmoji;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<bool>('isDark', isDark))
      ..add(DiagnosticsProperty<bool>('hasColorEmoji', hasColorEmoji));
  }

  @override
  Widget build(BuildContext context) => MarkdownHelpButton(
        assetPath: 'assets/help/rohd_shell_help.md',
        isDark: isDark,
        labelIcon: hasColorEmoji
            ? null
            : Icon(
                Icons.help_outline,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
      );
}
