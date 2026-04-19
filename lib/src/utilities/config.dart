// Copyright (C) 2022-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// config.dart
// A configuration file of ROHD.
//
// 2022 December 1
// Author: Yao Jing Quek <yao.jing.quek@intel.com>

/// A utility for ROHD configuration file.
class Config {
  /// The version of the ROHD framework.
  static const String version = '0.6.8';

  /// Controls whether synthesized signal names and instance names must be
  /// unique across both namespaces.
  ///
  /// When `true`, central naming cross-checks both namespaces during
  /// allocation to avoid collisions in generated output.
  ///
  /// When `false`, signal and instance names are uniquified independently.
  static bool ensureUniqueSignalAndInstanceNames = true;
}
