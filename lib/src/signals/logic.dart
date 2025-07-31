// Copyright (C) 2021-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logic.dart
// Definition of basic signals, like Logic, and their behavior in the
// simulator, as well as basic operations on them
//
// 2021 August 2
// Author: Max Korbel <max.korbel@intel.com>,
//         Rahul Gautham Putcha <rahul.gautham.putcha@intel.com>

part of 'signals.dart';

/// Represents a logical signal of any width which can change values.
class Logic {
  // A special quiet flag to prevent `<=` and `<` where inappropriate
  bool _unassignable = false;

  /// The reason why a signal is unassignable, if provided when
  /// [makeUnassignable] is set.
  String? _unassignableReason;

  /// Makes it so that this signal cannot be assigned by any full (`<=`) or
  /// conditional (`<`) assignment.
  ///
  /// Optionally, a [reason] may be provided for why it cannot be assigned. If a
  /// prior reason had been provided, this will overwrite it.
  void makeUnassignable({String? reason}) {
    _unassignable = true;
    _unassignableReason = reason;
  }

  /// The name of this signal.
  final String name;

  /// The [_Wire] which holds the current value and listeners for this [Logic].
  ///
  /// May be a shared object between multiple [Logic]s.
  _Wire _wire;

  /// The number of bits in this signal.
  int get width => _wire.width;

  /// The current active value of this signal.
  LogicValue get value => _wire.value;

  /// The current active value of this signal if it has width 1, as
  /// a [LogicValue].
  ///
  /// Throws an Exception if width is not 1.
  @Deprecated('Use `value` instead.'
      '  Check `width` separately to confirm single-bit.')
  LogicValue get bit => value.bit;

  /// The current valid active value of this signal as an [int].
  ///
  /// Throws an exception if the signal is not valid or can't be represented
  /// as an [int].
  @Deprecated('Use value.toInt() instead.')
  int get valueInt => value.toInt();

  /// The current valid active value of this signal as a [BigInt].
  ///
  /// Throws an exception if the signal is not valid.
  @Deprecated('Use value.toBigInt() instead.')
  BigInt get valueBigInt => value.toBigInt();

  /// Returns `true` iff the value of this signal is valid (no `x` or `z`).
  @Deprecated('Use value.isValid instead.')
  bool hasValidValue() => value.isValid;

  /// Returns `true` iff *all* bits of the current value are floating (`z`).
  @Deprecated('Use value.isFloating instead.')
  bool isFloating() => value.isFloating;

  /// The [Logic] signal that is driving `this`, if any.
  ///
  /// If there are multiple drivers (e.g. this is an instance of a special
  /// type/subclass of [Logic]), this will be `null` and [srcConnections] can be
  /// referenced to find all drivers. A simple [Logic] will always have either
  /// one or no driver.
  Logic? get srcConnection => _srcConnection;
  Logic? _srcConnection;

  /// An [Iterable] of all [Logic]s that are being directly driven by `this`.
  late final Iterable<Logic> dstConnections =
      UnmodifiableSetView(_dstConnections);
  late final Set<Logic> _dstConnections = {};

  /// Notifies `this` that [dstConnection] is now directly connected to the
  /// output of `this`.
  void _registerConnection(Logic dstConnection) =>
      _dstConnections.add(dstConnection);

  /// A stream of [LogicValueChanged] events for every time the signal
  /// transitions at any time during a [Simulator] tick.
  ///
  /// This event can occur more than once per edge, or even if there is no edge.
  SynchronousEmitter<LogicValueChanged> get glitch => _wire.glitch;

  /// A [Stream] of [LogicValueChanged] events which triggers at most once
  /// per [Simulator] tick, iff the value of the [Logic] has changed.
  Stream<LogicValueChanged> get changed => _wire.changed;

  /// A [Stream] of [LogicValueChanged] events which triggers at most once
  /// per [Simulator] tick, iff the value of the [Logic] has changed
  /// from `1` to `0`.
  ///
  /// Throws an exception if [width] is not `1`.
  Stream<LogicValueChanged> get negedge => _wire.negedge;

  /// A [Stream] of [LogicValueChanged] events which triggers at most once
  /// per [Simulator] tick, iff the value of the [Logic] has changed
  /// from `0` to `1`.
  ///
  /// Throws an exception if [width] is not `1`.
  Stream<LogicValueChanged> get posedge => _wire.posedge;

