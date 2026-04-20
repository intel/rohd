// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// export_button.dart
// Reusable camera-icon button for PNG export.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

/// Small camera-icon button for triggering PNG export.
///
/// Designed to be placed in a [Positioned] overlay.  Calls [onPressed]
/// when tapped.
class ExportPngButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const ExportPngButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Export as PNG',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surface.withAlpha(200),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.camera_alt_outlined,
              size: 20,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
