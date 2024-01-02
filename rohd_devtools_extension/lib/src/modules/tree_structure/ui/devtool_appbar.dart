import 'package:flutter/material.dart';

class DevtoolAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DevtoolAppBar({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.onPrimary,
      title: const Row(
        children: [
          Icon(Icons.build),
          SizedBox(width: 5),
          Text('ROHD DevTool (Beta)'),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