  /// Triggers at most once, the next time that this [Logic] changes
  /// value at the end of a [Simulator] tick.
  Future<LogicValueChanged> get nextChanged => _wire.nextChanged;

  /// Triggers at most once, the next time that this [Logic] changes
  /// value at the end of a [Simulator] tick from `0` to `1`.
  ///
  /// Throws an exception if [width] is not `1`.
  Future<LogicValueChanged> get nextPosedge => _wire.nextPosedge;

  /// Triggers at most once, the next time that this [Logic] changes
  /// value at the end of a [Simulator] tick from `1` to `0`.
  ///
  /// Throws an exception if [width] is not `1`.
  Future<LogicValueChanged> get nextNegedge => _wire.nextNegedge;

  /// The [value] of this signal before the most recent [Simulator.tick] had
  /// completed. It will be `null` before the first tick after this signal is
  /// created.
  ///
  /// If this is called mid-tick, it will be the value from before the tick
  /// started. If this is called post-tick, it will be the value from before
  /// that last tick started.
  ///
  /// This is useful for querying the value of a signal in a testbench before
  /// some change event occurred, for example sampling a signal before a clock
  /// edge for code that was triggered on that edge.
  ///
  /// Note that if a signal is connected to another signal, the listener may
  /// be reset.
  LogicValue? get previousValue => _wire.previousValue;

  /// The [Module] that this [Logic] exists within.
  ///
  /// For internal signals, this only gets populated after its parent [Module],
  /// if it exists, has been built.  Ports (both input and output) have this
  /// populated at the time of creation.
  Module? get parentModule => _parentModule;
  Module? _parentModule;

  /// If this is a part of a [LogicStructure], the structure which this is
  /// a part of.  Otherwise, `null`.
  LogicStructure? get parentStructure => _parentStructure;
  LogicStructure? _parentStructure;

  /// True if this is a member of a [LogicArray].
  bool get isArrayMember => parentStructure is LogicArray;

  /// Returns the name relative to the [parentStructure]-defined hierarchy, if
  /// one exists.  Otherwise, this is the same as [name].
  ///
  /// This is useful for finding the name of a signal as an element of a root
  /// [LogicArray] or [LogicStructure].
  String get structureName {
    if (parentStructure != null) {
      if (parentStructure is LogicArray) {
        return '${parentStructure!.structureName}[${arrayIndex!}]';
      } else {
        return '${parentStructure!.structureName}.$name';
      }
    } else {
      return name;
    }
  }

  /// If this is a part of a [LogicArray], the index within that array.
  /// Othwerise, returns `null`.
  ///
  /// If [isArrayMember] is true, this will be non-`null`.
  int? get arrayIndex => _arrayIndex;
  int? _arrayIndex;

  /// Sets the value of [parentModule] to [newParentModule].
  ///
  /// This should *only* be called by [Module.build].  It is used to
  /// optimize search.
  @internal
  set parentModule(Module? newParentModule) {
    assert(_parentModule == null || _parentModule == newParentModule,
        'Should only set parent module once.');

    _parentModule = newParentModule;
  }

  /// Returns true iff this signal is an input of its parent [Module].
  late final bool isInput =
      // this can be cached because parentModule is set at port creation
      parentModule?.isInput(this) ?? false;

  /// Returns true iff this signal is an output of its parent [Module].
  late final bool isOutput =
      // this can be cached because parentModule is set at port creation
      parentModule?.isOutput(this) ?? false;

  /// Returns true iff this signal is an inOut of its parent [Module].
  late final bool isInOut =
      // this can be cached because parentModule is set at port creation
      parentModule?.isInOut(this) ?? false;

  /// Indicates whether this signal behaves like a [LogicNet], allowing multiple
  /// drivers.
  bool get isNet => false;

  /// All [Logic]s driving `this`, if any.
  ///
  /// For a simple [Logic], this will simply be an [Iterable] containing either
  /// nothing (if no driver), or one element equal to [srcConnection]. If there
  /// are multiple drivers (e.g. this is an instance of a special type/subclass
  /// of [Logic]), then there may be multiple drivers.
  late final Iterable<Logic> srcConnections =
      UnmodifiableListView(_srcConnections);
  // [if (srcConnection != null) srcConnection!];
  late final List<Logic> _srcConnections = [];

