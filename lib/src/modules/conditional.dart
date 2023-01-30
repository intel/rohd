/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// conditional.dart
/// Definitions of conditionallly executed hardware constructs (if/else statements, always_comb, always_ff, etc.)
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/collections/duplicate_detection_set.dart';
import 'package:rohd/src/exceptions/conditionals/conditional_exceptions.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/uniquifier.dart';

/// Represents a block of logic, similar to `always` blocks in SystemVerilog.
abstract class _Always extends Module with CustomSystemVerilog {
  /// A [List] of the [Conditional]s to execute.
  final List<Conditional> conditionals;

  /// A mapping from internal receiver signals to designated [Module] outputs.
  final Map<Logic, Logic> _assignedReceiverToOutputMap = {};

  /// A mapping from internal driver signals to designated [Module] inputs.
  final Map<Logic, Logic> _assignedDriverToInputMap = {};

  final Uniquifier _portUniquifier = Uniquifier();

  _Always(this.conditionals, {super.name = 'always'}) {
    // create a registration of all inputs and outputs of this module
    var idx = 0;
    for (final conditional in conditionals) {
      for (final driver in conditional.getDrivers()) {
        if (!_assignedDriverToInputMap.containsKey(driver)) {
          final inputName = _portUniquifier.getUniqueName(
              initialName: Module.unpreferredName(
                  Sanitizer.sanitizeSV('in${idx}_${driver.name}')));
          addInput(inputName, driver, width: driver.width);
          _assignedDriverToInputMap[driver] = input(inputName);
          idx++;
        }
      }
      for (final receiver in conditional.getReceivers()) {
        if (!_assignedReceiverToOutputMap.containsKey(receiver)) {
          final outputName = _portUniquifier.getUniqueName(
              initialName: Module.unpreferredName(
                  Sanitizer.sanitizeSV('out${idx}_${receiver.name}')));
          addOutput(outputName, width: receiver.width);
          _assignedReceiverToOutputMap[receiver] = output(outputName);
          receiver <= output(outputName);
          idx++;
        }
      }

      // share the registration information down
      conditional._updateAssignmentMaps(
          _assignedReceiverToOutputMap, _assignedDriverToInputMap);
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
  String alwaysVerilogStatement(Map<String, String> inputs);

  /// The assignment operator to use when generating SystemVerilog.
  ///
  /// For example `=` or `<=`.
  @protected
  String assignOperator();

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    var verilog = '';
    verilog += '//  $instanceName\n';
    verilog += '${alwaysVerilogStatement(inputs)} begin\n';
    verilog += _alwaysContents(inputs, outputs, assignOperator());
    verilog += 'end\n';
    return verilog;
  }
}

/// Represents a block of combinational logic.
///
/// This is similar to an `always_comb` block in SystemVerilog.
///
/// Note that it is necessary to build this module and any sensitive
/// dependencies in order for sensitivity detection to work properly
/// in all cases.
class Combinational extends _Always with FullyCombinational {
  /// Constructs a new [Combinational] which executes [conditionals] in order
  /// procedurally.
  Combinational(super.conditionals, {super.name = 'combinational'}) {
    _execute(); // for initial values
    for (final driver in _assignedDriverToInputMap.keys) {
      driver.glitch.listen((args) {
        _execute();
      });
    }
  }

  @override
  Future<void> build() async {
    await super.build();

    // any glitch on an input to an output's sensitivity should
    // trigger re-execution
    _listenToSensitivities();
  }

  /// Sets up additional glitch listening for sensitive modules.
  void _listenToSensitivities() {
    final sensitivities = <Logic>{};
    for (final out in outputs.values) {
      final newSensitivities = _collectSensitivities(out);
      if (newSensitivities != null) {
        sensitivities.addAll(newSensitivities);
      }
    }

    for (final sensitivity in sensitivities) {
      sensitivity.glitch.listen((args) {
        _execute();
      });
    }
  }

