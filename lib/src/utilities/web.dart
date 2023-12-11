// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// web.dart
// Utilities for running ROHD on the web or in JavaScript.
//
// 2023 December 8
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// Borrowed from Flutter's implementation to determine whether Dart is
/// compiled to run on the web.  This is relevant for ROHD because when the
/// code is compiled to JavaScript, it affects the ability for [LogicValue]
/// to store different sizes of data in different implementations.
///
/// See more details here:
/// https://api.flutter.dev/flutter/foundation/kIsWeb-constant.html
// ignore: do_not_use_environment
const bool kIsWeb = bool.fromEnvironment('dart.library.js_util');
