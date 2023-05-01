import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd/src/exceptions/module/module_exceptions.dart';
import 'package:rohd/src/utilities/sanitizer.dart';
import 'package:rohd/src/utilities/synchronous_propagator.dart';

class LogicStructure implements Logic {
  /// All components of this structure.
  late final List<Logic> components = UnmodifiableListView(_components);
  final List<Logic> _components = [];

  /// Packs all [components] into one flattened bus.
  late final Logic packed = components
      .map((e) {
        if (e is LogicStructure) {
          return e.packed;
        } else {
          return e;
        }
      })
      .toList()
      .swizzle();

  @override
  final String name;

  /// An internal counter for encouraging unique naming of unnamed signals.
  static int _structIdx = 0;

  /// Creates a new [LogicStructure] with [components] as elements.
  LogicStructure(List<Logic> components, {String? name})
      : name = (name == null || name.isEmpty)
            ? 'st${_structIdx++}'
            : Sanitizer.sanitizeSV(name) {
    _components.addAll(components);
  }

  //TODO: dimension List<int> (only on array?)

  ///////////////////////////////////////////////
  ///////////////////////////////////////////////
  ///////////////////////////////////////////////
  ///////////////////////////////////////////////

  @override
  void put(dynamic val, {bool fill = false}) {
    final logicVal = LogicValue.of(val, fill: fill, width: width);

    var index = 0;
    for (final component in components) {
      component.put(logicVal.getRange(index, index + component.width));
      index += component.width;
    }
  }

  @override
  void inject(val, {bool fill = false}) {
    final logicVal = LogicValue.of(val, fill: fill, width: width);

    var index = 0;
    for (final component in components) {
      component.inject(logicVal.getRange(index, index + component.width));
      index += component.width;
    }
  }

  @override
  Conditional operator <(dynamic other) {
    final otherLogic = other is Logic ? other : Const(other, width: width);

    if (otherLogic.width != width) {
      throw PortWidthMismatchException(otherLogic, width);
    }

    final conditionalAssigns = <Conditional>[];

    var index = 0;
    for (final component in components) {
      conditionalAssigns
          .add(component < otherLogic.getRange(index, index + component.width));
      index += component.width;
    }

    return ConditionalGroup(conditionalAssigns);
  }

  @override
  void gets(Logic other) {
    if (other.width != width) {
      throw PortWidthMismatchException(other, width);
    }

    var index = 0;
    for (final component in components) {
      component <= other.getRange(index, index + component.width);
      index += component.width;
    }
  }

  @override
  void operator <=(Logic other) => gets(other);

  @override
  Logic operator [](dynamic index) => packed[index];

  @override
  Logic getRange(int startIndex, [int? endIndex]) =>
      packed.getRange(startIndex, endIndex);

  @override
  Logic slice(int endIndex, int startIndex) =>
      packed.slice(endIndex, startIndex);

