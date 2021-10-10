/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// conditional.dart
/// Definitions of conditionallly executed hardware constructs (if/else statements, always_comb, always_ff, etc.)
/// 
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';


// TODO: consider X optimism in conditional statements in more detail, dont be too pessimistic if both inputs are equal
//  also need to add more tests around this (including @posedge(clk|reset))

// TODO: warnings for case statements not covering all cases

/// Represents a block of logic, similar to `always` blocks in SystemVerilog.
abstract class _Always extends Module with CustomSystemVerilog {

  /// A [List] of the [Conditional]s to execute.
  final List<Conditional> conditionals;
  
  final Map<Logic,Logic> _assignedReceiverToOutputMap = {};
  final Map<Logic,Logic> _assignedDriverToInputMap = {};

  _Always(this.conditionals, {String name='always'}) : super(name: name) {

    //TODO: need to do some check that the same conditional is not used multiple times in the same always or in different always
    
    // create a registration of all inputs and outputs of this module
    var idx = 0;
    for(var conditional in conditionals) {
      for(var driver in conditional.getDrivers()) {
        if(!_assignedDriverToInputMap.containsKey(driver)) {
          var inputName = Module.unpreferredName('in$idx');
          addInput(inputName, driver, width: driver.width);
          _assignedDriverToInputMap[driver] = input(inputName);
          idx++;
        }
      }
      for(var receiver in conditional.getReceivers()) {
        if(!_assignedReceiverToOutputMap.containsKey(receiver)) {
          var outputName = Module.unpreferredName('out$idx');
          addOutput(outputName, width: receiver.width);
          _assignedReceiverToOutputMap[receiver] = output(outputName);
          receiver <= output(outputName);
          idx++;
        }
      }

      // share the registration information down
      conditional._updateAssignmentMaps(_assignedReceiverToOutputMap, _assignedDriverToInputMap);
    }
  }

  String _alwaysContents(Map<String,String> inputsNameMap, Map<String,String> outputsNameMap, String assignOperator) {
    var contents = '';
    for (var conditional in conditionals) {
      contents += conditional.verilogContents(1, inputsNameMap, outputsNameMap, assignOperator) + '\n';
    }
    return contents;
  }

  /// The "always" part of the `always` block when generating SystemVerilog.
  /// 
  /// For example, `always_comb` or `always_ff`.
  @protected String alwaysVerilogStatement(Map<String,String> inputs);

  /// The assignment operator to use when generating SystemVerilog.
  /// 
  /// For example `=` or `<=`.
  @protected String assignOperator();

