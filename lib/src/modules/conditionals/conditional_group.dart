// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// conditional_group.dart
// Definition for a group of conditionals to be executed.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

/// Represents a group of [Conditional]s to be executed.
class ConditionalGroup extends Conditional {
  @override
  final List<Conditional> conditionals;

  /// Creates a group of [conditionals] to be executed in order and bundles
  /// them into a single [Conditional].
  ConditionalGroup(this.conditionals);

  @override
  Map<Logic, Logic> processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    var mappings = currentMappings;
    for (final conditional in conditionals) {
      mappings = conditional.processSsa(mappings, context: context);
    }
    return mappings;
  }

  @override
  late final List<Logic> drivers = [
    for (final conditional in conditionals) ...conditional.drivers
  ];

  @override
  late final List<Logic> receivers = calculateReceivers();

  @override
  @protected
  List<Logic> calculateReceivers() =>
      [for (final conditional in conditionals) ...conditional.receivers];

  @override
  void execute(Set<Logic>? drivenSignals, void Function(Logic toGuard)? guard) {
    for (final conditional in conditionals) {
      conditional.execute(drivenSignals, guard);
    }
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
          Map<String, String> outputsNameMap, String assignOperator) =>
      conditionals
          .map((c) => c.verilogContents(
                indent,
                inputsNameMap,
                outputsNameMap,
                assignOperator,
              ))
          .join('\n');
}