  /// Increments each component of [components] using [Logic.incr].
  @override
  Conditional incr(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val = 1}) =>
      ConditionalGroup([
        for (final component in components) component.incr(s: s, val: val),
      ]);

  /// Decrements each component of [components] using [Logic.decr].
  @override
  Conditional decr(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val = 1}) =>
      ConditionalGroup([
        for (final component in components) component.decr(s: s, val: val),
      ]);

  /// Divide-assigns each component of [components] using [Logic.divAssign].
  @override
  Conditional divAssign(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val}) =>
      ConditionalGroup([
        for (final component in components) component.divAssign(s: s, val: val),
      ]);

  /// Multiply-assigns each component of [components] using [Logic.mulAssign].
  @override
  Conditional mulAssign(
          {Logic Function(Logic p1) s = Logic.nopS, dynamic val}) =>
      ConditionalGroup([
        for (final component in components) component.mulAssign(s: s, val: val),
      ]);

  @override
  late final Iterable<Logic> dstConnections = [
    for (final component in components) ...component.dstConnections
  ];

  //TODO: is this safe to have a separate tracking here?
  Module? _parentModule;

  @override
  Module? get parentModule => _parentModule;

  @override
  set parentModule(Module? newParentModule) => _parentModule = newParentModule;

  @override
  bool get isInput => parentModule?.isInput(this) ?? false;

  @override
  // TODO: implement isOutput
  bool get isOutput => parentModule?.isOutput(this) ?? false;

  @override
  // TODO: implement isPort
  bool get isPort => isInput || isOutput;

  @override
  void makeUnassignable() {
    for (final component in components) {
      component.makeUnassignable();
    }
  }

  @override
  // TODO: implement srcConnection
  Logic? get srcConnection => throw UnimplementedError();

  @override
  LogicValue get value => packed.value;

  @override
  int get width => packed.width;

  @override
  Logic withSet(int startIndex, Logic update) =>
      packed.withSet(startIndex, update);

  /////////////////////////////////////////////////
  /////////////////////////////////////////////////
  /////////////////////////////////////////////////
  /////////////////////////////////////////////////

  @override
  Logic operator ~() => ~packed;

  @override
  Logic operator &(Logic other) => packed & other;

  @override
  Logic operator |(Logic other) => packed | other;

  @override
  Logic operator ^(Logic other) => packed ^ other;

  @override
  Logic operator *(dynamic other) => packed * other;

  @override
  Logic operator +(dynamic other) => packed + other;

  @override
  Logic operator -(dynamic other) => packed - other;

  @override
  Logic operator /(dynamic other) => packed / other;

  @override
  Logic operator %(dynamic other) => packed % other;

  @override
  Logic operator <<(dynamic other) => packed << other;

  @override
  Logic operator >(dynamic other) => packed > other;

  @override
  Logic operator >=(dynamic other) => packed >= other;

  @override
  Logic operator >>(dynamic other) => packed >> other;

  @override
  Logic operator >>>(dynamic other) => packed >>> other;

  @override
  Logic and() => packed.and();

  @override
  Logic or() => packed.or();

  @override
  Logic xor() => packed.xor();

  @override
  // ignore: deprecated_member_use_from_same_package
  LogicValue get bit => packed.bit;

  @override
  Stream<LogicValueChanged> get changed => packed.changed;

  @override
  Logic eq(dynamic other) => packed.eq(other);

  @override
  Logic neq(dynamic other) => packed.neq(other);

  @override
  SynchronousEmitter<LogicValueChanged> get glitch => packed.glitch;

  @override
  Logic gt(dynamic other) => packed.gt(other);

  @override
  Logic gte(dynamic other) => packed.gte(other);

  @override
  Logic lt(dynamic other) => packed.lt(other);

  @override
  Logic lte(dynamic other) => packed.lte(other);

  @override
  // ignore: deprecated_member_use_from_same_package
  bool hasValidValue() => packed.hasValidValue();

  @override
  // ignore: deprecated_member_use_from_same_package
  bool isFloating() => packed.isFloating();

  @override
  Logic isIn(List<dynamic> list) => packed.isIn(list);

  @override
  Stream<LogicValueChanged> get negedge => packed.negedge;

  @override
  Stream<LogicValueChanged> get posedge => packed.posedge;

  @override
  Future<LogicValueChanged> get nextChanged => packed.nextChanged;

  @override
  Future<LogicValueChanged> get nextNegedge => packed.nextNegedge;

  @override
  Future<LogicValueChanged> get nextPosedge => packed.nextPosedge;

  @override
  Logic replicate(int multiplier) => packed.replicate(multiplier);

  @override
  Logic get reversed => packed.reversed;

  @override
  Logic signExtend(int newWidth) => packed.signExtend(newWidth);

  @override
  Logic zeroExtend(int newWidth) => packed.zeroExtend(newWidth);

  @override
  // ignore: deprecated_member_use_from_same_package
  BigInt get valueBigInt => packed.valueBigInt;

  @override
  // ignore: deprecated_member_use_from_same_package
  int get valueInt => packed.valueInt;
}