  /// Recursively collects a list of all [Logic]s that this should be sensitive
  /// to beyond direct inputs.
  ///
  /// Use [alreadyParsed] to prevent searching down paths already searched.
  Set<Logic>? _collectSensitivities(Logic src, [Set<Logic>? alreadyParsed]) {
    Set<Logic>? collection;

    alreadyParsed ??= {};
    if (alreadyParsed.contains(src)) {
      // we're in a loop or already traversed this path, abandon it
      return null;
    }
    alreadyParsed.add(src);

    final dstConnections = src.dstConnections.toSet();

    if (src.isInput) {
      if (src.parentModule! is Sequential) {
        // sequential logic can't be a sensitivity, so ditch those
        return null;
      }

      // we're at the input to another module, grab all the outputs of it which
      // are combinationally connected and continue searching
      dstConnections.addAll(src.parentModule!.combinationalPaths[src]!);
    }

    if (dstConnections.isEmpty) {
      // we've reached the end of the line and not hit an input to this
      // Combinational
      return null;
    }

    for (final dst in dstConnections) {
      // if any of these are an input to this Combinational, then we've found
      // a sensitivity
      if (dst.isInput && dst.parentModule! == this) {
        // make sure we have something to return
        collection ??= {};
      } else {
        // otherwise, let's look deeper to see if any others down the path
        // are sensitivities
        final subSensitivities = _collectSensitivities(dst, alreadyParsed);

        if (subSensitivities == null) {
          // if we get null, then it was a dead end
          continue;
        } else {
          // otherwise, we have some sensitivities to send back
          collection ??= {};
          collection.addAll(subSensitivities);
          if (dst.isInput) {
            // collect all the inputs of this module too as sensitivities
            // but only ones which can affect outputs affected by this input!

            if (dst.parentModule! is FullyCombinational) {
              // for efficiency, if purely combinational just go straight to all
              collection.addAll(dst.parentModule!.inputs.values);
            } else {
              // default, add all inputs that may affect outputs affected
              // by this input
              for (final dstDependentOutput
                  in dst.parentModule!.combinationalPaths[dst]!) {
                collection.addAll(dst.parentModule!
                    .reverseCombinationalPaths[dstDependentOutput]!);
              }
            }
          }
        }
      }
    }

    return collection;
  }

  /// Keeps track of whether this block is already mid-execution, in order to
  /// detect reentrance.
  bool _isExecuting = false;

  /// Performs the functional behavior of this block.
  void _execute() {
    if (_isExecuting) {
      // this combinational is already executing, which means an input has
      // changed as a result of some output of this combinational changing.
      // this is imperative style, so don't loop
      return;
    }

    _isExecuting = true;

    final drivenLogics = <Logic>{};
    for (final element in conditionals) {
      element.execute(drivenLogics);
    }

    // combinational must always drive all outputs or else you get X!
    if (_assignedReceiverToOutputMap.length != drivenLogics.length) {
      for (final receiverOutputPair in _assignedReceiverToOutputMap.entries) {
        if (!drivenLogics.contains(receiverOutputPair.key)) {
          receiverOutputPair.value.put(LogicValue.x, fill: true);
        }
      }
    }

    _isExecuting = false;
  }

  @override
  String alwaysVerilogStatement(Map<String, String> inputs) => 'always_comb';
  @override
  String assignOperator() => '=';
}

/// Deprecated: use [Sequential] instead.
@Deprecated('Use Sequential instead')
typedef FF = Sequential;

/// Represents a block of sequential logic.
///
/// This is similar to an `always_ff` block in SystemVerilog.  Positive edge
/// triggered by either one trigger or multiple with [Sequential.multi].
class Sequential extends _Always {
  /// The input clocks used in this block.
  final List<Logic> _clks = [];

  /// Constructs a [Sequential] single-triggered by [clk].
  Sequential(Logic clk, List<Conditional> conditionals,
      {String name = 'sequential'})
      : this.multi([clk], conditionals, name: name);

  /// Constructs a [Sequential] multi-triggered by any of [clks].
  Sequential.multi(List<Logic> clks, List<Conditional> conditionals,
      {String name = 'sequential'})
      : super(conditionals, name: name) {
    for (var i = 0; i < clks.length; i++) {
      final clk = clks[i];
      if (clk.width > 1) {
        throw Exception('Each clk must be 1 bit, but saw $clk.');
      }
      _clks.add(addInput(
          _portUniquifier.getUniqueName(
              initialName: Sanitizer.sanitizeSV(
                  Module.unpreferredName('clk${i}_${clk.name}'))),
          clk));
      _preTickClkValues.add(null);
    }
    _setup();
  }

  /// A map from input [Logic]s to the values that should be used for
  /// computations on the edge.
  final Map<Logic, LogicValue> _inputToPreTickInputValuesMap = {};

  /// The value of the clock before the tick.
  final List<LogicValue?> _preTickClkValues = [];

  /// Keeps track of whether the clock has glitched and an [_execute] is
  /// necessary.
  bool _pendingExecute = false;