  @override
  String instantiationVerilog(String instanceType, String instanceName, Map<String,String> inputs, Map<String,String> outputs) {
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
class Combinational extends _Always {
  
  Combinational(List<Conditional> conditionals, {String name = 'always_comb'}) : super(conditionals, name:name) {
    _execute(); // for initial values
    for (var element in _assignedDriverToInputMap.keys) {
      element.glitch.listen((args) {      
        _execute();
      });
    }
  }
  
  /// Keeps track of whether this block is already mid-execution, in order to detect reentrance.
  bool _isExecuting = false;

  /// Performs the functional behavior of this block.
  void _execute() {
    if(_isExecuting) {
      // this combinational is already executing, which means an input has changed as a result
      // of some output of this combinational changing.  this is imperative style, so don't loop
      return;
    }

    _isExecuting = true;

    // combinational must always drive all outputs or else you get X!
    //TODO: could be more efficient if we only put X's on non-driven outputs (based on execute return)
    for (var element in _assignedReceiverToOutputMap.values) {
      element.put(LogicValue.x, fill:true);
    }

    for (var element in conditionals) {element.execute();}

    _isExecuting = false;
  }

  @override String alwaysVerilogStatement(Map<String,String> inputs) => 'always_comb';
  @override String assignOperator() => '=';

}


/// Represents a block of sequential logic.
/// 
/// This is similar to an `always_ff` block in SystemVerilog.
class FF extends _Always {
  
  /// The name of the clock for this block.
  final String _clk = Module.unpreferredName('clk');
  
  /// The clock used in this block.
  Logic get clk => input(_clk);

  FF(Logic clk, List<Conditional> conditionals, {String name = 'always_ff'}) : super(conditionals, name:name) {
    if(clk.width > 1) throw Exception('clk must be 1 bit');
    addInput(_clk, clk);
    _setup();
  }

  final Map<Logic, LogicValues> _inputToPreTickInputValuesMap = {};
  late LogicValue _preTickClkValue;

  /// Performs setup steps for custom functional behavior of this block.
  void _setup() {
    Simulator.preTick.listen((args) {
      for(var driverInput in _assignedDriverToInputMap.values) {
        _inputToPreTickInputValuesMap[driverInput] = driverInput.value;
      }
      for (var element in conditionals) { element._updateOverrideMap(_inputToPreTickInputValuesMap); }
      _preTickClkValue = clk.bit;
    });
    Simulator.clkStable.listen((args) {
      if(!clk.bit.isValid || !_preTickClkValue.isValid) {
        for (var receiverOutput in _assignedReceiverToOutputMap.values) {
          receiverOutput.put(LogicValue.x);
        }
      } else if(LogicValue.isPosedge(_preTickClkValue, clk.bit)) {
        var allDrivenSignals = <Logic>[];
        for (var element in conditionals) {
          allDrivenSignals.addAll(element.execute());
        }
        if(allDrivenSignals.length != allDrivenSignals.toSet().length) {
          throw Exception('FF drove the same signal multiple times.');
        }
      }
    });
  }

  @override String alwaysVerilogStatement(Map<String,String> inputs) => 'always_ff @(posedge ${inputs[_clk]})';
  @override String assignOperator() => '<=';

}

/// Represents an some logical assignments or actions that will only happen under certain conditions.
abstract class Conditional {
  
  /// A [Map] from receiver [Logic] signals passed into this [Conditional] to the appropriate output logic port.
  late Map<Logic,Logic> _assignedReceiverToOutputMap;

  /// A [Map] from driver [Logic] signals passed into this [Conditional] to the appropriate input logic port.
  late Map<Logic,Logic> _assignedDriverToInputMap;
  
  /// A [Map] of override [LogicValues]s for driver [Logic]s of this [Conditional].
  /// 
  /// This is used for things like [FF]'s pre-tick values.
  Map<Logic,LogicValues> _driverValueOverrideMap = {};

  /// Updates the values of [_assignedReceiverToOutputMap] and [_assignedDriverToInputMap] and
  /// passes them down to all sub-[Conditional]s as well.
  void _updateAssignmentMaps(
      Map<Logic,Logic> assignedReceiverToOutputMap,
      Map<Logic,Logic> assignedDriverToInputMap,
  ) {
    _assignedReceiverToOutputMap = assignedReceiverToOutputMap;
    _assignedDriverToInputMap = assignedDriverToInputMap;
    getConditionals().forEach((element) {
      element._updateAssignmentMaps(assignedReceiverToOutputMap, assignedDriverToInputMap);
    });
  }

  /// Updates the value of [_driverValueOverrideMap] and passes it down to all
  /// sub-[Conditional]s as well.
  void _updateOverrideMap(Map<Logic,LogicValues> driverValueOverrideMap) {
    // this is for always_ff pre-tick values
    _driverValueOverrideMap = driverValueOverrideMap;
    getConditionals().forEach((element) {
      element._updateOverrideMap(driverValueOverrideMap);
    });
  }

  /// Gets the value that should be used for execution for the input port associated with [driver].
  @protected LogicValues driverValue(Logic driver) {
    return _driverValueOverrideMap.containsKey(driverInput(driver)) ? 
      _driverValueOverrideMap[driverInput(driver)]! : _assignedDriverToInputMap[driver]!.value;
  }

  /// Gets the input port associated with [driver].
  @protected Logic driverInput(Logic driver) {
    return _assignedDriverToInputMap[driver]!;
  }

  /// Gets the output port associated with [receiver].
  @protected Logic receiverOutput(Logic receiver) {
    return _assignedReceiverToOutputMap[receiver]!;
  }

  /// Executes the functionality represented by this [Conditional].
  /// 
  /// Returns a [List] of all [Logic] signals which were driven during execution.
  @protected List<Logic> execute();

  /// Lists *all* receivers, recursively including all sub-[Conditional]s receivers.
  List<Logic> getReceivers();

  /// Lists *all* drivers, recursively including all sub-[Conditional]s drivers.
  List<Logic> getDrivers();

  /// Lists of *all* [Conditional]s contained within this [Conditional] (not including itself).
  /// 
  /// Recursively calls down through sub-[Conditional]s.
  List<Conditional> getConditionals();

  /// Returns a [String] of SystemVerilog to be used in generated output.
  /// 
  /// The [indent] is used for pretty-printing, and should generally be incremented for sub-[Conditional]s.
  /// The [inputsNameMap] and [outputsNameMap] are a mapping from port names to SystemVerilog variable
  /// names for inputs and outputs, respectively.  The [assignOperator] is the SystemVerilog operator
  /// that should be used for any assignments within this [Conditional].
  String verilogContents(int indent, Map<String,String> inputsNameMap, Map<String,String> outputsNameMap, String assignOperator);

  /// Calculates an amount of padding to provie at the beginning of each new line based on [indent].
  static String calcPadding(int indent) => List.filled(indent, '  ').join();
}

/// An assignment that only happens under certain conditions.
/// 
/// [Logic] has a short-hand for creating [ConditionalAssign] via the `<` operator.
class ConditionalAssign extends Conditional {

  /// The input to this assignment.
  final Logic receiver;

  /// The output of this assignment.
  final Logic driver;
  
  ConditionalAssign(this.receiver, this.driver) {
    if(driver.width != receiver.width) throw Exception('Widths must match');
  }

  //TODO: how to handle a conditional fill a-la '1

  @override List<Logic> getReceivers() => [receiver];
  @override List<Logic> getDrivers() => [driver];
  @override List<Conditional> getConditionals() => [];

  @override
  List<Logic> execute() {
    // print('>>Assigning $receiver [value ${receiver.value}] to $driver [value ${driver.value}]');
    receiverOutput(receiver).put(driverValue(driver));
    return [receiver];
  }

  @override
  String verilogContents(int indent, Map<String,String> inputsNameMap, Map<String,String> outputsNameMap, String assignOperator) {
    var padding = Conditional.calcPadding(indent);
    var driverName = inputsNameMap[driverInput(driver).name]!;
    var receiverName = outputsNameMap[receiverOutput(receiver).name]!;
    return '$padding$receiverName $assignOperator $driverName;';
  }
}

/// Represents a single case within a [Case] block.
class CaseItem {
  /// The value to match against.
  final Logic value;

  /// A [List] of [Conditional]s to execute when [value] is matched.
  final List<Conditional> then;

  CaseItem(this.value, this.then);
}

/// Controls characteristics about [Case] blocks.
/// 
/// The default type is [none].  The [unique] and [priority] values have 
/// behavior similar to what is implemented in SystemVerilog.
/// 
/// [priority] indicates that the decisions must be executed in the same order
/// that they are listed, and that every legal scenario is included.  An exception
/// will be thrown if there is no match to a scenario.
/// 
/// [unique] indicates that for a given expression, only one item will match.  If
/// multiple items match the expression, an exception will be thrown.  If there is no
/// match and no default item, an exception will also be thrown.
enum ConditionalType {none, unique, priority}

/// A block of [CaseItem]s where only the one with a matching [CaseItem.value] is executed.
/// 
/// Searches for which of [items] appropriately matches [expression], then executes the 
/// matching [CaseItem].  If [defaultItem] is specified, and no other item matches, then
/// that one is executed.  Use [conditionalType] to modify behavior in ways similar to
/// what is available in SystemVerilog.
class Case extends Conditional {

  /// A logical signal to match against.
  final Logic expression;

  /// An ordered collection of [CaseItem]s to search through for a match to [expression].
  final List<CaseItem> items;

  /// The default to execute when there was no match with any other [CaseItem]s.
  final List<Conditional>? defaultItem;

  /// The type of case block this is, for special attributes (e.g. [ConditionalType.unique],
  /// [ConditionalType.priority]).
  /// 
  /// See [ConditionalType] for more details.
  final ConditionalType conditionalType;
  Case(this.expression, this.items, {this.defaultItem, this.conditionalType=ConditionalType.none});
  
  /// Returns true iff [value] matches the expressions current value.
  @protected
  bool isMatch(LogicValues value) {
    return expression.value == value;
  }

  /// Returns the SystemVerilog keyword to represent this case block.
  @protected
  String get caseType => 'case';

  @override
  List<Logic> execute() {
    var drivenLogics = <Logic>[];

    //TODO: what about for CaseZ where epxressions can have Z?  BUG?
    if(!expression.value.isValid) {
      // if expression has X or Z, then propogate X's!
      getReceivers().forEach((receiver) {
        receiverOutput(receiver).put(LogicValue.x);
      });
      return [];
    }

    var foundMatch = false;

    for(var item in items) {
      // match on the first matchinig item
      if(isMatch(item.value.value)) {
        for(var conditional in item.then) {
          drivenLogics.addAll(conditional.execute());
        }
        if(foundMatch && conditionalType == ConditionalType.unique) {
          //TODO: replace this with a logger message
          throw Exception('Unique case statement had multiple matching cases');
        }

        foundMatch = true;

        if(foundMatch && conditionalType != ConditionalType.unique) {
          break;
        } 
      }
    }

    // no items matched
    if(!foundMatch && defaultItem != null) {
      for(var conditional in defaultItem!) {
        drivenLogics.addAll(conditional.execute());
      }
    } else if(!foundMatch && (conditionalType == ConditionalType.unique || conditionalType == ConditionalType.priority)) {
      throw Exception('$conditionalType case statement had no matching case.');
    }

    return drivenLogics;
  }

  @override
  List<Conditional> getConditionals() {
    return [
      ...items.map((item) => item.then).expand((conditional) => conditional).toList(),
      ...defaultItem ?? []
    ];
  }

  @override
  List<Logic> getDrivers() {
    var drivers = <Logic>[expression];
    for(var item in items) {
      drivers.add(item.value);
      drivers.addAll(
        item.then.map((conditional) => conditional.getDrivers())
          .expand((driver) => driver).toList()
      );
    }
    if(defaultItem != null) {
      drivers.addAll(
        defaultItem!.map((conditional) => conditional.getDrivers())
        .expand((driver) => driver).toList()
      );
    }
    return drivers;
  }

  @override
  List<Logic> getReceivers() {
    var receivers = <Logic>[];
    for(var item in items) {
      receivers.addAll(
        item.then.map((conditional) => conditional.getReceivers())
          .expand((receiver) => receiver).toList()
      );
    }
    if(defaultItem != null) {
      receivers.addAll(
        defaultItem!.map((conditional) => conditional.getReceivers())
        .expand((receiver) => receiver).toList()
      );
    }
    return receivers;
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap, Map<String, String> outputsNameMap, String assignOperator) {
    var padding = Conditional.calcPadding(indent);
    var expressionName = inputsNameMap[driverInput(expression).name];
    var caseHeader = caseType;
    if(conditionalType == ConditionalType.priority) {
      caseHeader = 'priority $caseType';
    } else if(conditionalType == ConditionalType.unique) {
      caseHeader = 'unique $caseType';
    }
    var verilog = '$padding$caseHeader ($expressionName) \n';
    var subPadding = Conditional.calcPadding(indent+2);
    for(var item in items) {
      var conditionName = inputsNameMap[driverInput(item.value).name];
      var caseContents = item.then.map((conditional) => conditional.verilogContents(indent+4, inputsNameMap, outputsNameMap, assignOperator)).join('\n');
      verilog += '''$subPadding$conditionName : begin
$caseContents
${subPadding}end
''';
    }
    if(defaultItem != null) {
      var defaultCaseContents = defaultItem!.map((conditional) => conditional.verilogContents(indent+4, inputsNameMap, outputsNameMap, assignOperator)).join('\n');
      verilog += '''${subPadding}default : begin
$defaultCaseContents
${subPadding}end
''';
    }
    verilog += '${padding}endcase\n';
    
    return verilog;
  }
  
}

/// A special version of [Case] which can do wildcard matching via `z` in the expression.
/// 
/// Any `z` in the value of a [CaseItem] will act as a wildcard. 
/// 
/// Does not support SystemVerilog's `?` syntax, which is exactly functionally equivalent to `z` syntax.
class CaseZ extends Case {
  CaseZ(Logic expression, List<CaseItem> items, {List<Conditional>? defaultItem, ConditionalType conditionalType=ConditionalType.none}):
    super(expression, items, defaultItem: defaultItem, conditionalType: conditionalType);
  
  @override
  String get caseType => 'casez';

  //TODO: should CaseZ force Const in items? Otherwise, what if a floating signal came into the case statement??
  // or at least don't do wildcard for non-const items?

  //TODO: what if there's an X in the expression? should throw exception!
  @override
  bool isMatch(LogicValues value) {
    if(expression.width != value.length) throw Exception('Value and expression must be equal width.');
    for(var i = 0; i < expression.width; i++) {
      if(expression.value[i] != value[i] && value[i] != LogicValue.z) {
        return false;
      }
    }
    return true;
  }
}

/// A conditional block to execute only if [condition] is satisified.
/// 
/// Intended for use with [IfBlock].
class Iff {
  /// A condition to match against to determine if [then] should be executed.
  final Logic condition;

  /// The [Conditional]s to execute if [condition] is satisfied.
  final List<Conditional> then;

  Iff(this.condition, this.then);
}

/// A conditional block to execute only if [condition] is satisified.
///
/// Intended for use with [IfBlock].
class ElseIf extends Iff {
  ElseIf(Logic condition, List<Conditional> then) : super(condition, then);
}

/// A conditional block to execute only if [condition] is satisified.
/// 
/// This should come last in [IfBlock].
class Else extends Iff {
  Else(List<Conditional> then) : super(Const(1), then);
}

/// Represents a chain of blocks of code to be conditionally executed, like `if`/`else if`/`else`.
/// 
/// This is functionally equivalent to chaining together [If]s, but this syntax is a little nicer
/// for long chains.
class IfBlock extends Conditional {
  
  /// A set of conditional items to check against for execution, in order.
  /// 
  /// The first item *must* be an [Iff], and if an [Else] is included it must 
  /// be the last item.  Any other items should be [ElseIf].
  final List<Iff> iffs;

  IfBlock(this.iffs);

  @override
  List<Logic> execute() {
    var drivenLogics = <Logic>[];

    for(var iff in iffs) {
      if(driverValue(iff.condition)[0] == LogicValue.one) {
        for(var conditional in iff.then) {
          drivenLogics.addAll(conditional.execute());
        }
        break;
      } else if(driverValue(iff.condition)[0] != LogicValue.zero) {
        // x and z propagation
        getReceivers().forEach((receiver) {
          receiverOutput(receiver).put(driverValue(iff.condition)[0]);
        });
        break;
      }
      // if it's 0, then continue searching down the path
    }
    return drivenLogics;
  }

  @override
  List<Conditional> getConditionals() {
    return iffs.map((iff) => iff.then).expand((conditional) => conditional).toList();
  }

  @override
  List<Logic> getDrivers() {
    var drivers = <Logic>[];
    for(var iff in iffs) {
      drivers.add(iff.condition);
      drivers.addAll(
        iff.then.map((conditional) => conditional.getDrivers())
          .expand((driver) => driver).toList()
      );
    }
    return drivers;
  }

  @override
  List<Logic> getReceivers() {
    var receivers = <Logic>[];
    for(var iff in iffs) {
      receivers.addAll(
        iff.then.map((conditional) => conditional.getReceivers())
          .expand((receiver) => receiver).toList()
      );
    }
    return receivers;
  }

  @override
  String verilogContents(int indent, Map<String, String> inputsNameMap, Map<String, String> outputsNameMap, String assignOperator) {
    var padding = Conditional.calcPadding(indent);
    var verilog = '';
    for(var iff in iffs) {
      if(iff is Else && iff != iffs.last) throw Exception('Else must come last in an IfBlock');
      var header = iff == iffs.first ? 'if' :
                   iff is ElseIf ? 'else if' :
                   iff is Else ? 'else' :
                   throw Exception('Unsupported Iff');
      
      var conditionName = inputsNameMap[driverInput(iff.condition).name];
      var ifContents = iff.then.map((conditional) => conditional.verilogContents(indent+2, inputsNameMap, outputsNameMap, assignOperator)).join('\n');
      var condition = iff is! Else ? '($conditionName)' : '';
      verilog += '''$padding$header$condition begin
$ifContents
${padding}end ''';
    }
    verilog += '\n';
    
    return verilog;
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

  If(this.condition, {this.then = const [], this.orElse = const []});

  @override
  List<Logic> getReceivers() {
    var allReceivers = <Logic>[];
    for (var element in then) {allReceivers.addAll(element.getReceivers());}
    for (var element in orElse) {allReceivers.addAll(element.getReceivers());}
    return allReceivers;
  }

  @override
  List<Logic> getDrivers() {
    var allDrivers = <Logic>[condition];
    for (var element in then) {allDrivers.addAll(element.getDrivers());}
    for (var element in orElse) {allDrivers.addAll(element.getDrivers());}
    return allDrivers;
  }

  @override List<Conditional> getConditionals() => [...then, ...orElse];

  @override
  List<Logic> execute() {
    var drivenLogics = <Logic>[];
    if(driverValue(condition)[0] == LogicValue.one) {
      for(var conditional in then) {
        drivenLogics.addAll(conditional.execute());
      }
    } else if(driverValue(condition)[0] == LogicValue.zero) {
      for(var conditional in orElse) {
        drivenLogics.addAll(conditional.execute());
      }
    } else {
      // x and z propagation
      getReceivers().forEach((receiver) {
        receiverOutput(receiver).put(driverValue(condition)[0]);
      });
    }
    return drivenLogics;
  }

  @override
  String verilogContents(int indent, Map<String,String> inputsNameMap, Map<String,String> outputsNameMap, String assignOperator) {
    var padding = Conditional.calcPadding(indent);
    var conditionName = inputsNameMap[driverInput(condition).name];
    var ifContents = then.map((conditional) => conditional.verilogContents(indent+2, inputsNameMap, outputsNameMap, assignOperator)).join('\n');
    var elseContents = orElse.map((conditional) => conditional.verilogContents(indent+2, inputsNameMap, outputsNameMap, assignOperator)).join('\n');
    var verilog = '''${padding}if($conditionName) begin
$ifContents
${padding}end ''';
    if(orElse.isNotEmpty) {
      verilog += '''else begin
$elseContents
${padding}end ''';
    }
    verilog += '\n';
    
    return verilog;
  }
}

/// Represents a single flip-flop with no reset.
class FlipFlop extends Module with CustomSystemVerilog {

  /// Name for a port of this module. 
  late final String _clk, _d, _q;

  /// The clock, posedge triggered.
  Logic get clk => input(_clk);

  /// The input to the flop.
  Logic get d => input(_d);

  /// The output of the flop.
  Logic get q => output(_q);

  FlipFlop(Logic clk, Logic d, {String name='flipflop'}) : super(name: name) {
    if(clk.width > 1) throw Exception('clk must be 1 bit');
    _clk = Module.unpreferredName('clk');
    _d = Module.unpreferredName('d');
    _q = Module.unpreferredName('q');
    addInput(_clk, clk);
    addInput(_d, d, width: d.width);
    addOutput(_q, width: d.width);
    _setup();
  }

  late LogicValues _preTickValue; // logic or bus value, so dynamic
  late LogicValue _preTickClkValue;

  /// Performs setup for custom functional behavior.
  void _setup() {
    Simulator.preTick.listen((args) {
      _preTickValue = d.value;
      _preTickClkValue = clk.bit;
    });
    Simulator.clkStable.listen((args) {
      if(!_preTickClkValue.isValid || !clk.bit.isValid) {
        q.put(LogicValue.x);
      } else if(LogicValue.isPosedge(_preTickClkValue, clk.bit)) {
        q.put(_preTickValue);
      }
    });
  }

  @override
  String instantiationVerilog(String instanceType, String instanceName, Map<String,String> inputs, Map<String,String> outputs) {
    if(inputs.length != 2 || outputs.length != 1) {
      throw Exception('FlipFlop has exactly two inputs and one output.');
    }
    var clk = inputs['clk']!;
    var d = inputs['d']!;
    var q = outputs['q']!;
    return 'always_ff @(posedge $clk) $q <= $d;  // $instanceName';
  }
}
