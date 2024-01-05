// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// devtool_appbar.dart
// UI for rohd devtool appbar.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

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
