// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// export_toast.dart
// Overlay-based toast that works without a Scaffold ancestor.
//
// 2026 April
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:async';

import 'package:flutter/material.dart';

/// Show a brief floating toast at the bottom of the screen.
///
/// Works without a [Scaffold] ancestor by inserting directly into the
/// root [Overlay].  Auto-removes after [duration].
void showExportToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade800,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(duration, entry.remove);
}
