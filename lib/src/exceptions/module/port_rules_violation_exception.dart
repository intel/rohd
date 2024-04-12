// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_rules_violation_exception.dart
// Definition for exception when port rules are not followed.
//
// 2024 April 12
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a port is not following the input/output rules.
class PortRulesViolationException extends RohdException {
  /// Constructs a new [Exception] for when port rules are not present on
  /// [module] for [signal].
  PortRulesViolationException(Module module, String signal)
      : super('Violation of input/output rules in $module on $signal.'
            ' Logic within a Module should only consume inputs/inouts and'
            ' drive outputs/inouts of that Module.'
            ' See https://intel.github.io/rohd-website/docs/modules/'
            ' for more information.');
}