  /// Returns true iff this signal is an input, output, or inOut of its parent
  /// [Module].
  late final bool isPort = isInput || isOutput || isInOut;

  /// Controls the naming (and renaming) preferences of this signal in generated
  /// outputs.
  final Naming naming;

  /// Constructs a new [Logic] named [name] with [width] bits.
  ///
  /// The default value for [width] is 1.  The [name] should be sanitary
  /// (variable rules for languages such as SystemVerilog).
  ///
  /// The [naming] and [name], if unspecified, are chosen based on the rules in
  /// [Naming.chooseNaming] and [Naming.chooseName], respectively.
  Logic({
    String? name,
    int width = 1,
    Naming? naming,
  }) : this._(
          name: name,
          width: width,
          naming: naming,
        );

  /// A cloning utility for [clone] and [named].
  Logic _clone({String? name, Naming? naming}) =>
      (isNet ? LogicNet.new : Logic.new)(
          name: name ?? this.name,
          naming: Naming.chooseCloneNaming(
              originalName: this.name,
              newName: name,
              originalNaming: this.naming,
              newNaming: naming),
          width: width);

  /// Makes a copy of `this`, optionally with the specified [name], but the same
  /// [width].
  ///
  /// It is expected that any implementation will override this in a way that
  /// returns the same type as itself.
  @mustBeOverridden
  Logic clone({String? name}) => _clone(name: name);

  /// Makes a new [Logic] with the provided [name] and optionally [naming], then
  /// assigns it to be driven by `this`.
  ///
  /// This is a useful utility for naming the result of some hardware
  /// construction without separately declaring a new named signal and then
  /// assigning.  For example:
  ///
  /// ```dart
  /// // named "myImportantNode" instead of a generated name like "a_xor_b"
  /// final myImportantNode = (a ^ b).named('myImportantNode');
  /// ```
  Logic named(String name, {Naming? naming}) =>
      _clone(name: name, naming: naming)..gets(this);

  /// An internal constructor for [Logic] which additional provides access to
  /// setting the [wire].
  Logic._({
    String? name,
    int width = 1,
    Naming? naming,
    _Wire? wire,
  })  : naming = Naming.chooseNaming(name, naming),
        name = Naming.chooseName(name, naming),
        _wire = wire ?? _Wire(width: width) {
    if (width < 0) {
      throw LogicConstructionException(
          'Logic width must be greater than or equal to 0.');
    }
  }

  /// Constructs a [Logic] with some additional validation for ports of
  /// [Module]s.
  ///
  /// Useful for [Interface] definitions.
  factory Logic.port(String name, [int width = 1]) {
    if (!Sanitizer.isSanitary(name)) {
      throw InvalidPortNameException(name);
    }

    return Logic(
      name: name,
      width: width,

      // make port names mergeable so we don't duplicate the ports
      // when calling connectIO
      naming: Naming.mergeable,
    );
  }

  @override
  String toString() => [
        'Logic($width): $name',
        if (isArrayMember) 'index $arrayIndex of ($parentStructure)'
      ].join(', ');

  /// Throws an exception if this [Logic] cannot be connected to another signal.
  void _assertConnectable(Logic other) {
    if (_srcConnection != null) {
      throw Exception(
          'This signal "$this" is already connected to "$srcConnection",'
          ' so it cannot be connected to "$other".');
    }

    if (_unassignable) {
      throw UnassignableException(this, reason: _unassignableReason);
    }

    if (other.width != width) {
      throw SignalWidthMismatchException(other, width);
    }

    if (_wire == other._wire && !isNet) {
      throw SelfConnectingLogicException(this, other);
    }
  }

  /// Injects a value onto this signal in the current [Simulator] tick.
  ///
  /// This function calls [put] in [Simulator.injectAction].
  void inject(dynamic val, {bool fill = false}) =>
      _wire.inject(val, signalName: name, fill: fill);

  /// Puts a value [val] onto this signal, which may or may not be picked up
  /// for [changed] in this [Simulator] tick.
  ///
  /// The type of [val] should be an `int`, [BigInt], `bool`, or [LogicValue].
  ///
  /// This function is used for propogating glitches through connected signals.
  /// Use this function for custom definitions of [Module] behavior.
  ///
  /// If [fill] is set, all bits of the signal gets set to [val], similar
  /// to `'` in SystemVerilog.
  void put(dynamic val, {bool fill = false}) =>
      _wire.put(val, signalName: name, fill: fill);

