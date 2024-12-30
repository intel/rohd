// Copyright (C) 2021-2024 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// conditional.dart
// Definition for conditionallly executed hardware constructs
//
// 2021 May 7
// Author: Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/conditionals/ssa.dart';

/// Represents an some logical assignments or actions that will only happen
/// under certain conditions.
abstract class Conditional {
  /// A [Map] from receiver [Logic] signals passed into this [Conditional] to
  /// the appropriate output logic port.
  late Map<Logic, Logic> _assignedReceiverToOutputMap;

  /// A [Map] from driver [Logic] signals passed into this [Conditional] to
  /// the appropriate input logic port.
  late Map<Logic, Logic> _assignedDriverToInputMap;

  /// A [Map] of override [LogicValue]s for driver [Logic]s of
  /// this [Conditional].
  ///
  /// This is used for things like [Sequential]'s pre-tick values.
  Map<Logic, LogicValue> _driverValueOverrideMap = {};

  /// Updates the values of [_assignedReceiverToOutputMap] and
  /// [_assignedDriverToInputMap] and passes them down to all sub-[Conditional]s
  /// as well.
  @internal
  void updateAssignmentMaps(
    Map<Logic, Logic> assignedReceiverToOutputMap,
    Map<Logic, Logic> assignedDriverToInputMap,
  ) {
    _assignedReceiverToOutputMap = assignedReceiverToOutputMap;
    _assignedDriverToInputMap = assignedDriverToInputMap;
    for (final conditional in conditionals) {
      conditional.updateAssignmentMaps(
          assignedReceiverToOutputMap, assignedDriverToInputMap);
    }
  }

  /// Updates the value of [_driverValueOverrideMap] and passes it down to all
  /// sub-[Conditional]s as well.
  @internal
  void updateOverrideMap(Map<Logic, LogicValue> driverValueOverrideMap) {
    // this is for always_ff pre-tick values
    _driverValueOverrideMap = driverValueOverrideMap;
    for (final conditional in conditionals) {
      conditional.updateOverrideMap(driverValueOverrideMap);
    }
  }

  /// Gets the value that should be used for execution for the input port
  /// associated with [driver].
  @protected
  LogicValue driverValue(Logic driver) =>
      _driverValueOverrideMap[driverInput(driver)] ??
      _assignedDriverToInputMap[driver]!.value;

  /// Gets the input port associated with [driver].
  @protected
  Logic driverInput(Logic driver) => _assignedDriverToInputMap[driver]!;

  /// Gets the output port associated with [receiver].
  @protected
  Logic receiverOutput(Logic receiver) =>
      _assignedReceiverToOutputMap[receiver]!;

  /// Executes the functionality of this [Conditional] and
  /// populates [drivenSignals] with all [Logic]s that were driven
  /// during execution.
  ///
  /// The [drivenSignals] are used by the caller to determine if signals
  /// were driven an appropriate number of times.
  ///
  /// The [guard] function should be called on drivers *prior* to any execution
  /// which consumes the current value of those drivers.  It is used to check
  /// that signals are not "written after read", for example.
  @protected
  void execute(Set<Logic>? drivenSignals, void Function(Logic toGuard)? guard);

  /// Lists *all* receivers, recursively including all sub-[Conditional]s
  /// receivers.
  @Deprecated('Use `receivers` instead.')
  List<Logic> getReceivers() => receivers;

  /// The same as [receivers], but uncached for situations where the list of
  /// [conditionals] may still be modified or to compute the cached result
  /// for [receivers] itself.
  @visibleForOverriding
  @protected
  List<Logic> calculateReceivers();

  /// Lists *all* receivers, recursively including all sub-[Conditional]s
  /// receivers.
  List<Logic> get receivers;

  /// Lists *all* drivers, recursively including all sub-[Conditional]s drivers.
  @Deprecated('Use `drivers` instead.')
  List<Logic> getDrivers() => drivers;

  /// Lists *all* drivers, recursively including all sub-[Conditional]s drivers.
  List<Logic> get drivers;

