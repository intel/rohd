// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// combinational.dart
// Definition for combinational logic block.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/traverseable_collection.dart';
import 'package:rohd/src/modules/conditionals/always.dart';
import 'package:rohd/src/modules/conditionals/ssa.dart';
import 'package:rohd/src/utilities/synchronous_propagator.dart';

/// Represents a block of combinational logic.
///
/// This is similar to an `always_comb` block in SystemVerilog.
class Combinational extends Always {
  /// Constructs a new [Combinational] which executes [conditionals] in order
  /// procedurally.
  ///
  /// If any "write after read" occurs, then a [WriteAfterReadException] will
  /// be thrown since it could lead to a mismatch between simulation and
  /// synthesis.  See [Combinational.ssa] for more details.
  Combinational(super._conditionals,
      {super.name = 'combinational', super.label}) {
    _execute(); // for initial values
    for (final driver in assignedDriverToInputMap.keys) {
      driver.glitch.listen((args) {
        _execute();
      });
    }
  }

  /// An internal counter to keep track of unique contexts
  /// per [Combinational.ssa].
  static int _ssaContextCounter = 0;

  /// Constructs a new [Combinational] where [construct] generates a list of
  /// [Conditional]s which use the provided remapping function to enable
  /// a "static single-asssignment" (SSA) form for procedural execution. The
  /// Wikipedia article has a good explanation:
  /// https://en.wikipedia.org/wiki/Static_single-assignment_form
  ///
  /// In SystemVerilog, an `always_comb` block can easily produce
  /// non-synthesizable or ambiguous design blocks which can lead to subtle
  /// bugs and mismatches between simulation and synthesis.  Since
  /// [Combinational] maps directly to an `always_comb` block, it is also
  /// susceptible to these types of issues in the path to synthesis.
  ///
  /// A large class of  these issues can be prevented by avoiding a "write after
  /// read" scenario, where a signal is assigned a value after that value would
  /// have had an impact on prior procedural assignment in that same
  /// [Combinational] execution.
  ///
  /// [Combinational.ssa] remaps signals such that signals are only "written"
  /// once.
  ///
  /// The below example shows a simple use case:
  /// ```dart
  /// Combinational.ssa((s) => [
  ///   s(y) < 1,
  ///   s(y) < s(y) + 1,
  /// ]);
  /// ```
  ///
  /// Note that every variable in this case must be "initialized" before it
  /// can be used.
  ///
  /// Note that signals returned by the remapping function (`s`) are tied to
  /// this specific instance of [Combinational] and shouldn't be used elsewhere
  /// or you may see unexpected behavior.  Also note that each instance of
  /// signal returned by the remapping function should be used in at most
  /// one [Conditional] and on either the receiving or driving side, but not
  /// both.  These restrictions are generally easy to adhere to unless you do
  /// something strange.
  ///
  /// There is a construction-time performance penalty for usage of this
  /// roughly proportional to the size of the design feeding into this instance.
  /// This is because it must search for any remapped signals along the entire
  /// combinational and sequential path feeding into each [Conditional].  This
  /// penalty is purely at generation time, not in simulation or the actual
  /// generated design.  For very large designs, this penalty can be
  /// mitigated by constructing the [Combinational.ssa] before connecting
  /// inputs to the rest of the design, but usually the impact is so small
  /// that it will not be noticeable.
  factory Combinational.ssa(
      List<Conditional> Function(Logic Function(Logic signal) s) construct,
      {String name = 'combinational_ssa',
      String? label}) {
    final context = _ssaContextCounter++;

    final ssas = <SsaLogic>[];

    Logic getSsa(Logic ref) {
      final newSsa = SsaLogic(ref, context);
      ssas.add(newSsa);
      return newSsa;
    }

    final conditionals = construct(getSsa);

    ssas.forEach(_updateSsaDriverMap);

    _processSsa(conditionals, context: context);

    // no need to keep any of this old info around anymore
    signalToSsaDrivers.clear();

    return Combinational(conditionals, name: name, label: label);
  }

  /// A map from [SsaLogic]s to signals that they drive.
  ///
  /// This only stores information temporarily during construction of a
  /// [Combinational.ssa] and clears afterwards.
  @internal
  static final Map<Logic, Set<SsaLogic>> signalToSsaDrivers = {};