  /// Connects this [Logic] directly to be driven by [other].
  ///
  /// Every time [other] transitions ([glitch]es), this signal will transition
  /// the same way.
  void gets(Logic other) {
    // If we are connecting a `LogicStructure` to this simple `Logic`,
    // then pack it first.
    if (other is LogicStructure) {
      // ignore: parameter_assignments
      other = other.packed;
    }

    _assertConnectable(other);

    _connect(other);

    other._registerConnection(this);
  }

  /// Handles the actual connection of this [Logic] to be driven by [other].
  void _connect(Logic other) {
    _unassignable = true;
    if (other is LogicNet) {
      put(other.value);
      other.glitch.listen((args) {
        put(other.value);
      });
    } else {
      _updateWire(other._wire);
    }
    _srcConnection = other;
    _srcConnections.add(other);
  }

  /// Updates the current active [_Wire] for this [Logic] and also
  /// notifies all downstream [Logic]s of the new source [_Wire].
  void _updateWire(_Wire newWire) {
    assert((_wire is _WireNet) == (newWire is _WireNet),
        'Should not merge nets of different types.');

    if (newWire == _wire) {
      // no need to do any work if we're already on the same wire!
      return;
    }

    // first, propagate the new value (if it's different) downstream
    _wire.put(newWire.value, signalName: name);

    // then, replace the wire
    _wire = newWire._adopt(_wire);

    // tell all downstream signals to update to the new wire as well
    final Iterable<Logic> toUpdateWire;
    if (this is LogicNet) {
      toUpdateWire = [
        ...dstConnections,
        ...srcConnections,
      ].where(
          (connection) => connection._wire != _wire && connection is LogicNet);
    } else {
      toUpdateWire = dstConnections.where((element) => element is! LogicNet);
    }

    for (final dstConnection in toUpdateWire) {
      dstConnection._updateWire(_wire);
    }
  }

  /// Connects this [Logic] directly to another [Logic].
  ///
  /// This is shorthand for [gets].
  void operator <=(Logic other) => gets(other);

  /// Logical bitwise NOT.
  Logic operator ~() => NotGate(this).out;

  /// Logical bitwise AND.
  Logic operator &(Logic other) => And2Gate(this, other).out;

  /// Logical bitwise OR.
  Logic operator |(Logic other) => Or2Gate(this, other).out;

  /// Logical bitwise XOR.
  Logic operator ^(Logic other) => Xor2Gate(this, other).out;

  /// Power operation
  Logic pow(dynamic exponent) => Power(this, exponent).out;

  /// Addition.
  Logic operator +(dynamic other) => Add(this, other).sum;

  /// Subtraction.
  Logic operator -(dynamic other) => Subtract(this, other).out;

  /// Multiplication.
  Logic operator *(dynamic other) => Multiply(this, other).out;

  /// Division.
  Logic operator /(dynamic other) => Divide(this, other).out;

  /// Modulo operation.
  Logic operator %(dynamic other) => Modulo(this, other).out;

  /// Arithmetic right-shift.
  ///
  /// The upper-most bits of the result will be equal to the upper-most bit of
  /// the original signal.
  ///
  /// If [isNet] and [other] is constant, then the result will also be a net.
  Logic operator >>(dynamic other) {
    if (isNet) {
      // many SV simulators don't support shifting of nets, so default this
      final shamt = _constShiftAmount(other);
      if (shamt != null) {
        return [
          this[-1].replicate(shamt),
          getRange(shamt),
        ].swizzle();
      }
    }

    return ARShift(this, other).out;
  }

  /// Logical left-shift.
  ///
  /// The lower bits are 0-filled.
  ///
  /// If [isNet] and [other] is constant, then the result will also be a net.
  Logic operator <<(dynamic other) {
    if (isNet) {
      // many SV simulators don't support shifting of nets, so default this
      final shamt = _constShiftAmount(other);
      if (shamt != null) {
        return [
          getRange(0, -shamt),
          Const(0, width: shamt),
        ].swizzle();
      }
    }

    return LShift(this, other).out;
  }

