// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// if.dart
// Definition for if statements and blocks.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/conditionals/ssa.dart';

/// A conditional block to execute only if [condition] is satisified.
///
/// Intended for use with [If.block].
class ElseIf {
  /// A condition to match against to determine if [then] should be executed.
  final Logic condition;

  /// The [Conditional]s to execute if [condition] is satisfied.
  final List<Conditional> then;

  /// If [condition] is 1, then [then] will be executed.
  ElseIf(this.condition, this.then) {
    if (condition.width != 1) {
      throw PortWidthMismatchException(condition, 1);
    }
  }

  /// If [condition] is 1, then [then] will be executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  ElseIf.s(Logic condition, Conditional then) : this(condition, [then]);
}

/// A conditional block to execute only if `condition` is satisified.
///
/// Intended for use with [If.block].
typedef Iff = ElseIf;

/// A conditional block to execute only if [condition] is satisified.
///
/// This should come last in [If.block].
class Else extends Iff {
  /// If none of the proceding [Iff] or [ElseIf] are executed, then
  /// [then] will be executed.
  Else(List<Conditional> then) : super(Const(1), then);

  /// If none of the proceding [Iff] or [ElseIf] are executed, then
  /// [then] will be executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  Else.s(Conditional then) : this([then]);
}

/// Represents a chain of blocks of code to be conditionally executed, like
/// `if`/`else if`/`else`.
///
/// This is functionally equivalent to chaining together [If]s, but this syntax
/// is a little nicer for long chains.
@Deprecated('Use `If.block` instead.')
class IfBlock extends If {
  /// Checks the conditions for [iffs] in order and executes the first one
  /// whose condition is enabled.
  @Deprecated('Use `If.block` instead.')
  IfBlock(super.iffs) : super.block();
}

/// Represents a chain of blocks of code to be conditionally executed, like
/// `if`/`else if`/`else`.
class If extends Conditional {
  /// A set of conditional items to check against for execution, in order.
  ///
  /// The first item should be an [Iff], and if an [Else] is included it must
  /// be the last item.  Any other items should be [ElseIf].  It is okay to
  /// make the first item an [ElseIf], it will act just like an [Iff]. If an
  /// [Else] is included, it cannot be the only element (it must be preceded
  /// by an [Iff] or [ElseIf]).
  final List<Iff> iffs;

  /// If [condition] is high, then [then] executes, otherwise [orElse] is
  /// executed.
  If(Logic condition, {List<Conditional>? then, List<Conditional>? orElse})
      : this.block([
          Iff(condition, then ?? []),
          if (orElse != null) Else(orElse),
        ]);

  /// If [condition] is high, then [then] is excutes,
  /// otherwise [orElse] is executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  /// An optional [orElse] condition can be passed.
  If.s(Logic condition, Conditional then, [Conditional? orElse])
      : this(condition, then: [then], orElse: orElse == null ? [] : [orElse]);

  /// Checks the conditions for [iffs] in order and executes the first one
  /// whose condition is enabled.
  If.block(this.iffs) {
    for (final iff in iffs) {
      if (iff is Else) {
        if (iff != iffs.last) {
          throw InvalidConditionalException(
              'Else must come last in an IfBlock.');
        }

        if (iff == iffs.first) {
          throw InvalidConditionalException(
              'Else cannot be the first in an IfBlock.');
        }
      }
    }
  }

  @override
  void execute(Set<Logic>? drivenSignals, [void Function(Logic)? guard]) {
    if (guard != null) {
      for (final iff in iffs) {
        guard(iff.condition);
      }
    }

    for (final iff in iffs) {
      if (driverValue(iff.condition) == LogicValue.one) {
        for (final conditional in iff.then) {
          conditional.execute(drivenSignals, guard);
        }
        break;
      } else if (driverValue(iff.condition) != LogicValue.zero) {
        // x and z propagation
        driveX(drivenSignals);
        break;
      }
      // if it's 0, then continue searching down the path
    }
  }