  /// Lists of *all* [Conditional]s directly contained within this [Conditional]
  /// (not including itself).
  ///
  /// Does *not* recursively call down through sub-[Conditional]s.
  @Deprecated('Use `conditionals` instead.')
  List<Conditional> getConditionals() => conditionals;

  /// Lists of *all* [Conditional]s directly contained within this [Conditional]
  /// (not including itself).
  ///
  /// Does *not* recursively call down through sub-[Conditional]s.
  List<Conditional> get conditionals;

  /// Returns a [String] of SystemVerilog to be used in generated output.
  ///
  /// The [indent] is used for pretty-printing, and should generally be
  /// incremented for sub-[Conditional]s. The [inputsNameMap] and
  /// [outputsNameMap] are a mapping from port names to SystemVerilog variable
  /// names for inputs and outputs, respectively.  The [assignOperator] is the
  /// SystemVerilog operator that should be used for any assignments within
  /// this [Conditional].
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator);

  /// Calculates an amount of padding to provie at the beginning of each new
  /// line based on [indent].
  static String calcPadding(int indent) => List.filled(indent, '  ').join();

  /// Connects [driver] to drive all appropriate SSA nodes based on [mappings]
  /// which match the provided [context].
  @protected
  static void connectSsaDriverFromMappings(
      Logic driver, Map<Logic, Logic> mappings,
      {required int context}) {
    final ssaDrivers = Conditional._findSsaDriversFrom(driver, context);

    // take all the "current" names for these signals
    for (final ssaDriver in ssaDrivers) {
      if (!mappings.containsKey(ssaDriver.ref)) {
        throw UninitializedSignalException(ssaDriver.ref.name);
      }

      // if these are already connected, just skip it, we're fine already
      if (ssaDriver.srcConnection != null &&
          ssaDriver.srcConnection == mappings[ssaDriver.ref]!) {
        continue;
      }

      // if these are the same signal, also just skip it
      if (ssaDriver == mappings[ssaDriver.ref]!) {
        continue;
      }

      ssaDriver <= mappings[ssaDriver.ref]!;
    }
  }

  /// Searches for SSA nodes from a source [driver] which match the [context].
  static List<SsaLogic> _findSsaDriversFrom(Logic driver, int context) {
    if (driver is SsaLogic && driver.context == context) {
      return [driver];
    }

    // no need to check for context on this map since it clears each time
    return Combinational.signalToSsaDrivers[driver]?.toList() ?? const [];
  }

  /// Given existing [currentMappings], connects [drivers] and [receivers]
  /// accordingly to [SsaLogic]s and returns an updated set of mappings.
  ///
  /// This function may add new [Conditional]s to existing [Conditional]s.
  ///
  /// This is used for [Combinational.ssa].
  @protected
  @visibleForOverriding
  Map<Logic, Logic> processSsa(Map<Logic, Logic> currentMappings,
      {required int context});

  /// Drives X to all receivers.
  @protected
  void driveX(Set<Logic>? drivenSignals) {
    for (final receiver in receivers) {
      receiverOutput(receiver).put(LogicValue.x);
      if (drivenSignals != null &&
          (!drivenSignals.contains(receiver) || receiver.value.isValid)) {
        drivenSignals.add(receiver);
      }
    }
  }
}

/// Controls characteristics about [Case] blocks.
///
/// The default type is [none].  The [unique] and [priority] values have
/// behavior similar to what is implemented in SystemVerilog.
///
/// [priority] indicates that the decisions must be executed in the same order
/// that they are listed, and that every legal scenario is included.
/// An exception will be thrown if there is no match to a scenario.
///
/// [unique] indicates that for a given expression, only one item will match.
/// If multiple items match the expression, an exception will be thrown.
/// If there is no match and no default item, an exception will also be thrown.
enum ConditionalType {
  /// There are no special checking or expectations.
  none,

  /// Expect that exactly one condition is true.
  unique,

  /// Expect that at least one condition is true, and the first one is executed.
  priority
}