  /// Logical right-shift.
  ///
  /// The upper bits are 0-filled.
  ///
  /// If [isNet] and [other] is constant, then the result will also be a net.
  Logic operator >>>(dynamic other) {
    if (isNet) {
      // many SV simulators don't support shifting of nets, so default this
      final shamt = _constShiftAmount(other);
      if (shamt != null) {
        return [
          Const(0, width: shamt),
          getRange(shamt),
        ].swizzle();
      }
    }

    return RShift(this, other).out;
  }

  /// Helper function to extract a constant integer shift amount from [other].
  static int? _constShiftAmount(dynamic other) {
    if (other is Const) {
      return other.value.toInt();
    } else if (other is Logic) {
      return null;
    } else {
      return LogicValue.ofInferWidth(other).toInt();
    }
  }

  /// Unary AND.
  Logic and() => AndUnary(this).out;

  /// Unary OR.
  Logic or() => OrUnary(this).out;

  /// Unary XOR.
  Logic xor() => XorUnary(this).out;

  /// Logical equality.
  Logic eq(dynamic other) => Equals(this, other).out;

  /// Logical inequality.
  Logic neq(dynamic other) => NotEquals(this, other).out;

  /// Less-than.
  Logic lt(dynamic other) => LessThan(this, other).out;

  /// Less-than-or-equal-to.
  Logic lte(dynamic other) => LessThanOrEqual(this, other).out;

  /// Greater-than.
  Logic gt(dynamic other) => GreaterThan(this, other).out;

  /// Greater-than-or-equal-to.
  Logic gte(dynamic other) => GreaterThanOrEqual(this, other).out;

  /// Greater-than.
  Logic operator >(dynamic other) => GreaterThan(this, other).out;

  /// Greater-than-or-equal-to.
  Logic operator >=(dynamic other) => GreaterThanOrEqual(this, other).out;

  /// Shorthand for a [Conditional] which increments this by [val].
  ///
  /// By default for a [Logic] variable, if no [val] is provided then the
  /// result is ++variable else result is variable+=[val].
  ///
  /// If using [Combinational], you will need to provide [s] as a remapping
  /// function since otherwise this will cause a "write after read" violation.
  ///
  /// ```dart
  ///
  /// Sequential(clk, [
  ///   pOut.incr(val: b),
  /// ]);
  ///
  /// Combinational.ssa((s) => [
  ///       s(pOut) < a,
  ///       pOut.incr(val: b, s: s),
  ///     ]);
  ///
  /// ```
  Conditional incr({Logic Function(Logic)? s, dynamic val = 1}) =>
      s == null ? (this < this + val) : (s(this) < s(this) + val);

  /// Shorthand for a [Conditional] which decrements this by [val].
  ///
  /// By default for a [Logic] variable, if no [val] is provided then the
  /// result is --variable else result is var-=[val].
  ///
  /// If using [Combinational], you will need to provide [s] as a remapping
  /// function since otherwise this will cause a "write after read" violation.
  ///
  /// ```dart
  ///
  /// Sequential(clk, [
  ///   pOut.decr(val: b),
  /// ]);
  ///
  /// Combinational.ssa((s) => [
  ///       s(pOut) < a,
  ///       pOut.decr(val: b, s: s),
  ///     ]);
  ///
  /// ```
  Conditional decr({Logic Function(Logic)? s, dynamic val = 1}) =>
      s == null ? (this < this - val) : (s(this) < s(this) - val);

  /// Shorthand for a [Conditional] which increments this by [val].
  ///
  /// For a [Logic] variable, this is variable *= [val].
  ///
  /// If using [Combinational], you will need to provide [s] as a remapping
  /// function since otherwise this will cause a "write after read" violation.
  ///
  /// ```dart
  ///
  /// Sequential(clk, [
  ///   pOut.mulAssign(val: b),
  /// ]);
  ///
  /// Combinational.ssa((s) => [
  ///       s(pOut) < a,
  ///       pOut.mulAssign(val: b, s: s),
  ///     ]);
  ///
  /// ```
  Conditional mulAssign(dynamic val, {Logic Function(Logic)? s}) =>
      s == null ? (this < this * val) : (s(this) < s(this) * val);

