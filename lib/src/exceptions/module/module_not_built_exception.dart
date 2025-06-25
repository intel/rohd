// Copyright (C) 2022-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_not_build_exception.dart
// Definition for exception when module is not built
//
// 2022 December 30
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a [Module] was used in a way that required it
/// to be built first, but it was not yet built.
class ModuleNotBuiltException extends RohdException {
  /// Constructs a new [Exception] for when a [Module] should have been built
  /// before some action was taken.
  ModuleNotBuiltException(Module module, [String? additionalInformation])
      : super([
          'Module $module has not yet built! Must call build() first.',
          additionalInformation
        ].nonNulls.join(' '));
}
