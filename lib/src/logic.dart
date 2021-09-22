/// Copyright (C) 2021 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
/// 
/// logic.dart
/// Definition of basic signals, like Logic, and their behavior in the simulator, as well as basic operations on them
/// 
/// 2021 August 2
/// Author: Max Korbel <max.korbel@intel.com>
/// 

import 'dart:async';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';

//TODO: add support for arrays of signals for synthesizing to SV so that it's not verbose for large structures, along with for loops?

//TODO: add "in" like behavior, to see if some const is among a set of values of consts

/// Represents the event of a [Logic] changing value.
class LogicValueChanged {

  /// The newly updated value of the [Logic].
  final LogicValues newValue;

  /// The previous value of the [Logic].
  final LogicValues previousValue;

  LogicValueChanged(this.newValue, this.previousValue);

  @override
  String toString() => '$previousValue  -->  $newValue';
}


/// Represents a [Logic] that never changes value.
class Const extends Logic {

  /// Constructs a [Const] with the specified value.
  /// 
  /// If [val] is a [LogicValues], the [width] is inferred from it.
  /// Otherwise, if [width] is not specified, the default [width] is 1.
  /// If [fill] is set to `true`, the value is extended across [width] (like `'` in SystemVerilog).
  Const(dynamic val, {int? width, bool fill=false}) :
    super(
      name: 'const_$val',
      width: val is LogicValues ?
        val.length : 
        width ?? 1
  ) {
    put(val, fill: fill);
    _unassignable = true;
  }
}

//TODO: how to convert 0-width signals to SystemVerilog?

/// Represents a logical signal of any width which can change values.
class Logic {

  /// An internal counter for encouraging unique naming of unnamed signals.
  static int _signalIdx = 0;
  
  // special quiet flag to prevent <= and < where inappropriate
  bool _unassignable = false;
  void makeUnassignable() => _unassignable = true;

  /// The name of this signal.
  final String name;

  /// The current active value of this signal.
  LogicValues _currentValue;

  /// The last value of this signal before the [Simulator] tick.
  /// 
  /// This is useful for detecting when to trigger an edge.
  LogicValues _preTickValue;
  
  /// The number of bits in this signal.
  final int width;

  /// The current active value of this signal.
  LogicValues get value => _currentValue;

  //TODO: add a setter for value that calls put()?
  // set value(dynamic newValue) => put(newValue);

  /// The current active value of this signal if it has width 1, as a [LogicValue].
  /// 
  /// Throws an Exception if width is not 1.
  LogicValue get bit {
    if(width != 1) throw Exception('Logic width is not 1');
    return _currentValue[0];
  }

  /// The current valid active value of this signal as an [int].
  /// 
  /// Throws an exception if the signal is not valid or can't be represented as an [int].
  int get valueInt => value.toInt();

  /// The current valid active value of this signal as a [BigInt].
  /// 
  /// Throws an exception if the signal is not valid.
  BigInt get valueBigInt => value.toBigInt();

  /// Returns `true` iff the value of this signal is valid (no `x` or `z`).
  bool hasValidValue() => _currentValue.isValid;

  /// Returns true iff all bits of the current value are floating (`z`).
  bool isFloating() => value.isFloating;

  /// The `Logic` signal that is driving [this], if any.
  Logic? get srcConnection => _srcConnection;
  Logic? _srcConnection;

  /// An [Iterable] of all [Logic]s that are being directly driven by [this].
  Iterable<Logic> get dstConnections => UnmodifiableListView(_dstConnections);
  final Set<Logic> _dstConnections = {};

  /// Notifies [this] that [dstConnection] is now directly connected to the output of [this].
  void _registerConnection(Logic dstConnection) => _dstConnections.add(dstConnection);
  
  /// A [Stream] of [LogicValueChanged] events for every time the signal transitions at any time during a [Simulator] tick.
  /// 
  /// This event can occur more than once per edge, or even if there is no edge.
  Stream<LogicValueChanged> get glitch => _glitchController.stream;
  final StreamController<LogicValueChanged> _glitchController = StreamController<LogicValueChanged>.broadcast(sync: true);

