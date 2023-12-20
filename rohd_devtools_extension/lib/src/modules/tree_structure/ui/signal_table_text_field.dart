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
