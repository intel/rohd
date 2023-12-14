// Copyright (C) 2023 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// unsupported_type_exception.dart
// An exception that is thrown when an unsupported type is used.
//
// 2023 September 14
// Author: Max Korbel <max.korbel@intel.com

import 'package:rohd/src/exceptions/rohd_exception.dart';

/// An exception that is thrown when an unsupported type is used.
class UnsupportedTypeException extends RohdException {
  /// Creates an exception when an unsupported type is used.
  UnsupportedTypeException(dynamic value, List<Type> supportedTypes)
      : super('Unsupported type ${value.runtimeType} used ($value).'
            ' Supported types are ${supportedTypes.join(',')}');
}
