// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cross_probe_button.dart
// Toolbar button for toggling cross-probing between viewers.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';
import 'cross_probe_service.dart';

/// A toolbar icon button for cross-probing signal selections between viewers.
///
/// Displays a bidirectional arrows icon ([Icons.compare_arrows]).  Tap to
/// toggle cross-probing on or off via [CrossProbeService.isActive].
///
/// When active the icon is rendered in the theme's primary colour; when
/// inactive it uses the theme's disabled colour.
class CrossProbeButton extends StatelessWidget {
  /// The cross-probe service whose [CrossProbeService.isActive] state is
  /// reflected by this button.
  final CrossProbeService service;

  /// Creates a [CrossProbeButton] for the given [service].
  const CrossProbeButton({required this.service, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: service.isActive,
      builder: (context, active, _) {
        final color = active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).disabledColor;
        return Tooltip(
          message: active
              ? 'Cross-probing active — tap to disable'
              : 'Cross-probing disabled — tap to enable',
          child: IconButton(
            icon: Icon(Icons.compare_arrows, color: color),
            onPressed: () => service.isActive.value = !service.isActive.value,
          ),
        );
      },
    );
  }
}
