// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// app.dart
// Main app
//
// 2025 January 28

import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/rohd_devtools/rohd_devtools.dart';

class RohdDevToolsApp extends MaterialApp {
  const RohdDevToolsApp({
    super.key,
  }) : super(home: const RohdDevToolsPage());
}
