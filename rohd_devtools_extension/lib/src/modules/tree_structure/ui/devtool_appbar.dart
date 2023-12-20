import 'package:flutter/material.dart';

class DevtoolAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DevtoolAppBar({
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
