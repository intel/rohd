import 'dart:collection';

import 'package:rohd/rohd.dart';
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

  /// Creates a new [LogicStructure] with [components] as elements.
  LogicStructure(List<Logic> components) {
    _components.addAll(components);
  }

  //TODO: dimension List<int>

  ///////////////////////////////////////////////
  ///////////////////////////////////////////////
  ///////////////////////////////////////////////
  ///////////////////////////////////////////////

  @override
  void put(dynamic val, {bool fill = false}) {
    var index = 0;
    for (final component in components) {
      component.put();
      index += component.width;
    }
  }

  @override
  Module? get parentModule =>
      throw Exception('Cannot access parent of a structure'); //TODO
  @override
  set parentModule(Module? newParentModule) =>
      throw Exception('Cannot access parent of a structure'); //TODO

  @override
  ConditionalAssign operator <(other) {
    // TODO: implement <
    throw UnimplementedError();
  }

  @override
  void operator <=(Logic other) {
    // TODO: implement <=
  }

  @override
  Logic operator [](index) {
    // TODO: implement []
    throw UnimplementedError();
    //TODO: should this still return just 1 bit or no?
  }

  @override
  Logic getRange(int startIndex, [int? endIndex]) {
    // TODO: implement getRange
    throw UnimplementedError();
  }

  @override
  //TODO
  Logic slice(int endIndex, int startIndex) =>
      packed.slice(endIndex, startIndex);

  @override
  ConditionalAssign decr({Logic Function(Logic p1) s = Logic.nopS, val = 1}) {
    // TODO: implement decr
    throw UnimplementedError();
  }

  @override
  ConditionalAssign divAssign({Logic Function(Logic p1) s = Logic.nopS, val}) {
    // TODO: implement divAssign
    throw UnimplementedError();
  }

  @override
  ConditionalAssign mulAssign({Logic Function(Logic p1) s = Logic.nopS, val}) {
    // TODO: implement mulAssign
    throw UnimplementedError();
  }

  @override
  ConditionalAssign incr({Logic Function(Logic p1) s = Logic.nopS, val = 1}) {
    // TODO: implement incr
    throw UnimplementedError();
  }

  @override
  // TODO: implement dstConnections
  Iterable<Logic> get dstConnections => throw UnimplementedError();

  @override
  void gets(Logic other) {
    // TODO: implement gets
  }

  @override
  void inject(val, {bool fill = false}) {
    // TODO: implement inject
  }

  @override
  // TODO: implement isInput
  bool get isInput => throw UnimplementedError();

  @override
  // TODO: implement isOutput
  bool get isOutput => throw UnimplementedError();

  @override
  // TODO: implement isPort
  bool get isPort => throw UnimplementedError();

  @override
  void makeUnassignable() {
    // TODO: implement makeUnassignable
  }

  @override
  // TODO: implement name
  String get name => throw UnimplementedError();

  @override
  // TODO: implement srcConnection
  Logic? get srcConnection => throw UnimplementedError();

  @override
  // TODO: implement value
  LogicValue get value => throw UnimplementedError();

  @override
  // TODO: implement width
  int get width => throw UnimplementedError();

  @override
  Logic withSet(int startIndex, Logic update) {
    // TODO: implement withSet
    throw UnimplementedError();
  }

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
