// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// cross_probe_menu.dart
// Shared helpers for building generalized "Go to <format> Source" cross-probe
// context-menu items across all viewers (wave, schematic, details).
//
// Viewers consult an [AvailableSourceFormats] query (backed by the cached
// ROHD extension module info) to discover which source languages are
// navigable, then build menu items via [buildGotoSourceMenuItems].  A single
// [GoToSourceCallback] handles the selection for every format, and the
// secondary frame picker (when a signal resolves to multiple frames) works
// uniformly for all formats.
//
// 2026 June
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

import 'rohd_extension_status.dart';

/// Returns the source formats currently navigable for the active module.
///
/// Must be synchronous (reads cached module info) so it can be consulted
/// while a popup menu is being built.
typedef AvailableSourceFormats = List<RohdSourceFormat> Function();

/// Invoked when the user picks `Go to <format> Source` for [signalPaths].
typedef GoToSourceCallback = void Function(
    RohdSourceFormat format, List<String> signalPaths);

/// Builds an icon for a source/output [format].
typedef SourceFormatIconBuilder = Widget Function(
  RohdSourceFormat format, {
  double size,
});

/// Prefix used to encode source-navigation entries in a `String`-valued popup
/// menu (e.g. `'goto_source:rohd'`).  Allows the shared items to coexist with
/// each viewer's other `String` menu values.
const String _gotoSourceValuePrefix = 'goto_source:';

/// Formats shown when source availability is unknown (module info not yet
/// loaded, the extension is unreachable, or the query errored).
const List<RohdSourceFormat> kDefaultNavigableFormats = [
  RohdSourceFormat.rohd,
  RohdSourceFormat.sv,
];

/// Encode a popup-menu value for navigating to [format].
String gotoSourceMenuValue(RohdSourceFormat format) =>
    '$_gotoSourceValuePrefix${format.name}';

/// Decode a popup-menu value produced by [gotoSourceMenuValue].
///
/// Returns `null` when [value] is not a Go-to-Source entry, so callers can
/// fall through to handling their own menu values.
RohdSourceFormat? gotoSourceFormatFromValue(String? value) {
  if (value == null || !value.startsWith(_gotoSourceValuePrefix)) {
    return null;
  }
  final name = value.substring(_gotoSourceValuePrefix.length);
  for (final f in RohdSourceFormat.values) {
    if (f.name == name) {
      return f;
    }
  }
  return null;
}

/// Short, menu-friendly name for [format] (e.g. `'ROHD'`, `'SV'`).
String gotoSourceShortName(RohdSourceFormat format) => switch (format) {
      RohdSourceFormat.rohd => 'ROHD',
      RohdSourceFormat.sv => 'SV',
      RohdSourceFormat.sc => 'SystemC',
      RohdSourceFormat.fst => 'Waveform',
    };

/// Menu label for `Go to <format> Source`, pluralized with [count].
String gotoSourceMenuLabel(RohdSourceFormat format, {int count = 1}) {
  final name = gotoSourceShortName(format);
  return count <= 1 ? 'Go to $name Source' : 'Go to $name Source ($count)';
}

const _rohdIconAsset = 'assets/rohd_icon.png';
const _systemVerilogIconAsset = 'assets/systemverilog_icon.png';
const _systemCIconAsset = 'assets/systemc_icon.png';

/// App-bar-style icon for a source/output [format].
Widget sourceFormatMenuIcon(RohdSourceFormat format, {double size = 18}) =>
    switch (format) {
      RohdSourceFormat.rohd => _sourceFormatAssetIcon(
          _rohdIconAsset,
          semanticLabel: 'ROHD Source',
          size: size,
        ),
      RohdSourceFormat.sv => _sourceFormatAssetIcon(
          _systemVerilogIconAsset,
          semanticLabel: 'SystemVerilog Source',
          size: size,
        ),
      RohdSourceFormat.sc => _sourceFormatAssetIcon(
          _systemCIconAsset,
          semanticLabel: 'SystemC Source',
          size: size,
        ),
      RohdSourceFormat.fst => Icon(Icons.timeline, size: size),
    };

/// Backwards-compatible alias for [sourceFormatMenuIcon].
Widget sourceFormatIcon(RohdSourceFormat format, {double size = 18}) =>
    sourceFormatMenuIcon(format, size: size);

Widget _sourceFormatAssetIcon(
  String asset, {
  required String semanticLabel,
  required double size,
}) =>
    Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final image = Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: semanticLabel,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            asset,
            package: 'rohd_devtools_widgets',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: semanticLabel,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.code, size: size),
          ),
        );

        if (!isDark) return image;

        return Container(
          width: size + 4,
          height: size + 4,
          decoration: const BoxDecoration(
            color: Color(0xFFE0E0E0),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(2),
          child: image,
        );
      },
    );

/// Standard popup-menu row with a fixed-width prefix icon and ellipsized label.
Widget sourcePopupMenuRow({
  required Widget icon,
  required String label,
  TextStyle? textStyle,
  double iconSlotWidth = 22,
  double gap = 8,
}) =>
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: iconSlotWidth,
          child: Center(child: icon),
        ),
        SizedBox(width: gap),
        Flexible(
          child: Text(label, style: textStyle, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

/// Standard popup-menu item using the same fixed icon gutter as source rows.
PopupMenuItem<T> buildRohdPopupMenuItem<T>({
  required T value,
  required Widget icon,
  required String label,
  double height = 32,
  TextStyle? textStyle,
  bool enabled = true,
}) =>
    PopupMenuItem<T>(
      value: value,
      height: height,
      enabled: enabled,
      child: sourcePopupMenuRow(
        icon: icon,
        label: label,
        textStyle: textStyle,
      ),
    );

/// Compact strip of source/output format icons for trace-picker menu rows.
Widget sourceFormatIconStrip({
  required Iterable<RohdSourceFormat> formats,
  SourceFormatIconBuilder iconBuilder = sourceFormatMenuIcon,
  double size = 16,
  double gap = 3,
}) {
  final formatList = formats.toList(growable: false);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < formatList.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        iconBuilder(formatList[i], size: size),
      ],
    ],
  );
}

/// Resolve which navigable source formats to display for [info].
///
/// When [info] is `null`, the extension is unavailable, or the query errored,
/// availability is treated as *unknown* and [kDefaultNavigableFormats] is
/// returned so the actions stay available while metadata converges.
/// Otherwise the exact set of usable navigable formats is returned (which may
/// be empty when the module genuinely has no source).
List<RohdSourceFormat> resolveNavigableFormats(RohdModuleInfo? info) {
  if (info == null || !info.extensionAvailable || info.error != null) {
    return kDefaultNavigableFormats;
  }
  return info.navigableSourceFormats;
}

/// Build `Go to <format> Source` popup-menu items for [formats].
///
/// Each item carries a value encoded by [gotoSourceMenuValue]; decode the
/// chosen value with [gotoSourceFormatFromValue] in the menu's result handler.
List<PopupMenuItem<String>> buildGotoSourceMenuItems({
  required List<RohdSourceFormat> formats,
  int count = 1,
  double height = 32,
  TextStyle? textStyle,
  bool showIcons = true,
  SourceFormatIconBuilder iconBuilder = sourceFormatMenuIcon,
}) =>
    [
      for (final format in formats)
        buildRohdPopupMenuItem<String>(
          value: gotoSourceMenuValue(format),
          height: height,
          icon: showIcons ? iconBuilder(format) : const SizedBox.shrink(),
          label: gotoSourceMenuLabel(format, count: count),
          textStyle: textStyle,
        ),
    ];
