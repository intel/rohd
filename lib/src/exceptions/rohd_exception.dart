/// Copyright (C) 2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// rohd_exception.dart
/// Base class for all ROHD exceptions
///
/// 2022 December 30
/// Author: Max Korbel <max.korbel@intel.com>
///

/// A base type of exception that ROHD-specific exceptions inherit from.
abstract class RohdException implements Exception {
  /// A description of what this exception means.
  final String message;

  /// Creates a new exception with description [message].
  RohdException(this.message);

  @override
  String toString() => message;
}