  /// Shorthand for a [Conditional] which increments this by [val].
  ///
  /// For a [Logic] variable, this is variable /= [val].
  ///
  /// If using [Combinational], you will need to provide [s] as a remapping
  /// function since otherwise this will cause a "write after read" violation.
  ///
  /// ```dart
  ///
  /// Sequential(clk, [
  ///   pOut.divAssign(val: b),
  /// ]);
  ///
  /// Combinational.ssa((s) => [
  ///       s(pOut) < a,
  ///       pOut.divAssign(val: b, s: s),
  ///     ]);
  ///
  /// ```
  Conditional divAssign(dynamic val, {Logic Function(Logic)? s}) =>
      s == null ? (this < this / val) : (s(this) < s(this) / val);

  /// Conditional assignment operator.
  ///
  /// Represents conditionally asigning the value of another signal to this.
  /// Returns an instance of [ConditionalAssign] to be be passed to a
  /// [Conditional].
  Conditional operator <(dynamic other) {
    if (_unassignable) {
      throw Exception('This signal "$this" has been marked as unassignable.  '
          'It may be a constant expression or otherwise'
          ' should not be assigned.');
    }

    if (other is Logic) {
      return ConditionalAssign(this, other);
    } else {
      return ConditionalAssign(this, Const(other, width: width));
    }
  }

  /// Accesses the [index]th bit of this signal.
  ///
  /// Accepts both [int] and [Logic] as [index].
  ///
  /// Throws [Exception] when index is not an [int] or [Logic].
  ///
  /// Negative/Positive index values are allowed (only when index is an int).
  /// When, index is a Logic, the index value is treated as an unsigned value.
  /// The negative indexing starts from the end=[width]-1
  ///
  /// -([width]) <= [index] < [width]
  ///
  /// ```dart
  /// Logic nextVal = addOutput('nextVal', width: width);
  /// // Example: val = 0xce, val.width = 8, bin(0xce) = "0b11001110"
  /// // Positive Indexing
  /// nextVal <= val[3]; // output: 1
  ///
  /// // Negative Indexing
  /// nextVal <= val[-5]; // output: 1, also val[3] == val[-5]
  ///
  /// // Error cases
  /// nextVal <= val[-9]; // Error!: allowed values [-8, 7]
  /// nextVal <= val[8]; // Error!: allowed values [-8, 7]
  /// ```
  /// Note: When, indexed by a Logic value, out-of-bounds will always return an
  /// invalid (LogicValue.x) value. This behavior is differs in simulation as
  /// compared to the generated SystemVerilog. In the generated SystemVerilog,
  /// [index] will be ignored, and the logic is returned as-is.
  ///
  /// If [isNet], then the result will also be a net.
  Logic operator [](dynamic index) {
    if (index is Logic) {
      return IndexGate(this, index).selection;
    } else if (index is int) {
      return slice(index, index);
    }
    throw Exception('Expected `int` or `Logic`');
  }

  /// Provides a list of logical elements within this signal.
  ///
  /// For a normal [Logic], this will always be a list of 1-bit signals.
  /// However, for derivatives of [Logic] like [LogicStructure] or [LogicArray],
  /// each element may be any positive number of bits.
  late final List<Logic> elements = UnmodifiableListView(
      List.generate(width, (index) => this[index], growable: false));

  /// Returns a simple flattened [Logic].
  ///
  /// For a basic [Logic], this just returns itself.
  // ignore: avoid_returning_this
  Logic get packed => this;

  /// Accesses a subset of this signal from [startIndex] to [endIndex],
  /// both inclusive.
  ///
  /// If [endIndex] comes before the [startIndex] on position, the returned
  /// value will be reversed relative to the original signal.
  /// Negative/Positive index values are allowed. (The negative indexing starts from where the array ends)
  ///
  ///
  /// ```dart
  /// Logic nextVal = addOutput('nextVal', width: width);
  /// // Example: val = 0xce, val.width = 8, bin(0xce) = "0b11001110"
  /// // Negative Slicing
  /// nextVal <= val.slice(val.width - 1, -3); // = val.slice(7,5) & output: 0b110, where the output.width=3
  ///
  /// // Positive Slicing
  /// nextVal <= val.slice(5, 0); // = val.slice(-3, -8) & output: 0b001110, where the output.width=6
  /// ```
  ///
  /// If [isNet], then the result will also be a net.
  Logic slice(int endIndex, int startIndex) {
    // Given start and end index, if either of them are seen to be -ve index
    // value(s) then convert them to a +ve index value(s)
    final modifiedStartIndex = IndexUtilities.wrapIndex(startIndex, width);
    final modifiedEndIndex = IndexUtilities.wrapIndex(endIndex, width);

    if (modifiedStartIndex == 0 && modifiedEndIndex == width - 1) {
      // ignore: avoid_returning_this
      return this;
    }

    // Create a new bus subset
    return BusSubset(this, modifiedStartIndex, modifiedEndIndex).subset;
  }

