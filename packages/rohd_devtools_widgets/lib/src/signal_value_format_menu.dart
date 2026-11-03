// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_value_format_menu.dart
// Shared display-format menu for signal occurrence surfaces.
//
// 2026 September 29
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_widgets/src/cross_probe_menu.dart'
    show buildRohdPopupMenuItem;
import 'package:rohd_devtools_widgets/src/signal_value_format_registry.dart';
import 'package:rohd_hierarchy/rohd_hierarchy.dart' show OccurrenceAddress;

/// Popup-menu value used to open the signal display-format submenu.
const signalValueFormatMenuValue = 'signal_format_as';

/// Builds the command that opens the signal display-format submenu.
PopupMenuItem<String> buildSignalValueFormatMenuItem({required int count}) =>
    buildRohdPopupMenuItem<String>(
      value: signalValueFormatMenuValue,
      icon: const Icon(Icons.numbers, size: 16),
      label: count == 1 ? 'Format As' : 'Format $count Signals As',
      textStyle: const TextStyle(fontSize: 13),
    );

/// Shows signal display-format choices and returns the selected format.
///
/// When [addresses] is non-empty, the shared format registry is updated before
/// the selected value is returned.
Future<SignalValueFormat?> showSignalValueFormatMenu(
  BuildContext context, {
  required Offset globalPosition,
  Iterable<OccurrenceAddress?> addresses = const [],
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final selectedFormat = await showMenu<SignalValueFormat>(
    context: context,
    position: RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlay.size.width - local.dx,
      overlay.size.height - local.dy,
    ),
    items: SignalValueFormat.values
        .map(
          (format) => buildRohdPopupMenuItem<SignalValueFormat>(
            value: format,
            icon: Icon(_iconFor(format), size: 16),
            label: _labelFor(format),
            textStyle: const TextStyle(fontSize: 13),
          ),
        )
        .toList(),
  );
  if (selectedFormat == null) {
    return null;
  }
  final resolvedAddresses = addresses.whereType<OccurrenceAddress>().toList();
  if (resolvedAddresses.isNotEmpty) {
    SignalValueFormatRegistry.setFormatFor(
      resolvedAddresses,
      selectedFormat,
    );
  }
  return selectedFormat;
}

String _labelFor(SignalValueFormat format) => switch (format) {
      SignalValueFormat.waveform => 'Waveform Default',
      SignalValueFormat.binary => 'Binary',
      SignalValueFormat.hexadecimal => 'Hexadecimal',
      SignalValueFormat.unsignedDecimal => 'Unsigned Decimal',
      SignalValueFormat.signedDecimal => 'Signed Decimal',
      SignalValueFormat.octal => 'Octal',
      SignalValueFormat.ascii => 'ASCII',
    };

IconData _iconFor(SignalValueFormat format) => switch (format) {
      SignalValueFormat.waveform => Icons.timeline,
      SignalValueFormat.binary => Icons.looks_one,
      SignalValueFormat.hexadecimal => Icons.tag,
      SignalValueFormat.unsignedDecimal => Icons.pin,
      SignalValueFormat.signedDecimal => Icons.plus_one,
      SignalValueFormat.octal => Icons.filter_8,
      SignalValueFormat.ascii => Icons.text_fields,
    };