  //TODO: consider using synchronous propogator instead of streams for glitch

  // final SynchronousPropagator<LogicValueChanged> _glitchController = SynchronousPropagator<LogicValueChanged>();
  // SynchronousEmitter<LogicValueChanged> get glitch => _glitchController.emitter;
  
  /// Controller for stable events that can be safely consumed at the end of a [Simulator] tick.
  final StreamController<LogicValueChanged> _changedController = StreamController<LogicValueChanged>.broadcast(sync: true);

  /// Tracks whether is being subscribed to by anything/anyone.
  bool _changedBeingWatched = false;

  //TODO: add tests for changed, posedge, negedge, etc. to make sure they dont break!

  /// A [Stream] of [LogicValueChanged] events which triggers at most once per [Simulator] tick, iff the value of the [Logic] has changed.
  Stream<LogicValueChanged> get changed {
    if(!_changedBeingWatched) {
      // only do these simulator subscriptions if someone has asked for them! saves performance!
      _changedBeingWatched = true;
      Simulator.preTick.listen((event) {
        _preTickValue = value;
      });
      Simulator.postTick.listen((event) {
        if(value != _preTickValue) {
          _changedController.add(LogicValueChanged(value, _preTickValue));
        }
      });
    }
    return _changedController.stream;
  }

  /// A [Stream] of [LogicValueChanged] events which triggers at most once per [Simulator] tick, iff the value of the [Logic] has changed from `0` to `1`.
  Stream<LogicValueChanged> get negedge => changed.where((args) => 
    width==1 && LogicValue.isNegedge(args.previousValue[0], args.newValue[0], ignoreInvalid: true));
  
  /// A [Stream] of [LogicValueChanged] events which triggers at most once per [Simulator] tick, iff the value of the [Logic] has changed from `1` to `0`.
  Stream<LogicValueChanged> get posedge => changed.where((args) => 
    width==1 && LogicValue.isPosedge(args.previousValue[0], args.newValue[0], ignoreInvalid: true));

  /// Triggers at most once, the next time that this [Logic] changes value at the end of a [Simulator] tick.
  Future<LogicValueChanged> get nextChanged => changed.first;
  
  /// Triggers at most once, the next time that this [Logic] changes value at the end of a [Simulator] tick from `0` to `1`.
  Future<LogicValueChanged> get nextPosedge => posedge.first;

  /// Triggers at most once, the next time that this [Logic] changes value at the end of a [Simulator] tick from `1` to `0`.
  Future<LogicValueChanged> get nextNegedge => negedge.first;

  /// The [Module] that this [Logic] exists within.
  /// 
  /// This only gets populated after its parent [Module], if it exists, has been built.
  Module? get parentModule => _parentModule;
  Module? _parentModule;
  
  //TODO: improve appropriate protection of parentModule

  /// Sets the value of [parentModule] to [newParent].
  /// 
  /// This should *only* be called by [Module.build()].
  @protected
  void setParentModule(Module? newParent) {
    // this should ONLY be called by Module build(), it is used to optimize the search
    _parentModule = newParent;
  }

  /// Returns true iff this signal is an input of its parent [Module].
  /// 
  /// Note: [parentModule] is not populated until after its parent [Module], if it exists, has been built.
  /// If no parent [Module] exists, returns false.
  bool get isInput => _parentModule?.isInput(this) ?? false;
  
  /// Returns true iff this signal is an output of its parent [Module].
  /// 
  /// Note: [parentModule] is not populated until after its parent [Module], if it exists, has been built.
  /// If no parent [Module] exists, returns false.
  bool get isOutput => _parentModule?.isOutput(this) ?? false;

  /// Returns true iff this signal is an input or output of its parent [Module].
  /// 
  /// Note: [parentModule] is not populated until after its parent [Module], if it exists, has been built.
  /// If no parent [Module] exists, returns false.
  bool get isPort => isInput || isOutput;
  
