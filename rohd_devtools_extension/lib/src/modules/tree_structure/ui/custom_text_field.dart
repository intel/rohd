import 'package:flutter/material.dart';

class DetailsCardTableTextField extends StatelessWidget {
  final String labelText;
  final ValueChanged<String> onChanged;

  const DetailsCardTableTextField({
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