  /// Returns a version of this [Logic] with the bit order reversed.
  late final Logic reversed = (isNet ? LogicNet.new : Logic.new)(
      name: 'reversed_$name', naming: Naming.unnamed, width: width)
    ..gets(slice(0, width - 1));

  /// Returns a subset [Logic].  It is inclusive of [startIndex], exclusive of
  /// [endIndex].
  ///
  /// The [startIndex] must come before the [endIndex]. If [startIndex] and
  /// [endIndex] are equal, then a zero-width signal is returned.
  /// Negative/Positive index values are allowed. (The negative indexing starts from where the array ends)
  ///
  /// If [endIndex] is not provided, [width] of the [Logic] will
  /// be used as the default values which assign it to the last index.
  ///
  /// ```dart
  /// Logic nextVal = addOutput('nextVal', width: width);
  /// // Example: val = 0xce, val.width = 8, bin(0xce) = "0b11001110"
  /// // Negative getRange
  /// nextVal <= val.getRange(-3, val.width); // = val.getRange(5,8) & output: 0b110, where the output.width=3
  ///
  /// // Positive getRange
  /// nextVal <= val.getRange(0, 6); // = val.slice(0, -2) & output: 0b001110, where the output.width=6
  ///
  /// // Get range from startIndex
  /// nextVal <= val.getRange(-3); // the endIndex will be auto assign to val.width
  /// ```
  ///
  /// If [isNet], then the result will also be a net.
  Logic getRange(int startIndex, [int? endIndex]) {
    endIndex ??= width;
    if (endIndex == startIndex) {
      return Const(0, width: 0);
    }

    // Given start and end index, if either of them are seen to be -ve index
    // value(s) then conver them to a +ve index value(s)
    final modifiedStartIndex =
        IndexUtilities.wrapIndex(startIndex, width, allowWidth: true);
    final modifiedEndIndex =
        IndexUtilities.wrapIndex(endIndex, width, allowWidth: true);

    IndexUtilities.validateRange(modifiedStartIndex, modifiedEndIndex);

    return slice(modifiedEndIndex - 1, modifiedStartIndex);
  }

  /// Returns a new [Logic] with width [newWidth] where new bits added are zeros
  /// as the most significant bits.
  ///
  /// The [newWidth] must be greater than or equal to the current width or an
  /// exception will be thrown.
  ///
  /// If [isNet], then the result will also be a net.
  Logic zeroExtend(int newWidth) {
    if (newWidth < width) {
      throw Exception(
          'New width $newWidth must be greater than or equal to width $width.');
    }
    return [
      Const(0, width: newWidth - width),
      this,
    ].swizzle();
  }

  /// Calculates the absolute value of a signal, assuming that the
  /// number is a two's complement.
  Logic abs() {
    if (width == 0) {
      return this;
    }
    return mux(this[-1], ~this + 1, this);
  }

  /// Returns a new [Logic] width width [newWidth] where new bits added are sign
  /// bits as the most significant bits.  The sign is determined using two's
  /// complement, so it takes the most significant bit of the original signal
  /// and extends with that.
  ///
  /// The [newWidth] must be greater than or equal to the current width or
  /// an exception will be thrown.
  ///
  /// If [isNet], then the result will also be a net.
  Logic signExtend(int newWidth) {
    if (width == 1) {
      return replicate(newWidth);
    } else if (newWidth > width) {
      return [
        this[-1].replicate(newWidth - width),
        this,
      ].swizzle();
    } else if (newWidth == width) {
      // ignore: avoid_returning_this
      return this;
    }

    throw Exception(
        'New width $newWidth must be greater than or equal to width $width.');
  }

