// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// source_frame_picker.dart
// Popup menu for selecting a source frame from an enriched trace.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:material_ui/material_ui.dart';
import 'package:rohd_devtools_extension/rohd_devtools/services/source_navigation_service.dart';
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart'
    show RohdSourceFormat, sourceFormatMenuIcon;

/// Text style used for the frame label (`file:line`).
const TextStyle _kLabelTextStyle = TextStyle(fontSize: 13);

/// Text style used for the highlight chip (enclosing symbol).
const TextStyle _kHighlightTextStyle = TextStyle(
  fontSize: 10,
  fontStyle: FontStyle.italic,
);

/// Horizontal padding inside each menu item (matches [PopupMenuItem.padding]).
const double _kItemHorizontalPadding = 12;

/// Horizontal padding inside the small type/highlight chips.
const double _kChipHorizontalPadding = 4;

/// Gap between the type tag and the label.
const double _kTagToLabelGap = 8;

/// Fixed width reserved for the source-format icon.
const double _kIconSlotWidth = 22;

/// Gap between the label and the highlight chip.
const double _kLabelToHighlightGap = 6;

/// Last known global pointer-down position, updated by
/// [SourceFramePointerTracker].
Offset? _lastGlobalPointerDown;

/// A widget that wraps part of the tree to track the last pointer-down
/// position.  Place this above the area that triggers Go to Source menus.
class SourceFramePointerTracker extends StatelessWidget {
  final Widget _child;

  /// Creates a pointer tracker for source-frame menus.
  const SourceFramePointerTracker({required Widget child, super.key})
      : _child = child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _lastGlobalPointerDown = event.position;
        },
        child: _child,
      );
}

/// Shows a popup menu of enriched source frames and returns the selected
/// index, or `null` if the user dismissed the menu.
///
/// If there is only one frame, returns `0` immediately without showing
/// a picker.
///
/// When [position] is not provided, the menu appears at the last known
/// pointer-down position (tracked by [SourceFramePointerTracker]).
Future<int?> showSourceFramePicker(
  BuildContext context,
  List<EnrichedFrame> frames, {
  Offset? position,
}) async {
  if (frames.isEmpty) {
    return null;
  }
  if (frames.length == 1) {
    return 0;
  }

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) {
    return null;
  }

  // Use provided position, or last tracked pointer-down, or overlay centre.
  final pos = position ??
      _lastGlobalPointerDown ??
      overlay.localToGlobal(
        Offset(overlay.size.width / 2, overlay.size.height / 2),
      );

  final rel = RelativeRect.fromSize(
    Rect.fromLTWH(pos.dx, pos.dy, 0, 0),
    overlay.size,
  );

  // Size the menu to fit the widest item (type tag + label + highlight) so the
  // filename and enclosing symbol are not truncated, clamped to the available
  // overlay width so it never runs off-screen.
  final maxAllowedWidth = (overlay.size.width - 32).clamp(0.0, double.infinity);
  final contentWidth = _computeMenuContentWidth(context, frames);
  final minWidth = contentWidth.clamp(0.0, maxAllowedWidth);

  final selected = await showMenu<int>(
    context: context,
    position: rel,
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxAllowedWidth),
    items: [
      for (var i = 0; i < frames.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 32,
          padding: const EdgeInsets.symmetric(
            horizontal: _kItemHorizontalPadding,
          ),
          child: _FrameMenuItem(frame: frames[i]),
        ),
    ],
  );
  return selected;
}

/// Measures the rendered width of [text] in [style], honouring the ambient
/// text scaler.
double _measureTextWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// Computes the width needed to display the widest menu item without
/// truncation: type tag chip + label + optional highlight chip, plus the
/// inter-element gaps and the item's own horizontal padding.
double _computeMenuContentWidth(
  BuildContext context,
  List<EnrichedFrame> frames,
) {
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;

  for (final frame in frames) {
    final hl = frame.highlight;

    // Source icon + gap + label.
    var width = _kIconSlotWidth;
    width += _kTagToLabelGap +
        _measureTextWidth(frame.label, _kLabelTextStyle, scaler);

    // Optional highlight chip: gap + text + chip padding on both sides.
    if (hl != null) {
      width += _kLabelToHighlightGap +
          _measureTextWidth(hl, _kHighlightTextStyle, scaler) +
          (_kChipHorizontalPadding * 2);
    }

    if (width > widest) {
      widest = width;
    }
  }

  // Add the item's horizontal padding (both sides) plus a small buffer for
  // chip borders and sub-pixel rounding.
  return widest + (_kItemHorizontalPadding * 2) + 4;
}

class _FrameMenuItem extends StatelessWidget {
  final EnrichedFrame _frame;

  const _FrameMenuItem({required EnrichedFrame frame}) : _frame = frame;

  @override
  Widget build(BuildContext context) {
    final hl = _frame.highlight;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _kIconSlotWidth,
          child: Center(child: sourceFormatMenuIcon(_formatOf(_frame))),
        ),
        const SizedBox(width: _kTagToLabelGap),
        Flexible(
          child: Text(
            _frame.label,
            style: _kLabelTextStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hl != null) ...[
          const SizedBox(width: _kLabelToHighlightGap),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _kChipHorizontalPadding,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: Colors.yellow.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              hl,
              style: _kHighlightTextStyle.copyWith(color: Colors.amber),
            ),
          ),
        ],
      ],
    );
  }

  RohdSourceFormat _formatOf(EnrichedFrame frame) {
    for (final format in RohdSourceFormat.values) {
      if (format.name == frame.frame.type) {
        return format;
      }
    }
    return RohdSourceFormat.rohd;
  }
}
