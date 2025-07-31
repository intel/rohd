// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port.dart
// Definition of Port.
//
// 2023 May 30
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

/// An extension of [Logic] which performs some additional validation for
/// inputs and outputs of [Module]s.
///
/// Useful for [Interface] definitions.
@Deprecated('Use `Logic.port` instead.')
class Port extends Logic {
  /// Constructs a [Logic] intended to be used for ports of a [Module] or
  /// in an [Interface].
  @Deprecated('Use `Logic.port` instead.')
  Port(String name, [int width = 1])
      : super(
          name: name,
          width: width,

          // make port names mergeable so we don't duplicate the ports
          // when calling connectIO
          naming: Naming.mergeable,
        ) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }
  }

  @override
  Logic clone({String? name}) => Port(name ?? this.name, width);
}