  /// Constructs a new [Logic] named [name] with [width] bits.
  /// 
  /// The default value for [width] is 1.  The [name] should be synthesizable to the desired output (e.g. SystemVerilog).
  Logic({String? name, this.width=1}) :
      name = name ?? 's${_signalIdx++}',
      assert(width >= 0), 
      _currentValue = LogicValues.filled(width, LogicValue.z),
      _preTickValue = LogicValues.filled(width, LogicValue.z);

  @override
  String toString() {
    //TODO: make this a prettier print, including full hierarchy from parents if available
    return 'Logic($width): $name';
  }

  /// Throws an exception if this [Logic] cannot be connected to another signal.
  void _assertConnectable() {
    if(_srcConnection != null) {
      throw Exception('This signal is already connected.');
      //TODO: this should be legal to do, but needs more safety around it (difficult)
    }
    if(_unassignable) throw Exception('This signal is unassignable.');
  }

  // TODO: prevent re-connection after build / after simulator has started?

  /// Connects this [Logic] directly to another [Logic].
  /// 
  /// Every time [other] transitions (`glitch`es), this signal will transition the same way.
  void gets(Logic other) {
    _assertConnectable();

    _connect(other);

    _srcConnection = other;
    other._registerConnection(this);
  }

  /// Handles the actual connection of this [Logic] to [other].
  void _connect(Logic other) {
    if(other.width != width) throw Exception('Bus widths must match.');

    _unassignable = true;

    if(value != other.value) put(other.value);
    other.glitch.listen((args) {
      put(other.value);
    });
  }

  /// Connects this [Logic] directly to another [Logic].
  /// 
  /// This is shorthand for [gets()].
  void operator <= (Logic other) => gets(other);

  /// Logical bitwise NOT.
  Logic operator ~ () => NotGate(this).out;
  /// Logical bitwise AND.
  Logic operator & (Logic other) =>  And2Gate(this, other).y;
  /// Logical bitwise OR.
  Logic operator | (Logic other) =>  Or2Gate(this, other).y;
  /// Logical bitwise XOR.
  Logic operator ^ (Logic other) =>  Xor2Gate(this, other).y;
  
  /// Addition.
  /// 
  /// WARNING: Signed math is not fully tested.
  Logic operator + (dynamic other) =>  Add(this, other).y;

  /// Subtraction.
  /// 
  /// WARNING: Signed math is not fully tested.
  Logic operator - (dynamic other) =>  Subtract(this, other).y;

  /// Multiplication.
  /// 
  /// WARNING: Signed math is not fully tested.
  Logic operator * (dynamic other) =>  Multiply(this, other).y;

  /// Division.
  /// 
  /// WARNING: Signed math is not fully tested.
  Logic operator / (dynamic other) =>  Divide(this, other).y;

  //TODO: implement shift operators for ints

  /// Arithmetic right-shift.
  Logic operator >>(Logic other)  => ARShift(this, other).y;
  /// Logical left-shift.
  Logic operator <<(Logic other)  => LShift(this, other).y;
  /// Logical right-shift.
  Logic operator >>>(Logic other) => RShift(this, other).y;
  /// Unary AND.
  Logic and() => AndUnary(this).y;
  /// Unary OR.
  Logic or() => OrUnary(this).y;
  /// Unary XOR.
  Logic xor() => XorUnary(this).y;
  /// Logical equality.
  Logic eq(dynamic other) => Equals(this, other).y;
  /// Less-than.
  Logic lt(dynamic other) => LessThan(this, other).y;
  /// Less-than-or-equal-to.
  Logic lte(dynamic other) => LessThanOrEqual(this, other).y;
  /// Greater-than.
  Logic operator >(dynamic other) => GreaterThan(this, other).y;
  /// Greater-than-or-equal-to.
  Logic operator >=(dynamic other) => GreaterThanOrEqual(this, other).y;