  /// A set of drivers whose values in [_inputToPreTickInputValuesMap] need
  /// updating after the tick completes.
  final Set<Logic> _driverInputsPendingPostUpdate = {};

  /// Keeps track of whether values need to be updated post-tick.
  bool _pendingPostUpdate = false;

  /// Performs setup steps for custom functional behavior of this block.
  void _setup() {
    // one time is enough, it's a final map
    for (final element in conditionals) {
      element._updateOverrideMap(_inputToPreTickInputValuesMap);
    }

    // listen to every input of this `Sequential` for changes
    for (final driverInput in _assignedDriverToInputMap.values) {
      // pre-fill the _inputToPreTickInputValuesMap so that nothing ever
      // uses values directly
      _inputToPreTickInputValuesMap[driverInput] = driverInput.value;

      driverInput.glitch.listen((event) async {
        if (Simulator.phase != SimulatorPhase.clkStable) {
          // if the change happens not when the clocks are stable, immediately
          // update the map
          _inputToPreTickInputValuesMap[driverInput] = driverInput.value;
        } else {
          // if this is during stable clocks, it's probably another flop
          // driving it, so hold onto it for later
          _driverInputsPendingPostUpdate.add(driverInput);
          if (!_pendingPostUpdate) {
            unawaited(
              Simulator.postTick.first.then(
                (value) {
                  // once the tick has completed,
                  // we can update the override maps
                  for (final driverInput in _driverInputsPendingPostUpdate) {
                    _inputToPreTickInputValuesMap[driverInput] =
                        driverInput.value;
                  }
                  _driverInputsPendingPostUpdate.clear();
                  _pendingPostUpdate = false;
                },
              ).catchError(
                test: (error) => error is Exception,
                // ignore: avoid_types_on_closure_parameters
                (Object err, StackTrace stackTrace) {
                  Simulator.throwException(err as Exception, stackTrace);
                },
              ),
            );
          }
          _pendingPostUpdate = true;
        }
      });
    }

    // listen to every clock glitch to see if we need to execute
    for (var i = 0; i < _clks.length; i++) {
      final clk = _clks[i];
      clk.glitch.listen((event) async {
        // we want the first previousValue from the first glitch of this tick
        _preTickClkValues[i] ??= event.previousValue;
        if (!_pendingExecute) {
          unawaited(Simulator.clkStable.first.then((value) {
            // once the clocks are stable, execute the contents of the FF
            _execute();
            _pendingExecute = false;
          }).catchError(test: (error) => error is Exception,
              // ignore: avoid_types_on_closure_parameters
              (Object err, StackTrace stackTrace) {
            Simulator.throwException(err as Exception, stackTrace);
          }).catchError(test: (error) => error is StateError,
              // ignore: avoid_types_on_closure_parameters
              (Object err, StackTrace stackTrace) {
            // This could be a result of the `Simulator` being reset, causing
            // the stream to `close` before `first` occurs.
            if (!Simulator.simulationHasEnded) {
              // If the `Simulator` is still running, rethrow immediately.

              // ignore: only_throw_errors
              throw err;
            }
          }));
        }
        _pendingExecute = true;
      });
    }
  }

  void _execute() {
    var anyClkInvalid = false;
    var anyClkPosedge = false;

    for (var i = 0; i < _clks.length; i++) {
      // if the pre-tick value is null, then it should have the same value as
      // it currently does
      if (!_clks[i].value.isValid || !(_preTickClkValues[i]?.isValid ?? true)) {
        anyClkInvalid = true;
        break;
      } else if (_preTickClkValues[i] != null &&
          LogicValue.isPosedge(_preTickClkValues[i]!, _clks[i].value)) {
        anyClkPosedge = true;
        break;
      }
    }

    if (anyClkInvalid) {
      for (final receiverOutput in _assignedReceiverToOutputMap.values) {
        receiverOutput.put(LogicValue.x);
      }
    } else if (anyClkPosedge) {
      final allDrivenSignals = DuplicateDetectionSet<Logic>();
      for (final element in conditionals) {
        element.execute(allDrivenSignals);
      }
      if (allDrivenSignals.hasDuplicates) {
        throw SignalRedrivenException(allDrivenSignals.duplicates.toString());
      }
    }

    // clear out all the pre-tick value of clocks
    for (var i = 0; i < _clks.length; i++) {
      _preTickClkValues[i] = null;
    }
  }

