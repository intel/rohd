// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// main.dart
// Entry point for main application.
//
// 2024 January 5
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/modules/rohd_devtools_module.dart';

void main() {
  runApp(const ProviderScope(
    child: RohdDevToolsModule(),
  ));
}
