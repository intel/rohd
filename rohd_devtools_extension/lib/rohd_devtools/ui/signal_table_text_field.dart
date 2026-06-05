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

/// A text field widget for filtering signals in the signal table.
///
/// Supports regex patterns (indicated by hint text). Includes a prefix
/// filter icon and a clear button that appears when text is entered.
class SignalTableTextField extends StatefulWidget {
  /// The label text for the text field.
  final String labelText;

  /// Callback when the text field value changes.
  final ValueChanged<String> onChanged;

  /// Creates a [SignalTableTextField] with the given label and change callback.
  const SignalTableTextField({
    required this.labelText,
    required this.onChanged,
    super.key,
  });

  @override
  State<SignalTableTextField> createState() => _SignalTableTextFieldState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('labelText', labelText))
      ..add(
        ObjectFlagProperty<ValueChanged<String>>.has('onChanged', onChanged),
      );
  }
}

class _SignalTableTextFieldState extends State<SignalTableTextField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: SizedBox(
        height: 32,
        child: TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black,
          ),
          decoration: InputDecoration(
            hintText: '${widget.labelText} (regex supported)',
            hintStyle: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            prefixIcon: Icon(
              Icons.filter_list,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 16,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  onPressed: _clear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                );
              },
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: isDark ? Colors.white24 : Colors.black12,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: isDark ? Colors.white24 : Colors.black12,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
          ),
        ),
      ),
    );
  }
}
