// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table_text_field.dart
// UI for signal table text field.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Text field used to filter or search within the signal table.
class SignalTableTextField extends StatelessWidget {
  /// The label shown inside the text field.
  final String labelText;

  /// Called whenever the text changes.
  final ValueChanged<String> onChanged;

  /// Creates a signal table text field.
  const SignalTableTextField({
    required this.labelText,
    required this.onChanged,
    super.key,
  });

  /// Builds the text field wrapped in an [Expanded] widget.
  @override
  Widget build(BuildContext context) => Expanded(
        child: TextField(
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: labelText,
          ),
        ),
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('labelText', labelText))
      ..add(ObjectFlagProperty<ValueChanged<String>>(
        'onChanged',
        onChanged,
        ifNull: 'disabled',
      ));
  }
}
