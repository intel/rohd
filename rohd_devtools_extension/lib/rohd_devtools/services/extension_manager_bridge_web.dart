// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// extension_manager_bridge_web.dart
// Web extension manager bridge implementation.
//
// 2026 September 15
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:devtools_extensions/devtools_extensions.dart';

/// Sets whether the embedding DevTools extension uses a dark theme.
void setExtensionDarkThemeEnabled({required bool enabled}) {
  extensionManager.darkThemeEnabled.value = enabled;
}