  /// Returns a copy of this [Logic] with the bits starting from [startIndex]
  /// up until [startIndex] + [update]`.width` set to [update] instead
  /// of their original value.
  ///
  /// The return signal will be the same [width].  An exception will be thrown
  /// if the position of the [update] would cause an overrun past the [width].
  Logic withSet(int startIndex, Logic update) {
    if (startIndex + update.width > width) {
      throw RangeError('Width of update $update at startIndex $startIndex would'
          ' overrun the width of the original ($width).');
    }

    if (startIndex < 0) {
      throw RangeError(
          'Start index must be greater than zero but was $startIndex');
    }

    if (startIndex == 0 && update.width == width) {
      // special case, setting whole thing, just return the same thing
      return update;
    }

    return [
      getRange(startIndex + update.width, width),
      update,
      getRange(0, startIndex),
    ].swizzle();
  }

  /// Returns a replicated signal using [ReplicationOp] with new width =
  /// this.width * [multiplier]
  ///
  /// The input [multiplier] cannot be negative or 0; an exception will be
  /// thrown, otherwise.
  ///
  /// If [isNet], then the result will also be a net.
  Logic replicate(int multiplier) {
    if (isNet) {
      // many SV simulators don't support replication of nets
      return List.generate(multiplier, (i) => this).swizzle();
    }

    return ReplicationOp(this, multiplier).replicated;
  }

  /// Returns `1` (of [width]=1) if the [Logic] calling this function is in
  /// [list]. Else `0` (of [width]=1) if not present.
  ///
  /// The [list] can be [Logic] or [int] or [bool] or [BigInt] or
  /// [list] of [dynamic] i.e combinition of aforementioned types.
  Logic isIn(List<dynamic> list) {
    // By default isLogicIn is not present return `0`:
    // Empty list corner-case state
    Logic isLogicIn = Const(0, width: 1);
    for (final dynamic y in list) {
      // Iterating through the list to check if the logic is present
      isLogicIn |= eq(y);
    }
    return isLogicIn;
  }

  /// Performs a [Logic] `index` based selection on an [List] of [Logic]
  /// named [busList].
  ///
  /// Using the [Logic] `index` on which [selectFrom] is performed on and
  /// a [List] of [Logic] named [busList] for `index` based selection, we can
  /// select any valid element of type [Logic] within the `logicList` using
  /// the `index` of [Logic] type.
  ///
  /// Alternatively we can approach this with `busList.selectIndex(index)`
  ///
  /// Example:
  /// ```dart
  /// // ordering matches closer to array indexing with `0` index-based.
  /// selected <= index.selectFrom(busList);
  /// ```
  Logic selectFrom(List<Logic> busList, {Logic? defaultValue}) {
    final selected = Logic(
        name: 'selectFrom',
        width: busList.first.width,
        naming: Naming.mergeable);

    Combinational(
      [
        Case(
            this,
            [
              for (var i = 0; i < busList.length; i++)
                CaseItem(Const(i, width: width), [selected < busList[i]])
            ],
            conditionalType: ConditionalType.unique,
            defaultItem: [selected < (defaultValue ?? 0)])
      ],
    );

    return selected;
  }

  /// If [assignSubset] has been used on this signal, a reference to the
  /// [LogicArray] that is usd to drive `this`.
  LogicArray? _subsetDriver;

  /// Performs an assignment operation on a portion this signal to be driven by
  /// [updatedSubset].  Each index of [updatedSubset] will be assigned to drive
  /// the corresponding index, plus [start], of this signal.
  ///
  /// Each of the elements of [updatedSubset] must have the same [width] as the
  /// corresponding member of [elements] of this signal.
  ///
  /// Example:
  /// ```dart
  /// // assign elements 2 and 3 of receiverLogic to sig1 and sig2, respectively
  /// receiverLogic.assignSubset([sig1, sig2], start: 2);
  /// ```
  void assignSubset(List<Logic> updatedSubset, {int start = 0}) {
    if (updatedSubset.length > width - start) {
      throw SignalWidthMismatchException.forWidthOverflow(
          updatedSubset.length, width - start);
    }

    if (_subsetDriver == null) {
      _subsetDriver = (isNet ? LogicArray.net : LogicArray.new)(
        [width],
        1,
        name: '${name}_subset',
        naming: Naming.unnamed,
      );
      this <= _subsetDriver!;
    }

    _subsetDriver!.assignSubset(updatedSubset, start: start);
  }
}
