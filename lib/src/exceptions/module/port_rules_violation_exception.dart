// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_rules_violation_exception.dart
// Definition for exception when port rules are not followed.
//
// 2024 April 12
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// An [Exception] thrown when a port is not following the input/output rules.
class PortRulesViolationException extends RohdException {
  final Module module;

  /// Constructs a new [Exception] for when port rules are not present on
  /// [module] for [signal].
  PortRulesViolationException(this.module, String signal,
      [String additionalMessage = ''])
      : super('Violation of input/output rules'
            ' in module $module on signal $signal.'
            ' Logic within a Module should only communicate outside of itself'
            ' by consuming inputs/inouts and'
            ' driving outputs/inouts of that itself.'
            ' See https://intel.github.io/rohd-website/docs/modules/'
            ' for more information. $additionalMessage');

  //TODO doc
  @internal
  PortRulesViolationException.trace({
    required this.module,
    required Logic signal,
    required PortRulesViolationException lowerException,
    required String traceDirection,
  }) : super([
          '$lowerException',
          if (module != lowerException.module)
            '@ Module $module \t [tracing $traceDirection]'
          else
            '= Module "${module.name}" \t [tracing $traceDirection]',
          '  on ${_getSignalDescription(signal)} \t $signal',
          if (signal.parentModule != module)
            '  of ${signal.parentModule == null ? 'undetermined sub-module' : 'sub-module\t${signal.parentModule!}'}',
        ].join('\n'));

  //TODO doc
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
