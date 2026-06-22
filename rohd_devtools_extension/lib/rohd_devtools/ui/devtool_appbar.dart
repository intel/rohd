// Copyright (C) 2024-2025 Intel Corporation
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
      title: const Text('ROHD DevTool (Beta)'),
      leading: const Icon(Icons.build),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 20.0),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                showLicensePage(context: context);
              },
              child: const Text(
                'Licenses',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
