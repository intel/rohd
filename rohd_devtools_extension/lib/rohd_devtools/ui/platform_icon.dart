// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// platform_icon.dart
// Provides platform-aware icon rendering with emoji fallback.
//
// 2026 January
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A widget that renders either a Material Icon or emoji text based on
/// platform emoji font availability.
///
/// On platforms with color emoji support, uses the provided emoji string.
/// On platforms without (or with `hasColorEmoji: false`), falls back to
/// the Material IconData.
class PlatformIcon extends StatelessWidget {
  /// Material IconData to use as fallback on platforms without color emoji
  final IconData nativeIcon;

  /// Emoji string to display if color emoji fonts are available
  final String emoji;

  /// Size of the icon/emoji (defaults to 16)
  final double? size;

  /// Color to apply to the icon/emoji
  final Color? color;

  /// Whether color emoji fonts are available on this platform
  /// (defaults to true - verify on native platforms)
  final bool hasColorEmoji;

  /// Constructor for [PlatformIcon].
  const PlatformIcon(
    this.nativeIcon,
    this.emoji, {
    this.size,
    this.color,
    this.hasColorEmoji = true,
    super.key,
  });

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<IconData>('nativeIcon', nativeIcon))
      ..add(StringProperty('emoji', emoji))
      ..add(DoubleProperty('size', size))
      ..add(ColorProperty('color', color))
      ..add(
        FlagProperty(
          'hasColorEmoji',
          value: hasColorEmoji,
          ifFalse: 'using fallback icons',
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (hasColorEmoji) {
      return Text(
        emoji,
        style: TextStyle(fontSize: size ?? 16, color: color),
      );
    }
    return Icon(nativeIcon, size: size, color: color);
  }
}

/// Helper function for quick construction of PlatformIcon widgets.
///
/// Returns a PlatformIcon widget that renders either emoji or Material icon
/// based on platform capabilities.
///
/// Example:
/// ```dart
/// platformIcon(Icons.waves, '🔗', size: 24, hasColorEmoji: true)
/// ```
Widget platformIcon(
  IconData nativeIcon,
  String emoji, {
  double? size,
  Color? color,
  bool hasColorEmoji = true,
}) =>
    PlatformIcon(
      nativeIcon,
      emoji,
      size: size,
      color: color,
      hasColorEmoji: hasColorEmoji,
    );

/// Check whether a color emoji font (Noto Color Emoji) is installed on the
/// system. Returns true on web (always has emoji), or checks fc-list on Linux.
Future<bool> isEmojiFontInstalled() async {
  if (kIsWeb) {
    return true; // Web always has color emoji
  }

  try {
    final result = await Process.run('fc-list', []);
    if (result.exitCode == 0) {
      final out = result.stdout.toString().toLowerCase();
      return out.contains('noto color emoji');
    }
  } on Exception {
    // fc-list command not available or failed; assume no emoji font
  }
  return false;
}
