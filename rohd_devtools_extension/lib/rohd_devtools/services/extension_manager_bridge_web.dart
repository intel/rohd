// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// extension_manager_bridge_web.dart
//
// 2026 October 17
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:devtools_app_shared/utils.dart' show globals;
import 'package:devtools_extensions/devtools_extensions.dart';

/// Sets whether the embedding DevTools extension uses a dark theme.
///
/// Does nothing before a DevTools extension host initializes its
/// [ExtensionManager], such as in standalone web mode.
void setExtensionDarkThemeEnabled({required bool enabled}) {
  final manager = globals[ExtensionManager] as ExtensionManager?;
  manager?.darkThemeEnabled.value = enabled;
}