  @override
  String alwaysVerilogStatement(Map<String, String> inputs) {
    final triggers =
        _clks.map((clk) => 'posedge ${inputs[clk.name]}').join(' or ');
    return 'always_ff @($triggers)';
  }

  @override
  String assignOperator() => '<=';
}

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
  /// [_assignedDriverToInputMap] and passes them down to all
  /// sub-[Conditional]s as well.
  void _updateAssignmentMaps(
    Map<Logic, Logic> assignedReceiverToOutputMap,
    Map<Logic, Logic> assignedDriverToInputMap,
  ) {
    _assignedReceiverToOutputMap = assignedReceiverToOutputMap;
    _assignedDriverToInputMap = assignedDriverToInputMap;
    for (final conditional in getConditionals()) {
      conditional._updateAssignmentMaps(
          assignedReceiverToOutputMap, assignedDriverToInputMap);
    }
  }

  /// Updates the value of [_driverValueOverrideMap] and passes it down to all
  /// sub-[Conditional]s as well.
  void _updateOverrideMap(Map<Logic, LogicValue> driverValueOverrideMap) {
    // this is for always_ff pre-tick values
    _driverValueOverrideMap = driverValueOverrideMap;
    for (final conditional in getConditionals()) {
      conditional._updateOverrideMap(driverValueOverrideMap);
    }
  }

  /// Gets the value that should be used for execution for the input port
  /// associated with [driver].
  @protected
  LogicValue driverValue(Logic driver) =>
      _driverValueOverrideMap.containsKey(driverInput(driver))
          ? _driverValueOverrideMap[driverInput(driver)]!
          : _assignedDriverToInputMap[driver]!.value;

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
  @protected
  void execute(Set<Logic> drivenSignals);

  /// Lists *all* receivers, recursively including all sub-[Conditional]s
  /// receivers.
  List<Logic> getReceivers();

  /// Lists *all* drivers, recursively including all sub-[Conditional]s drivers.
  List<Logic> getDrivers();

