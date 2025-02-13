// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_table_text_field.dart
// UI for signal table text field.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';

class SignalTableTextField extends StatelessWidget {
  final String labelText;
  final ValueChanged<String> onChanged;

  const SignalTableTextField({
    super.key,
    required this.labelText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: labelText,
        ),
      ),
    );
  }
}
