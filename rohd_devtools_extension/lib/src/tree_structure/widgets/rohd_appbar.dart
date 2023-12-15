import 'package:flutter/material.dart';

class RohdAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RohdAppBar({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.onPrimary,
      title: const Text('ROHD DevTools Extension'),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