  /// Lists of *all* [Conditional]s contained within this [Conditional]
  /// (not including itself).
  ///
  /// Recursively calls down through sub-[Conditional]s.
  List<Conditional> getConditionals();

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
}

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
      throw Exception('Width for $receiver and $driver must match but do not.');
    }
  }

  @override
  List<Logic> getReceivers() => [receiver];
  @override
  List<Logic> getDrivers() => [driver];
  @override
  List<Conditional> getConditionals() => [];

  @override
  void execute(Set<Logic> drivenSignals) {
    receiverOutput(receiver).put(driverValue(driver));

    if (!drivenSignals.contains(receiver) || receiver.value.isValid) {
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
}

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
  final List<Conditional>? defaultItem;

  /// The type of case block this is, for special attributes
  /// (e.g. [ConditionalType.unique], [ConditionalType.priority]).
  ///
  /// See [ConditionalType] for more details.
  final ConditionalType conditionalType;

  /// Whenever an item in [items] matches [expression], it will be executed.
  ///
  /// If none of [items] match, then [defaultItem] is executed.
  Case(this.expression, this.items,
      {this.defaultItem, this.conditionalType = ConditionalType.none});

  /// Returns true iff [value] matches the expressions current value.
  @protected
  bool isMatch(LogicValue value) => expression.value == value;

  /// Returns the SystemVerilog keyword to represent this case block.
  @protected
  String get caseType => 'case';

  @override
  void execute(Set<Logic> drivenSignals) {
    if (!expression.value.isValid) {
      // if expression has X or Z, then propogate X's!
      for (final receiver in getReceivers()) {
        receiverOutput(receiver).put(LogicValue.x);
        if (!drivenSignals.contains(receiver) || receiver.value.isValid) {
          drivenSignals.add(receiver);
        }
      }
      return;
    }

    CaseItem? foundMatch;

    for (final item in items) {
      // match on the first matchinig item
      if (isMatch(item.value.value)) {
        for (final conditional in item.then) {
          conditional.execute(drivenSignals);
        }
        if (foundMatch != null && conditionalType == ConditionalType.unique) {
          throw Exception('Unique case statement had multiple matching cases.'
              ' Original: "$foundMatch".'
              ' Duplicate: "$item".');
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
        conditional.execute(drivenSignals);
      }
    } else if (foundMatch == null &&
        (conditionalType == ConditionalType.unique ||
            conditionalType == ConditionalType.priority)) {
      throw Exception('$conditionalType case statement had no matching case,'
          ' and type was $conditionalType.');
    }
  }

  @override
  List<Conditional> getConditionals() => [
        ...items.map((item) => item.then).expand((conditional) => conditional),
        ...defaultItem ?? []
      ];

  @override
  List<Logic> getDrivers() {
    final drivers = <Logic>[expression];
    for (final item in items) {
      drivers
        ..add(item.value)
        ..addAll(item.then
            .map((conditional) => conditional.getDrivers())
            .expand((driver) => driver)
            .toList());
    }
    if (defaultItem != null) {
      drivers.addAll(defaultItem!
          .map((conditional) => conditional.getDrivers())
          .expand((driver) => driver)
          .toList());
    }
    return drivers;
  }

  @override
  List<Logic> getReceivers() {
    final receivers = <Logic>[];
    for (final item in items) {
      receivers.addAll(item.then
          .map((conditional) => conditional.getReceivers())
          .expand((receiver) => receiver)
          .toList());
    }
    if (defaultItem != null) {
      receivers.addAll(defaultItem!
          .map((conditional) => conditional.getReceivers())
          .expand((receiver) => receiver)
          .toList());
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
  bool isMatch(LogicValue value) {
    if (expression.width != value.width) {
      throw Exception(
          'Value "$value" and expression "$expression" must be equal width.');
    }
    for (var i = 0; i < expression.width; i++) {
      if (expression.value[i] != value[i] && value[i] != LogicValue.z) {
        return false;
      }
    }
    return true;
  }
}

/// A conditional block to execute only if [condition] is satisified.
///
/// Intended for use with [IfBlock].
class ElseIf {
  /// A condition to match against to determine if [then] should be executed.
  final Logic condition;

  /// The [Conditional]s to execute if [condition] is satisfied.
  final List<Conditional> then;

  /// If [condition] is 1, then [then] will be executed.
  ElseIf(this.condition, this.then);

  /// If [condition] is 1, then [then] will be executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  ElseIf.s(Logic condition, Conditional then) : this(condition, [then]);
}

/// A conditional block to execute only if `condition` is satisified.
///
/// Intended for use with [IfBlock].
typedef Iff = ElseIf;

/// A conditional block to execute only if [condition] is satisified.
///
/// This should come last in [IfBlock].
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
/// is a little nicer
/// for long chains.
class IfBlock extends Conditional {
  /// A set of conditional items to check against for execution, in order.
  ///
  /// The first item should be an [Iff], and if an [Else] is included it must
  /// be the last item.  Any other items should be [ElseIf].  It is okay to
  /// make thefirst item an [ElseIf], it will act just like an [Iff].
  final List<Iff> iffs;

  /// Checks the conditions for [iffs] in order and executes the first one
  /// whose condition is enabled.
  IfBlock(this.iffs);

  @override
  void execute(Set<Logic> drivenSignals) {
    for (final iff in iffs) {
      if (driverValue(iff.condition)[0] == LogicValue.one) {
        for (final conditional in iff.then) {
          conditional.execute(drivenSignals);
        }
        break;
      } else if (driverValue(iff.condition)[0] != LogicValue.zero) {
        // x and z propagation
        for (final receiver in getReceivers()) {
          receiverOutput(receiver).put(driverValue(iff.condition)[0]);
          if (!drivenSignals.contains(receiver) || receiver.value.isValid) {
            drivenSignals.add(receiver);
          }
        }
        break;
      }
      // if it's 0, then continue searching down the path
    }
  }

  @override
  List<Conditional> getConditionals() =>
      iffs.map((iff) => iff.then).expand((conditional) => conditional).toList();

  @override
  List<Logic> getDrivers() {
    final drivers = <Logic>[];
    for (final iff in iffs) {
      drivers
        ..add(iff.condition)
        ..addAll(iff.then
            .map((conditional) => conditional.getDrivers())
            .expand((driver) => driver)
            .toList());
    }
    return drivers;
  }

  @override
  List<Logic> getReceivers() {
    final receivers = <Logic>[];
    for (final iff in iffs) {
      receivers.addAll(iff.then
          .map((conditional) => conditional.getReceivers())
          .expand((receiver) => receiver)
          .toList());
    }
    return receivers;
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final verilog = StringBuffer();
    for (final iff in iffs) {
      if (iff is Else && iff != iffs.last) {
        throw Exception('Else must come last in an IfBlock.');
      }
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
}

/// Represents a block of code to be conditionally executed, like `if`/`else`.
class If extends Conditional {
  /// [Conditional]s to be executed if [condition] is true.
  final List<Conditional> then;

  /// [Conditional]s to be executed if [condition] is not true.
  final List<Conditional> orElse;

  /// The condition that decides if [then] or [orElse] is executed.
  final Logic condition;

  /// If [condition] is 1, then [then] executes, otherwise [orElse] is executed.
  If(this.condition, {this.then = const [], this.orElse = const []});

  /// If [condition] is 1, then [then] is excutes,
  /// otherwise [orElse] is executed.
  ///
  /// Use this constructor when you only have a single [then] condition.
  /// An optional [orElse] condition can be passed.
  If.s(Logic condition, Conditional then, [Conditional? orElse])
      : this(condition, then: [then], orElse: orElse == null ? [] : [orElse]);

  @override
  List<Logic> getReceivers() {
    final allReceivers = <Logic>[];
    for (final element in then) {
      allReceivers.addAll(element.getReceivers());
    }
    for (final element in orElse) {
      allReceivers.addAll(element.getReceivers());
    }
    return allReceivers;
  }

  @override
  List<Logic> getDrivers() {
    final allDrivers = <Logic>[condition];
    for (final element in then) {
      allDrivers.addAll(element.getDrivers());
    }
    for (final element in orElse) {
      allDrivers.addAll(element.getDrivers());
    }
    return allDrivers;
  }

  @override
  List<Conditional> getConditionals() => [...then, ...orElse];

  @override
  void execute(Set<Logic> drivenSignals) {
    if (driverValue(condition)[0] == LogicValue.one) {
      for (final conditional in then) {
        conditional.execute(drivenSignals);
      }
    } else if (driverValue(condition)[0] == LogicValue.zero) {
      for (final conditional in orElse) {
        conditional.execute(drivenSignals);
      }
    } else {
      // x and z propagation
      for (final receiver in getReceivers()) {
        receiverOutput(receiver).put(driverValue(condition)[0]);
        if (!drivenSignals.contains(receiver) || receiver.value.isValid) {
          drivenSignals.add(receiver);
        }
      }
    }
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap,
      Map<String, String> outputsNameMap, String assignOperator) {
    final padding = Conditional.calcPadding(indent);
    final conditionName = inputsNameMap[driverInput(condition).name];
    final ifContents = then
        .map((conditional) => conditional.verilogContents(
            indent + 2, inputsNameMap, outputsNameMap, assignOperator))
        .join('\n');
    final elseContents = orElse
        .map((conditional) => conditional.verilogContents(
            indent + 2, inputsNameMap, outputsNameMap, assignOperator))
        .join('\n');
    var verilog = '''
${padding}if($conditionName) begin
$ifContents
${padding}end ''';
    if (orElse.isNotEmpty) {
      verilog += '''
else begin
$elseContents
${padding}end ''';
    }

    return '$verilog\n';
  }
}

/// Represents a single flip-flop with no reset.
class FlipFlop extends Module with CustomSystemVerilog {
  /// Name for the clk of this flop.
  late final String _clk;

  /// Name for the input of this flop.
  late final String _d;

  /// Name for the output of this flop.
  late final String _q;

  /// The clock, posedge triggered.
  Logic get clk => input(_clk);

  /// The input to the flop.
  Logic get d => input(_d);

  /// The output of the flop.
  Logic get q => output(_q);

  /// Constructs a flip flop which is positive edge triggered on [clk].
  FlipFlop(Logic clk, Logic d, {super.name = 'flipflop'}) {
    if (clk.width != 1) {
      throw Exception('clk must be 1 bit');
    }
    _clk = Module.unpreferredName('clk');
    _d = Module.unpreferredName('d');
    _q = Module.unpreferredName('q');
    addInput(_clk, clk);
    addInput(_d, d, width: d.width);
    addOutput(_q, width: d.width);
    _setup();
  }

  /// Performs setup for custom functional behavior.
  void _setup() {
    Sequential(clk, [q < d]);
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName,
      Map<String, String> inputs, Map<String, String> outputs) {
    if (inputs.length != 2 || outputs.length != 1) {
      throw Exception('FlipFlop has exactly two inputs and one output.');
    }
    final clk = inputs[_clk]!;
    final d = inputs[_d]!;
    final q = outputs[_q]!;
    return 'always_ff @(posedge $clk) $q <= $d;  // $instanceName';
  }
}
