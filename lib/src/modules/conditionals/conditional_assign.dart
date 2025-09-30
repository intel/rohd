// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// conditional_assign.dart
// Definition for conditional assignment.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/conditionals/ssa.dart';

/// An assignment that only happens under certain conditions.
///
/// [Logic] has a short-hand for creating [ConditionalAssign] via the
///  `<` operator.
class ConditionalAssign extends Conditional {
  /// The input to this assignment.
  final Logic receiver;

  /// The output of this assignment.
  final Logic driver;

  /// Conditionally assigns [receiver] to the value of [driver].
  ConditionalAssign(this.receiver, this.driver) {
    if (driver.width != receiver.width) {
      throw PortWidthMismatchException.equalWidth(receiver, driver);
    }
  }

  @override
  String toString() => '${receiver.name} < ${driver.name}';

  @override
  late final List<Logic> receivers = [receiver];

  @override
  @protected
  List<Logic> calculateReceivers() => receivers;

  @override
  late final List<Logic> drivers = [driver];

  @override
  late final List<Conditional> conditionals = const [];

  /// A cached copy of the result of [receiverOutput] to save on lookups.
  late final Logic _receiverOutput = receiverOutput(receiver);

  @override
  void execute(Set<Logic>? drivenSignals,
      [void Function(Logic toGuard)? guard]) {
    if (guard != null) {
      guard(driver);
    }

    final currentValue = driverValue(driver);
    if (!currentValue.isValid) {
      // Use bitwise & to turn Z's into X's, but keep valid signals as-is.
      // It's too pessimistic to convert the whole bus to X.
      _receiverOutput.put(currentValue & currentValue);
    } else {
      _receiverOutput.put(currentValue);
    }

    if (drivenSignals != null &&
        (!drivenSignals.contains(receiver) || receiver.value.isValid)) {
      drivenSignals.add(receiver);
    }
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final driverName = inputsNameMap[driverInput(driver).name]!;
    final receiverName = outputsNameMap[receiverOutput(receiver).name]!;
    return '$padding$receiverName $assignOperator $driverName;';
  }

  @override
  Map<Logic, Logic> processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    Conditional.connectSsaDriverFromMappings(driver, currentMappings,
        context: context);

    final newMappings = <Logic, Logic>{...currentMappings};
    // if the receiver is an ssa node, then update the mapping
    if (receiver is SsaLogic) {
      newMappings[(receiver as SsaLogic).ref] = receiver;
    }

    return newMappings;
  }
}
