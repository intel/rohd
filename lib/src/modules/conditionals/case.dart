// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// case.dart
// Definition for case statements.
//
// 2024 December
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/modules/conditionals/ssa.dart';

/// Represents a single case within a [Case] block.
class CaseItem {
  /// The value to match against.
  final Logic value;

  /// A [List] of [Conditional]s to execute when [value] is matched.
  final List<Conditional> then;

  /// Executes [then] when [value] matches.
  CaseItem(this.value, this.then);

  @override
  String toString() => '$value : $then';
}

/// Shorthand for a [Case] inside a [Conditional] block.
///
/// It is used to assign a signal based on a condition with multiple cases to
/// consider. For e.g., this can be used instead of a nested [mux].
///
/// The result is of type [Logic] and it is determined by conditionaly matching
/// the expression with the values of each item in conditions. If width of the
/// input is not provided, then the width of  the result is inferred from the
/// width of the entries.
Logic cases(Logic expression, Map<dynamic, dynamic> conditions,
    {int? width,
    ConditionalType conditionalType = ConditionalType.none,
    dynamic defaultValue}) {
  for (final conditionValue in [
    ...conditions.values,
    if (defaultValue != null) defaultValue
  ]) {
    int? inferredWidth;

    if (conditionValue is Logic) {
      inferredWidth = conditionValue.width;
    } else if (conditionValue is LogicValue) {
      inferredWidth = conditionValue.width;
    }

    if (width != inferredWidth && width != null && inferredWidth != null) {
      throw SignalWidthMismatchException.forDynamic(
          conditionValue, width, inferredWidth);
    }

    width ??= inferredWidth;
  }

  if (width == null) {
    throw SignalWidthMismatchException.forNull(conditions);
  }

  for (final condition in conditions.entries) {
    if (condition.key is Logic) {
      if (expression.width != (condition.key as Logic).width) {
        throw SignalWidthMismatchException.forDynamic(
            condition.key, expression.width, (condition.key as Logic).width);
      }
    }

    if (condition.key is LogicValue) {
      if (expression.width != (condition.key as LogicValue).width) {
        throw SignalWidthMismatchException.forDynamic(condition.key,
            expression.width, (condition.key as LogicValue).width);
      }
    }
  }

  final result = Logic(name: 'result', width: width, naming: Naming.mergeable);

  Combinational([
    Case(
        expression,
        [
          for (final condition in conditions.entries)
            CaseItem(
                condition.key is Logic
                    ? condition.key as Logic
                    : Const(condition.key, width: expression.width),
                [result < condition.value])
        ],
        conditionalType: conditionalType,
        defaultItem: defaultValue != null ? [result < defaultValue] : null)
  ]);

  return result;
}

/// A block of [CaseItem]s where only the one with a matching [CaseItem.value]
/// is executed.
///
/// Searches for which of [items] appropriately matches [expression], then
/// executes the matching [CaseItem].  If [defaultItem] is specified, and no
/// other item matches, then that one is executed.  Use [conditionalType] to
/// modify behavior in ways similar to what is available in SystemVerilog.
class Case extends Conditional {
  /// A logical signal to match against.
  final Logic expression;

  /// An ordered collection of [CaseItem]s to search through for a match
  /// to [expression].
  final List<CaseItem> items;

  /// The default to execute when there was no match with any other [CaseItem]s.
  List<Conditional>? get defaultItem => _defaultItem;
  List<Conditional>? _defaultItem;

  /// The type of case block this is, for special attributes
  /// (e.g. [ConditionalType.unique], [ConditionalType.priority]).
  ///
  /// See [ConditionalType] for more details.
  final ConditionalType conditionalType;

  /// Whenever an item in [items] matches [expression], it will be executed.
  ///
  /// If none of [items] match, then [defaultItem] is executed.
  Case(this.expression, this.items,
      {List<Conditional>? defaultItem,
      this.conditionalType = ConditionalType.none})
      : _defaultItem = defaultItem {
    for (final item in items) {
      if (item.value.width != expression.width) {
        throw PortWidthMismatchException.equalWidth(expression, item.value);
      }
    }
  }

  /// Returns true iff [value] matches the expressions current value.
  @protected
  bool isMatch(LogicValue value, LogicValue expressionValue) =>
      expressionValue == value;

  /// Returns the SystemVerilog keyword to represent this case block.
  @protected
  String get caseType => 'case';

  @override
  void execute(Set<Logic>? drivenSignals, [void Function(Logic)? guard]) {
    if (guard != null) {
      guard(expression);
      for (final item in items) {
        guard(item.value);
      }
    }

    if (!expression.value.isValid) {
      // if expression has X or Z, then propagate X's!
      driveX(drivenSignals);
      return;
    }

    CaseItem? foundMatch;

    for (final item in items) {
      // match on the first matchinig item
      if (isMatch(driverValue(item.value), driverValue(expression))) {
        for (final conditional in item.then) {
          conditional.execute(drivenSignals, guard);
        }

        if (foundMatch != null && conditionalType == ConditionalType.unique) {
          driveX(drivenSignals);
          return;
        }

        foundMatch = item;

        if (conditionalType != ConditionalType.unique) {
          break;
        }
      }
    }

    // no items matched
    if (foundMatch == null && defaultItem != null) {
      for (final conditional in defaultItem!) {
        conditional.execute(drivenSignals, guard);
      }
    } else if (foundMatch == null &&
        (conditionalType == ConditionalType.unique ||
            conditionalType == ConditionalType.priority)) {
      driveX(drivenSignals);
      return;
    }
  }