  /// Conditional assignment operator.
  /// 
  /// Represents conditionally asigning the value of another signal to this.
  /// Returns an instance of [ConditionalAssign] to be be passed to a [Conditional].
  ConditionalAssign operator < (dynamic other) {
    if(_unassignable) throw Exception('This signal is unassignable.');

    if(other is Logic) {
      return ConditionalAssign(this, other);
    } else {
      return ConditionalAssign(this, Logic(width: width)..put(other));
    }
  }

  //TODO: implement a conditionalassign with fill here

  /// Injects a value onto this signal in the current [Simulator] tick.
  /// 
  /// This function calls [put()] in [Simulator.injectAction()].
  void inject(dynamic val, {bool fill = false}) {
    Simulator.injectAction(() => put(val, fill: fill));
  }

  /// Keeps track of whether there is an active put, to detect reentrance.
  bool _isPutting = false;

  /// Puts a value onto this signal, which may or may not be picked up for [changed] in this [Simulator] tick.
  /// 
  /// This function is used for propogating glitches through connected signals.
  /// Use this function for custom definitions of [Module] behavior.
  /// 
  /// If [fill] is set, all bits of the signal gets set to [val], similar to `'` in SystemVerilog.
  void put(dynamic val, {bool fill=false}) async {
    //TODO: prevent re-assignment for _unassignable even via put/inject
    // this opens the opportunity to automate stuff like &1 if necessary
    LogicValues newValue;
    if(val is int) {
      if(fill) {
        newValue = LogicValues.filled(
          width,
          val == 0 ? LogicValue.zero:
            val == 1 ? LogicValue.one :
            throw Exception('Only can fill 0 or 1')
        );
      } else {
        newValue = LogicValues.fromInt(val, width);
      }
    } else if(val is BigInt) {
      if(fill) {
        newValue = LogicValues.filled(
          width,
          val == BigInt.zero ? LogicValue.zero:
            val == BigInt.one  ? LogicValue.one :
            throw Exception('Only can fill 0 or 1')
        );
      } else {
        newValue = LogicValues.fromBigInt(val, width);
      }
    } else if(val is bool) {
      newValue = LogicValues.fromInt(val ? 1 : 0, width);
    } else if(val is LogicValues) {
      newValue = val;
    } else if(val is List<LogicValue>) {
      if(val.length == 1 && (val[0]==LogicValue.x || val[0] == LogicValue.z || fill)) {
        newValue = LogicValues.filled(width, val[0]);
      } else if(fill) {
        throw Exception('Failed to fill.');
      } else {
        newValue = LogicValues.from(val);
      }
    } else if(val is LogicValue) {
      if(val == LogicValue.x || val == LogicValue.z || fill) {
        newValue = LogicValues.filled(width, val);
      } else {
        var logicVals = List<LogicValue>.filled(width, LogicValue.zero);
        logicVals[0] = val;
        newValue = LogicValues.from(logicVals);
      }
    } else {
      throw Exception('Unrecognized value to deposit on this signal.');
    }

    if(newValue.length != width) throw Exception('Updated value width mismatch');

    var cycleContention = false;
    if(_isPutting) {
      // if this is the result of a cycle, then contention!
      newValue = LogicValues.filled(width, LogicValue.x);
      cycleContention = true;
    }

    var _prevValue = _currentValue;
    if(_prevValue != newValue) {
      _currentValue = newValue;
    }

    // sends out a glitch if the value deposited has changed
    if(_currentValue != _prevValue) {
      
      if(cycleContention){
        // sync stream is not reentrant, so kill remaining tasks first, then propogate the X
        await glitch.drain();
        _isPutting = false;
      }

      _isPutting = true;
      _glitchController.add(LogicValueChanged(
        _currentValue,
        _prevValue
      ));
      _isPutting = false;
    }
  }

  /// Accesses the [index]th bit of this signal.
  Logic operator [] (int index) {
    return slice(index, index);
  }

  /// Accesses a subset of this signal from [startIndex] to [endIndex], both inclusive.
  Logic slice(int endIndex, int startIndex) {
    return BusSubset(this, startIndex, endIndex).subset;
  }


}
