// Copyright (C) 2024-2025 Intel Corporation
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
  PortRulesViolationException(Module module, String signal,
      [String additionalMessage = ''])
      : super('Violation of input/output rules in $module on $signal.'
            ' Logic within a Module should only communicate outside of itself'
            ' by consuming inputs/inouts and'
            ' driving outputs/inouts of that itself.'
            ' See https://intel.github.io/rohd-website/docs/modules/'
            ' for more information. $additionalMessage');

  PortRulesViolationException.trace({
    required Module module,
    required Logic signal,
    required PortRulesViolationException lowerException,
  }) : super('''
$lowerException
@ Module $module
  on ${_getSignalDescription(signal)} \t $signal
  of ${signal.parentModule == null ? 'undetermined sub-module' : 'sub-module\t${signal.parentModule!}'}''');

  static String _getSignalDescription(Logic signal) {
    if (signal.isPort) {
      if (signal.isInput) {
        return 'input  port';
      } else if (signal.isOutput) {
        return 'output port';
      } else {
        return 'inout  port';
      }
    } else {
      return 'internal signal';
    }
  }
}
