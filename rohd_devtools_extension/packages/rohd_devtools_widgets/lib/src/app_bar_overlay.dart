// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app_bar_overlay.dart
// Auto-hiding overlay AppBar that slides in from the top edge.
//
// When [autoHide] is true, the bar slides out of view and reappears when
// the mouse enters a thin trigger zone along the top edge.  When [autoHide]
// is false the bar behaves like a normal AppBar (always visible, pushes
// content down).
//
// Designed to be reusable across ROHD Wave Viewer, Schematic Viewer, etc.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:flutter/material.dart';

/// Wraps a [body] widget and an [appBar] widget, where the AppBar
/// auto-hides by sliding up when [autoHide] is true.
///
/// When [autoHide] is false the layout is a simple Column (AppBar + body),
/// matching normal Scaffold behaviour.
class AppBarOverlay extends StatefulWidget {
  /// The AppBar-like widget to show/hide.
  final PreferredSizeWidget appBar;

  /// The main content below the AppBar.
  final Widget body;

  /// When true, the AppBar auto-hides and slides in on mouse hover.
  /// When false, the AppBar is always visible.
  final bool autoHide;

  /// Height of the invisible trigger zone along the top edge (pixels).
  final double triggerHeight;

  /// Opacity of the overlay AppBar when shown (0.0–1.0).
  final double panelOpacity;

  /// Duration of the slide animation.
  final Duration animationDuration;

  const AppBarOverlay({
    super.key,
    required this.appBar,
    required this.body,
    this.autoHide = false,
    this.triggerHeight = 12,
    this.panelOpacity = 0.92,
    this.animationDuration = const Duration(milliseconds: 200),
  });

  @override
  State<AppBarOverlay> createState() => _AppBarOverlayState();
}

class _AppBarOverlayState extends State<AppBarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1), // fully off-screen above
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    // If not auto-hiding, snap open.
    if (!widget.autoHide) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppBarOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.autoHide && oldWidget.autoHide) {
      // Switched from auto-hide → always visible: snap open.
      _controller.forward();
    } else if (widget.autoHide && !oldWidget.autoHide) {
      // Switched from always visible → auto-hide: hide immediately.
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show() {
    _controller.forward();
  }

  void _hide() {
    if (!widget.autoHide) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // ── When not auto-hiding, simple column layout ──
    if (!widget.autoHide) {
      return Column(
        children: [
          widget.appBar,
          Expanded(child: widget.body),
        ],
      );
    }

    // ── Auto-hide mode: overlay with trigger zone ──
    final appBarHeight =
        widget.appBar.preferredSize.height + MediaQuery.of(context).padding.top;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Body fills the entire area (no top inset — content goes edge-to-edge)
        Positioned.fill(child: widget.body),

        // Trigger zone: thin invisible strip along the top edge
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: widget.triggerHeight,
          child: MouseRegion(
            onEnter: (_) => _show(),
            opaque: false, // let clicks through when AppBar is hidden
            child: const SizedBox.expand(),
          ),
        ),

        // Sliding overlay AppBar
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: appBarHeight,
          child: SlideTransition(
            position: _slideAnimation,
            child: MouseRegion(
              onEnter: (_) => _show(),
              onExit: (_) => _hide(),
              child: Opacity(
                opacity: widget.panelOpacity,
                child: widget.appBar,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
