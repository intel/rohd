// Copyright (C) 2021-2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// name_validator.dart
// Performs validation on naming.
//
// 2023 October 24

import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';

//TODO: make this file generic naming stuff instead (including unpreferred, LogicNaming->Naming, etc.)

/// Utilities for name validation.
abstract class NameValidator {
  /// Returns [name] if it meets requirements for the specified [reserveName],
  /// otherwise throws an [Exception].
  static String? validatedName(String? name, {required bool reserveName}) {
    if (reserveName) {
      if (name == null) {
        throw NullReservedNameException();
      } else if (name.isEmpty) {
        throw EmptyReservedNameException();
      } else if (!Sanitizer.isSanitary(name!)) {
        throw InvalidReservedNameException();
      }
    }

    return name;
  }
}