  @override
  late final List<Conditional> conditionals =
      UnmodifiableListView(_getConditionals());

  /// Calculates the set of conditionals directly within this.
  List<Conditional> _getConditionals() => iffs
      .map((iff) => iff.then)
      .expand((conditional) => conditional)
      .toList(growable: false);

  @override
  late final List<Logic> drivers = _getDrivers();

  /// Calculates the set of drivers recursively down.
  List<Logic> _getDrivers() {
    final drivers = <Logic>[];
    for (final iff in iffs) {
      drivers
        ..add(iff.condition)
        ..addAll(iff.then
            .map((conditional) => conditional.drivers)
            .expand((driver) => driver)
            .toList(growable: false));
    }
    return drivers;
  }

  @override
  late final List<Logic> receivers = calculateReceivers();

  @override
  @protected
  List<Logic> calculateReceivers() {
    final receivers = <Logic>[];
    for (final iff in iffs) {
      receivers.addAll(iff.then
          .map((conditional) => conditional.receivers)
          .expand((receiver) => receiver)
          .toList(growable: false));
    }
    return receivers;
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final verilog = StringBuffer();
    for (final iff in iffs) {
      final header = iff == iffs.first
          ? 'if'
          : iff is Else
              ? 'else'
              : 'else if';

      final conditionName = inputsNameMap[driverInput(iff.condition).name];
      final ifContents = iff.then
          .map((conditional) => conditional.verilogContents(
              indent + 2, inputsNameMap, outputsNameMap, assignOperator))
          .join('\n');
      final condition = iff is! Else ? '($conditionName)' : '';
      verilog.write('''
$padding$header$condition begin
$ifContents
${padding}end ''');
    }
    verilog.write('\n');

    return verilog.toString();
  }

  @override
  Map<Logic, Logic> processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    // add an empty else if there isn't already one, since we need it for phi
    if (iffs.last is! Else) {
      iffs.add(Else([]));
    }

    // first connect direct drivers into the if statements
    for (final iff in iffs) {
      Conditional.connectSsaDriverFromMappings(iff.condition, currentMappings,
          context: context);
    }

    // calculate mappings locally within each if statement
    final phiMappings = <Logic, Logic>{};
    for (final conditionals in iffs.map((e) => e.then)) {
      var localMappings = {...currentMappings};

      for (final conditional in conditionals) {
        localMappings = conditional.processSsa(localMappings, context: context);
      }

      for (final localMapping in localMappings.entries) {
        if (!phiMappings.containsKey(localMapping.key)) {
          phiMappings[localMapping.key] = Logic(
            name: '${localMapping.key.name}_phi',
            width: localMapping.key.width,
            naming: Naming.mergeable,
          );
        }

        conditionals.add(phiMappings[localMapping.key]! < localMapping.value);
      }
    }

    final newMappings = <Logic, Logic>{...currentMappings}..addAll(phiMappings);

    // find all the SSA signals that are driven by anything in this if block,
    // since we need to ensure every case drives them or else we may create
    // an inferred latch
    final signalsNeedingInit = iffs
        .map((e) => e.then)
        .flattened
        .map((e) => e.calculateReceivers())
        .flattened
        .whereType<SsaLogic>()
        .toSet();
    for (final iff in iffs) {
      final alreadyDrivenSsaSignals = iff.then
          .map((e) => e.calculateReceivers())
          .flattened
          .whereType<SsaLogic>()
          .toSet();

      for (final signalNeedingInit in signalsNeedingInit) {
        if (!alreadyDrivenSsaSignals.contains(signalNeedingInit)) {
          iff.then.add(signalNeedingInit < 0);
        }
      }
    }

    return newMappings;
  }

  @override
  String toString() {
    final buffer = StringBuffer()..writeln('If(');
    for (final iff in iffs) {
      if (iff is Else) {
        buffer.writeln('  Else  ...');
      } else {
        buffer.writeln('  ${iff.condition.name} ...');
      }
    }
    buffer.writeln(')');
    return buffer.toString();
  }
}