  @override
  late final List<Conditional> conditionals =
      UnmodifiableListView(_getConditionals());

  /// Calculates the set of conditionals directly within this.
  List<Conditional> _getConditionals() => [
        ...items.map((item) => item.then).expand((conditional) => conditional),
        if (defaultItem != null) ...defaultItem!
      ];

  @override
  late final List<Logic> drivers = _getDrivers();

  /// Calculates the set of drivers recursively down.
  List<Logic> _getDrivers() {
    final drivers = <Logic>[expression];
    for (final item in items) {
      drivers
        ..add(item.value)
        ..addAll(item.then
            .map((conditional) => conditional.drivers)
            .expand((driver) => driver)
            .toList(growable: false));
    }
    if (defaultItem != null) {
      drivers.addAll(defaultItem!
          .map((conditional) => conditional.drivers)
          .expand((driver) => driver)
          .toList(growable: false));
    }
    return drivers;
  }

  @override
  late final List<Logic> receivers = calculateReceivers();

  @override
  List<Logic> calculateReceivers() {
    final receivers = <Logic>[];
    for (final item in items) {
      receivers.addAll(item.then
          .map((conditional) => conditional.receivers)
          .flattened
          .toList(growable: false));
    }
    if (defaultItem != null) {
      receivers.addAll(defaultItem!
          .map((conditional) => conditional.receivers)
          .flattened
          .toList(growable: false));
    }
    return receivers;
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final expressionName = inputsNameMap[driverInput(expression).name];
    var caseHeader = caseType;
    if (conditionalType == ConditionalType.priority) {
      caseHeader = 'priority $caseType';
    } else if (conditionalType == ConditionalType.unique) {
      caseHeader = 'unique $caseType';
    }
    final verilog = StringBuffer('$padding$caseHeader ($expressionName) \n');
    final subPadding = Conditional.calcPadding(indent + 2);
    for (final item in items) {
      final conditionName = inputsNameMap[driverInput(item.value).name];
      final caseContents = item.then
          .map((conditional) => conditional.verilogContents(
              indent + 4, inputsNameMap, outputsNameMap, assignOperator))
          .join('\n');
      verilog.write('''
$subPadding$conditionName : begin
$caseContents
${subPadding}end
''');
    }
    if (defaultItem != null) {
      final defaultCaseContents = defaultItem!
          .map((conditional) => conditional.verilogContents(
              indent + 4, inputsNameMap, outputsNameMap, assignOperator))
          .join('\n');
      verilog.write('''
${subPadding}default : begin
$defaultCaseContents
${subPadding}end
''');
    }
    verilog.write('${padding}endcase\n');

    return verilog.toString();
  }

  @override
  Map<Logic, Logic> processSsa(Map<Logic, Logic> currentMappings,
      {required int context}) {
    // add an empty default if there isn't already one, since we need it for phi
    _defaultItem ??= [];

    // first connect direct drivers into the case statement
    Conditional.connectSsaDriverFromMappings(expression, currentMappings,
        context: context);
    for (final itemDriver in items.map((e) => e.value)) {
      Conditional.connectSsaDriverFromMappings(itemDriver, currentMappings,
          context: context);
    }

    // calculate mappings locally within each item
    final phiMappings = <Logic, Logic>{};
    for (final conditionals in [
      ...items.map((e) => e.then),
      defaultItem!,
    ]) {
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

    // find all the SSA signals that are driven by anything in this case block,
    // since we need to ensure every case drives them or else we may create
    // an inferred latch
    final signalsNeedingInit = [
      ...items.map((e) => e.then).flattened,
      ...defaultItem!,
    ]
        .map((e) => e.calculateReceivers())
        .flattened
        .whereType<SsaLogic>()
        .toSet();
    for (final conditionals in [
      ...items.map((e) => e.then),
      defaultItem!,
    ]) {
      final alreadyDrivenSsaSignals = conditionals
          .map((e) => e.calculateReceivers())
          .flattened
          .whereType<SsaLogic>()
          .toSet();

      for (final signalNeedingInit in signalsNeedingInit) {
        if (!alreadyDrivenSsaSignals.contains(signalNeedingInit)) {
          conditionals.add(signalNeedingInit < 0);
        }
      }
    }

    return newMappings;
  }

  @override
  String toString() {
    final buffer = StringBuffer()..writeln('$caseType($expression, ');
    for (final item in items) {
      buffer.writeln('  $item');
    }
    buffer.writeln(')');
    return buffer.toString();
  }
}

/// A special version of [Case] which can do wildcard matching via `z` in
/// the expression.
///
/// Any `z` in the value of a [CaseItem] will act as a wildcard.
///
/// Does not support SystemVerilog's `?` syntax, which is exactly functionally
/// equivalent to `z` syntax.
class CaseZ extends Case {
  /// Whenever an item in [items] matches [expression], it will be executed, but
  /// the definition of matches allows for `z` to be a wildcard.
  ///
  /// If none of [items] match, then [defaultItem] is executed.
  CaseZ(super.expression, super.items,
      {super.defaultItem, super.conditionalType});

  @override
  String get caseType => 'casez';

  @override
  bool isMatch(LogicValue value, LogicValue expressionValue) {
    for (var i = 0; i < expression.width; i++) {
      if (expressionValue[i] != value[i] && value[i] != LogicValue.z) {
        return false;
      }
    }
    return true;
  }
}