  /// Tags each downstream [Logic] from [ssaDriver] as such in
  /// [signalToSsaDrivers].
  static void _updateSsaDriverMap(SsaLogic ssaDriver) {
    final toParse = TraverseableCollection<Logic>()
      ..addAll(ssaDriver.dstConnections);
    for (var i = 0; i < toParse.length; i++) {
      final tpi = toParse[i];

      signalToSsaDrivers.putIfAbsent(tpi, () => <SsaLogic>{}).add(ssaDriver);

      if (tpi.isInput &&
          // ignore: deprecated_member_use_from_same_package
          ((tpi.parentModule! is CustomSystemVerilog) ||
              tpi.parentModule! is SystemVerilog)) {
        toParse.addAll(tpi.parentModule!.outputs.values);
      } else {
        toParse.addAll(tpi.dstConnections);
      }

      // This is critical to make sure we are notifying downstream SSA's even
      // if they are driven as a result of being a part of a modified structure.
      if (tpi.parentStructure != null) {
        toParse.add(tpi.parentStructure!);
      }

      // This is probably unnecessary, as the SSA would not allow someone to
      // reference an element of a structure without separately SSA'ing it.
      // However, leaving this in here just in case (probably negligible perf
      // impact).
      if (tpi is LogicStructure) {
        toParse.addAll(tpi.elements);
      }
    }
  }

  /// Executes the remapping for all the [conditionals] recursively.
  static void _processSsa(List<Conditional> conditionals,
      {required int context}) {
    var mappings = <Logic, Logic>{};
    for (final conditional in conditionals) {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_overriding_member
      mappings = conditional.processSsa(mappings, context: context);
    }

    for (final mapping in mappings.entries) {
      if (mapping.key.srcConnection != null) {
        throw MappedSignalAlreadyAssignedException(mapping.key.name);
      }

      mapping.key <= mapping.value;
    }
  }

  /// Keeps track of whether this block is already mid-execution, in order to
  /// detect reentrance.
  bool _isExecuting = false;

  /// Keeps track of already-driven logics during [_execute].
  ///
  /// Must be cleared at the end of each [_execute].
  final Set<Logic> _drivenLogics = HashSet<Logic>();

  /// Keeps track of signals already [_guard]ed.
  ///
  /// Must be cleared at the end of each [_execute].
  final Set<Logic> _guarded = HashSet<Logic>();

  /// Keeps track of subscriptions to glitches for each of the [_guarded].
  ///
  /// Must be cleared at the end of each [_execute].
  final List<SynchronousSubscription<LogicValueChanged>> _guardListeners =
      <SynchronousSubscription<LogicValueChanged>>[];

  /// A function that sub-[Conditional]s should call to guard signals they
  /// are consuming.
  void _guard(Logic toGuard) {
    if (_guarded.add(toGuard)) {
      _guardListeners.add(toGuard.glitch.listen(_writeAfterRead));
    }
  }

  /// A function that throws a [WriteAfterReadException].
  ///
  /// Declared as a separate static function so that it doesn't need to be
  /// created on each [_guard] call.
  static void _writeAfterRead(args) {
    throw WriteAfterReadException();
  }

  /// Performs the functional behavior of this block.
  void _execute() {
    if (_isExecuting) {
      // this combinational is already executing, which means an input has
      // changed as a result of some output of this combinational changing.
      // this is imperative style, so don't loop
      return;
    }

    _isExecuting = true;

    for (final element in conditionals) {
      // ignore: invalid_use_of_protected_member
      element.execute(_drivenLogics, _guard);
    }

    // combinational must always drive all outputs or else you get X!
    if (assignedReceiverToOutputMap.length != _drivenLogics.length) {
      for (final receiverOutputPair in assignedReceiverToOutputMap.entries) {
        if (!_drivenLogics.contains(receiverOutputPair.key)) {
          receiverOutputPair.value.put(LogicValue.x, fill: true);
        }
      }
    }

    // clean up after execution
    for (final guardListener in _guardListeners) {
      guardListener.cancel();
    }
    _guardListeners.clear();
    _drivenLogics.clear();
    _guarded.clear();

    _isExecuting = false;
  }

  @override
  String alwaysVerilogStatement(Map<String, String> inputs) => 'always_comb';

  @override
  String assignOperator() => '=';
}
