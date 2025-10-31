// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// always.dart
// Definition for base class for combinational and sequential blocks.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Represents a block of logic, similar to `always` blocks in SystemVerilog.
abstract class Always extends Module with SystemVerilog {
  /// A [List] of the [Conditional]s to execute.
  List<Conditional> get conditionals =>
      UnmodifiableListView<Conditional>(_conditionals);
  List<Conditional> _conditionals;

  /// A mapping from internal receiver signals to designated [Module] outputs.
  @protected
  @internal
  final Map<Logic, Logic> assignedReceiverToOutputMap = HashMap<Logic, Logic>();

  /// A mapping from internal driver signals to designated [Module] inputs.
  @protected
  @internal
  final Map<Logic, Logic> assignedDriverToInputMap = HashMap<Logic, Logic>();

  /// A uniquifier for ports generated on this [Always].
  @protected
  @internal
  final Uniquifier portUniquifier = Uniquifier();

  /// Executes provided [conditionals] at the appropriate time (specified by
  /// child class).
  ///
  /// If [reset] is provided, then all signals driven by this block will be
  /// conditionally reset when the signal is high.
  /// The default reset value is to `0`, but if [resetValues] is provided then
  /// the corresponding value associated with the driven signal will be set to
  /// that value instead upon reset. If a signal is in [resetValues] but not
  /// driven by any other [Conditional] in this block, it will be driven to the
  /// specified reset value.
  Always(this._conditionals,
      {Logic? reset, Map<Logic, dynamic>? resetValues, super.name = 'always'}) {
    // create a registration of all inputs and outputs of this module
    var idx = 0;

    // Get all Receivers
    final allReceivers = conditionals
        .map((e) => e.receivers)
        .expand((e) => e)
        .toSet()
        .toList(growable: false);

    // This will reset the conditionals on setting the `reset` flag
    if (reset != null) {
      final allResetCondAssigns = <Conditional>[];
      final signalsBeingReset = <Logic>{};

      if (resetValues != null) {
        final toConsiderForElementsReset = <Logic>[
          ...resetValues.keys,
        ];

        for (var i = 0; i < toConsiderForElementsReset.length; i++) {
          final toConsider = toConsiderForElementsReset[i];

          // if it's a structure, we need to consider its elements
          if (toConsider is LogicStructure) {
            toConsiderForElementsReset.addAll(toConsider.elements);
          }

          // if we're already resetting this signal, flag an issue
          if (signalsBeingReset.contains(toConsider)) {
            throw SignalRedrivenException([toConsider],
                'Signal is already being reset by another reset value: ');
          }

          if (resetValues.containsKey(toConsider)) {
            // should only be true for top-level structures referenced
            allResetCondAssigns.add(toConsider < resetValues[toConsider]);
          }

          // always add the signal, even if this is a sub-element
          signalsBeingReset.add(toConsider);
        }
      }

      // now add the reset to 0 for all the remaining ones
      for (final receiver in allReceivers) {
        if (!signalsBeingReset.contains(receiver)) {
          allResetCondAssigns.add(receiver < 0);
        }
      }

      _conditionals = [
        // If resetValue for a receiver is defined,
        If(
          reset,
          // then use it for assigning receiver
          then: allResetCondAssigns,
          // else assign zero as resetValue
          orElse: conditionals,
        ),
      ];
    }

    for (final conditional in conditionals) {
      for (final driver in conditional.drivers) {
        if (!assignedDriverToInputMap.containsKey(driver)) {
          final inputName = portUniquifier.getUniqueName(
              initialName: Naming.unpreferredName(
                  Sanitizer.sanitizeSV('in${idx}_${driver.name}')));
          addInput(inputName, driver, width: driver.width);
          assignedDriverToInputMap[driver] = input(inputName);
          idx++;
        }
      }
      for (final receiver in conditional.receivers) {
        if (!assignedReceiverToOutputMap.containsKey(receiver)) {
          final outputName = portUniquifier.getUniqueName(
              initialName: Naming.unpreferredName(
                  Sanitizer.sanitizeSV('out${idx}_${receiver.name}')));
          addOutput(outputName, width: receiver.width);
          assignedReceiverToOutputMap[receiver] = output(outputName);
          receiver <= output(outputName);
          idx++;
        }
      }

      // share the registration information down
      conditional.updateRegistration(
        assignedReceiverToOutputMap: assignedReceiverToOutputMap,
        assignedDriverToInputMap: assignedDriverToInputMap,
        parentConditional: null,
        parentAlways: this,
      );
    }
  }

  String _alwaysContents(Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final contents = StringBuffer();
    for (final conditional in conditionals) {
      final subContents = conditional.verilogContents(
          1, inputsNameMap, outputsNameMap, assignOperator);
      contents.write('$subContents\n');
    }
    return contents.toString();
  }

  /// The "always" part of the `always` block when generating SystemVerilog.
  ///
  /// For example, `always_comb` or `always_ff`.
  @protected
  @visibleForOverriding
  String alwaysVerilogStatement(Map<String, String> inputs);

  /// The assignment operator to use when generating SystemVerilog.
  ///
  /// For example `=` or `<=`.
  @protected
  @visibleForOverriding
  String assignOperator();

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    // no `inouts` can be used in a `Conditional`
    final inputs = Map.fromEntries(
        ports.entries.where((element) => this.inputs.containsKey(element.key)));
    final outputs = Map.fromEntries(ports.entries
        .where((element) => this.outputs.containsKey(element.key)));

    var verilog = '';
    verilog += '//  $instanceName\n';
    verilog += '${alwaysVerilogStatement(inputs)} begin\n';
    verilog += _alwaysContents(inputs, outputs, assignOperator());
    verilog += 'end\n';
    return verilog;
  }
}
