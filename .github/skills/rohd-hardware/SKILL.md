---
name: rohd-hardware
description: Use when writing, editing, reviewing, or debugging ROHD hardware modules in Dart. Covers module construction and hierarchy ownership (addInput/addOutput/addInterfacePorts), definitionName, port types, logic constructs, LogicStructure/Interface patterns, nested composition tests, SimCompare multi-backend vectors, event-driven simulation, and common mistakes from PR reviews.
argument-hint: Describe the ROHD module, test, or simulation task and the files involved
---

# ROHD Hardware Modeling — AI Skill Guide

> This repository-tracked file is the canonical ROHD hardware-modeling guide.
> User-level skill installations may link here so improvements made by any
> session remain version-controlled and shareable.
>
> This document instructs AI coding assistants on how to build correct ROHD
> hardware modules, write thorough tests, and run simulations that verify
> functional correctness across multiple backends.

---

## 1. Framework Fundamentals

ROHD is a hardware description framework built as a Dart library.
All Dart conventions (Effective Dart) apply. Hardware is described by
composing `Module` subclasses that have typed ports (`Logic`, `LogicArray`,
`LogicStructure`, `Interface`) and procedural logic (`Combinational`,
`Sequential`, `Pipeline`, `FiniteStateMachine`).

### Core types

| Type             | Role                                  | SV equivalent     |
| ---------------- | ------------------------------------- | ----------------- |
| `Logic`          | Single wire/bus, fixed width          | `logic [N-1:0]`   |
| `LogicValue`     | Immutable 4-state value (0,1,x,z)     | —---------------- |
| `LogicArray`     | Multi-dimensional array of `Logic`    | unpacked array    |
| `TypedLogicArray<T, V>` | Array with a concrete hardware element type `T` and semantic value type `V` | typed packed/unpacked array |
| `LogicStructure` | Named bundle of heterogeneous signals | struct            |
| `Interface`      | Directional port bundle with tags     | interface/modport |
| `LogicNet`       | Net-type for multi-driver/tri-state   | `wire`/`tri`      |

Payload structures should describe data semantics, not transport. Use names
such as `Frame<T>`, `CountedFrame<T>`, `MaskedLanes<T>`, `CompactedLanes<T>`,
`Tagged<T>`, and `PoolRequest<T>`, then wrap the payload in
`ReadyValidInterface<T>`, `CreditInterface<T>`, or direct scheduled ports.
Do not prefix a `LogicStructure` with `ReadyValid` unless the structure itself
actually contains ready/valid transport semantics.

### Signal assignment operators

| Operator     | Context                             | Meaning                                   |
| --------     | ----------------------------------- | ----------------------------------------- |
| `<=`         | Outside `_Always` blocks            | Continuous connection (`gets`)            |
| `<`          | Inside `Combinational`/`Sequential` | Conditional assignment                    |
| `.inject(v)` | Test code only                      | Force a value without hardware connection |
| `.put(v)`    | Simulation actions                  | Drive a value at a simulation timestamp   |

---

## 2. Building a Module — Step by Step

### 2.1 Minimal structure

```dart
class MyModule extends Module {
  /// The computed output.
  Logic get result => output('result');

  MyModule(Logic dataIn, {super.name = 'myModule'})
      : super(definitionName: 'MyModule_W${dataIn.width}') {
    dataIn = addInput('dataIn', dataIn, width: dataIn.width);
    final result = addOutput('result', width: dataIn.width);
    result <= dataIn;  // continuous assignment
  }
}
```

### 2.2 Critical rules

1. **Always reassign after `addInput`**: `dataIn = addInput('dataIn', dataIn, ...)`.
   All subsequent code must use the returned internal copy, never the external signal.

2. **`definitionName` encodes configuration**: Include sizing parameters
   (`'MacUnit_W$dataWidth'`, `'CoeffBank_T${numTaps}_W$dataWidth'`) so
   different configurations produce distinct synthesized module definitions.

3. **`super.name` is the instance name**: Use lowercase
   (`super.name = 'macUnit'`), matching Verilog conventions.

4. **1-bit signals don't need `width:`**: `addInput('clk', clk)` defaults to 1.

5. **Output getters are public API**: `Logic get result => output('result');`

6. **Input getters are `@protected`**: Internal access only, with `Pin` suffix
   if shadowing constructor params:

   ```dart
   @protected
   Logic get clkPin => input('clk');
   ```

7. **Store configuration as `final` fields**: `final int dataWidth;` makes
   parameterization inspectable.

### 2.3 Port types

```dart
// Scalar
dataIn = addInput('dataIn', dataIn, width: dataWidth);
final result = addOutput('result', width: dataWidth);

// Array
final coeffs = addInputArray('coeffs', coefficients,
    dimensions: [numTaps], elementWidth: dataWidth);
final outputs = addOutputArray('outputs',
    dimensions: [numChannels], elementWidth: dataWidth);

// Bidirectional
final bus = addInOut('dataBus', dataBusNet, width: dataWidth);

// Typed structure (preserves named fields)
this.sample = addTypedInput('sample', sample);
```

### 2.4 Driving `LogicArray` outputs

**Always drive element-by-element**, never via `swizzle()`:

```dart
// CORRECT — preserves array structure in synthesis
outputArray.elements.forEachIndexed((i, d) =>
    d <= flop(clk, reset: reset, en: enable & count.eq(i), serialized));

// WRONG — flattens the array
outputArray <= [...].swizzle();
```

### 2.5 Typed ports and typed arrays

Use `addTypedInput` and `addTypedOutput` for a `LogicStructure`,
`LogicEnum`, or `TypedLogicArray` port. They preserve the concrete hardware
type rather than flattening it to an ordinary `Logic`.

```dart
class Sample extends LogicStructure {
  Logic get flag => elements[0];

  Sample({String? name})
      : super([Logic(name: 'flag')], name: name ?? 'sample');

  @override
  Sample clone({String? name}) => Sample(name: name ?? this.name);
}

final samples = addTypedInput(
  'samples',
  TypedLogicArray<Sample, LogicValue>([2], Sample.new, name: 'samples'),
);
final inverted = addTypedOutput('inverted', samples.clone);
for (final (index, sample) in samples.arrayElements.indexed) {
  inverted.arrayElements[index].flag <= ~sample.flag;
}
```

Define `clone()` on every concrete `LogicStructure` used as a typed port or
typed-array element. The clone must preserve the concrete type, layout, and
semantic metadata while honoring the requested `name`.

### 2.6 Interfaces with `addInterfacePorts`

Use `addInterfacePorts` to register an interface at a module boundary. It returns
an internal clone; module logic must use that clone, while callers retain the
external interface instance.

```dart
control = addInterfacePorts(
  control,
  inputTags: {ControlPort.toModule},
  outputTags: {ControlPort.fromModule},
  uniquify: (original) => 'control_$original',
);
control.signalOut <= ~control.signalIn;
```

Use `addInterfaceFrom` only when deliberately adapting the interface type.
For `PairInterface`, use `addPairInterfacePorts` or `addPairInterfaceFrom`.

### 2.7 Mandatory module-boundary ownership

Every hardware signal used across a `Module` boundary must cross through a port
owned by that module. A module that builds successfully as the root DUT can
still fail hierarchy tracing when instantiated under a parent, so this rule
must be audited explicitly.

#### Constructor inputs

- Rebind every constructor signal with `addInput`, `addTypedInput`,
  `addInputArray`, `addInterfacePorts`, `addPairInterfacePorts`, or
  `addPairInterfaceFrom`.
- Use only the returned internal signal or interface after registration.
- Never use the original external constructor argument in module logic.

#### Outputs

- Create scalar, array, and typed outputs with the matching `addOutput`,
  `addOutputArray`, or `addTypedOutput` API.
- A public hardware getter must return a port owned by the module, normally
  `output('name')`. Do not return an internal signal.
- Child state needed by a parent must be promoted to an explicit child output.
  The parent must not read a child's internal field, input port, register, or
  connected interface clone.
- `@protected` changes Dart API visibility only; it does not make hardware a
  port. Parent hardware still must not consume a protected internal signal.

```dart
class Child extends Module {
  Logic get available => output('available');

  Child(Logic request) {
    request = addInput('request', request);
    final available = addOutput('available');
    available <= ~request;
  }
}

final child = Child(parentRequest);
parentAvailable <= child.available; // child output: valid boundary crossing
```

#### Interfaces and composition

`addInterfacePorts`, `addPairInterfacePorts`, and `addPairInterfaceFrom`
create or return an **internal connected clone**. That clone is for the module
implementation
only. Keep it private:

```dart
late final ReadyValidInterface<Payload> _upstream;

_upstream = addPairInterfacePorts(
  upstream,
  PairRole.consumer,
  uniquify: (original) => 'upstream_$original',
);
```

Do not publish the clone as a public hardware field. Callers already own the
external interface passed to the constructor.

Prefer the repository's `addInterfacePorts`/`addPairInterfacePorts` helper
seam over
calling `connectIO` or `pairConnectIO` directly. Direct calls are appropriate
only inside the helper implementation or when a documented exceptional
retyping pattern cannot use `addPairInterfaceFrom`.

When composing children, create the connecting interface in the parent and
pass that same parent-owned interface to both children:

```dart
final link = ReadyValidInterface(Payload(name: 'linkPayload'));
Producer(clk: clk, reset: reset, downstream: link);
Consumer(clk: clk, reset: reset, upstream: link);
```

Never connect children by reading `producer.downstream`,
`consumer.upstream`, or another child field unless that field is an actual
module output getter backed by `output(...)`.

#### Child-signal audit before protocol debugging

Before debugging ready/valid timing, list every `child.member` used by the
parent and verify:

1. Parent reads only child outputs or the parent's own connecting interface.
2. Parent drives child inputs only through constructor arguments or interfaces.
3. Every child output getter is backed by `addOutput`, `addTypedOutput`,
   `addOutputArray`, or an output interface port.
4. Connected interface clones and child-internal registers are private.
5. No `rohd_hierarchy/non_port_public_hardware` diagnostic is suppressed.

If any item fails, fix ownership first. Do not try to solve the resulting trace
error by changing ready/valid equations.

### 2.8 Count and index width safety

Keep zero-based indices and cardinality counts conceptually separate:

- An index over `N` entries represents `0` through `N - 1`; use
  `indexWidthForCount(N)`.
- A count for up to `N` entries represents `0` through `N`; use
  `countWidthForMaximum(N)`.
- Do not use `log2Ceil(N)` for a count that may equal `N`. It wraps to zero
  when `N` is a power of two.

When deriving a one-based count from a zero-based index, extend the index to
the count width **before** adding one:

```dart
completedCount < oneBasedCountFromIndex(
  index,
  countWidth: completedCount.width,
);
```

Do not write `completedCount < index + 1`: ROHD sizes the addition from the
index expression, so the full count may truncate before assignment or fail
port-width validation.

Count-bearing payload consumers must reject fields too narrow for every legal
value when the protocol permits a full-capacity count. Arithmetic that combines
counts, credits, occupancy, or accepted-lane totals should use an explicitly
extended intermediate width and narrow only after bounds have been enforced.

Every count-bearing component must test capacities `1`, `2`, and at least one
larger power of two. The test must reach the exact full count, not merely
`capacity - 1`.

---

## 3. Logic Constructs

### 3.1 Combinational logic

```dart
Combinational([
  If(condition, then: [
    result < valueA,
  ], orElse: [
    result < valueB,
  ]),
]);
```

For 3+ branches, use `If.block`:

```dart
Combinational([
  If.block([
    Iff(condA, [result < valA]),
    ElseIf(condB, [result < valB]),
    Else([result < valC]),
  ]),
]);
```

### 3.2 Sequential (registered) logic

```dart
Sequential(clk, reset: reset, [
  If(enable, then: [
    counter < counter + Const(1, width: counterWidth),
  ]),
]);
```

Signals assigned with `<` inside `Sequential` are automatically flopped.
Unassigned signals hold their previous value (implicit latch).

### 3.3 Pipeline

```dart
final pipe = Pipeline(clk, reset: reset, stages: [
  (p) => [p.get(data) < (p.get(data) * p.get(coeff)).named('product')],
  (p) => [p.get(data) < (p.get(data) + p.get(accum)).named('macSum')],
], signals: [data, coeff, accum]);
result <= pipe.get(data);
```

### 3.4 Finite State Machine

```dart
_fsm = FiniteStateMachine<MyState>(clk, reset, MyState.idle, [
  State<MyState>(MyState.idle,
    events: {startSignal: MyState.running},
    actions: [enable < 0, done < 0]),
  State<MyState>(MyState.running,
    events: {finishSignal: MyState.done},
    actions: [enable < 1, done < 0]),
  State<MyState>(MyState.done,
    events: {},
    actions: [enable < 0, done < 1]),
]);
stateOut <= _fsm.currentState.zeroExtend(stateOut.width);
```

### 3.5 Gate-level primitives

| Pattern | Use |
| --- | --- |
| `x <= mux(sel, a, b)` | Simple 2-input select |
| `x <= flop(clk, data)` | Simple register |
| `condFlop(clk?, d)` | Optional pipeline stage |
| `a & b`, `a \| b`, `~a` | Logic gates |
| `a + b`, `a * b`, `a - b` | Arithmetic |
| `a.eq(b)`, `a.lt(b)` | Comparison |

### 3.6 Type-preserving operations

Typed operations preserve a concrete `LogicStructure` or `TypedLogicArray`
representation when the operand layouts match. Prefer generic `mux<T>` and
`flop<T>` (or `Mux<T>` and `FlipFlop<T>`) when the result must retain its
domain type.

```dart
final selected = mux<Sample>(select, secondSample, firstSample);
final registered = flop<Sample>(clk, selected, reset: reset);
final named = registered.namedTyped('registeredSample');
```

The operands must have matching concrete types and recursive layouts. Use
`cloneTyped` to create a typed schema or `namedTyped` for a driveable typed
alias. Unary bit operations such as `~structure` intentionally return packed
`Logic`; invert a structure or typed-array field-by-field when its type must
be preserved.

### 3.7 Signal naming

Use `.named()` for readable SystemVerilog output:

```dart
final product = (a * b).named('product');
final lastTap = counter.eq(Const(numTaps - 1, width: w)).named('lastTap');
final isNormal = exponent.neq(zero).named('isNormal', naming: Naming.mergeable);
```

---

## 4. LogicStructure

### 4.1 Definition

```dart
class FilterSample extends LogicStructure {
  late final Logic data;
  late final Logic valid;

  FilterSample({int dataWidth = 16, String? name})
      : super([
          Logic(name: 'data', width: dataWidth),
          Logic(name: 'valid'),
        ], name: name ?? 'filter_sample') {
    data = elements[0];
    valid = elements[1];
  }
```

### 4.2 Required: `clone()`

```dart
  @override
  FilterSample clone({String? name}) => FilterSample._clone(
        elements.map((e) => e.clone(name: e.name)),
        name: name ?? this.name,
      );
```

### 4.3 Always name structures

Unnamed structures produce `_st_null_fieldName` in SystemVerilog.
**Always pass a meaningful `name:` parameter.**

### 4.4 Derived properties as `late final`

```dart
late final Logic hasData = valid & data.or()
    .named('hasData', naming: Naming.mergeable);
```

Creates hardware once, provides stable `Logic` reference.

---

## 5. Interface

```dart
class MyInterface extends Interface<MyPortTag> {
  Logic get dataIn => port('dataIn');
  Logic get dataOut => port('dataOut');

  MyInterface({int width = 8}) {
    setPorts([Logic.port('dataIn', width)], [MyPortTag.input]);
    setPorts([Logic.port('dataOut', width)], [MyPortTag.output]);
  }

  @override
  MyInterface clone() => MyInterface(width: _width);
}
```

Connect with:

```dart
intf = MyInterface(width: dataWidth)
  ..connectIO(this, srcIntf,
      inputTags: [MyPortTag.input],
      outputTags: [MyPortTag.output]);
```

The connected `intf` object above is internal implementation state and should
normally be private. The source interface remains the caller-visible API.

---

## 6. Testing and Simulation

### 6.1 Test file structure

```dart
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  test('descriptive name of what is being tested', () async {
    // 1. Build DUT
    final dut = MyModule(inputSignal, width: 8);
    await dut.build();

    // 2. Configure simulation
    Simulator.setMaxSimTime(2000);
    unawaited(Simulator.run());

    // 3. Stimulus + checks
    inputSignal.inject(42);
    await clk.nextPosedge;
    expect(dut.result.value.toInt(), equals(42));

    await Simulator.endSimulation();
  });
}
```

### 6.2 SimCompare — multi-backend vector testing

`SimCompare` runs the same stimulus vectors against multiple backends:
ROHD functional simulation and Icarus Verilog.

```dart
import 'package:rohd/src/utilities/simcompare.dart';

test('simcompare myModule', () async {
  final dut = MyModule(Logic(width: 8), Logic(width: 8));
  await dut.build();

  final vectors = [
    Vector({'a': 0, 'b': 0}, {'result': 0}),
    Vector({'a': 5, 'b': 3}, {'result': 8}),
    Vector({'a': 255, 'b': 1}, {'result': 0}),  // overflow wraps
  ];

  // Functional simulation (always available)
  await SimCompare.checkFunctionalVector(dut, vectors);

  // Icarus Verilog (requires iverilog installed)
  SimCompare.checkIverilogVector(dut, vectors);
});
```

### 6.2.1 Mandatory nested-composition build test

A root-only unit test does not reliably expose hierarchy ownership mistakes.
Every new composable module must have at least one test that instantiates it
inside a parent harness and calls `await harness.build()`. The harness should
exercise every boundary direction by connecting:

- parent inputs to DUT inputs;
- DUT outputs into parent outputs or parent logic; and
- ready/valid interfaces through parent-owned interface instances.

For interface-heavy modules, also verify each external direction appears in
the harnessed DUT's `inputs` or `outputs` maps. Generate SystemVerilog or run an
Icarus test for at least one representative hierarchy.

The touched files must pass the analyzer with no
`rohd_hierarchy/non_port_public_hardware` diagnostics. Do not add an ignore for
this diagnostic as a substitute for making the signal a real port or private
implementation state.

### 6.3 Vector format

```dart
Vector(
  {'inputPortName': value, ...},   // input stimulus
  {'outputPortName': expected, ...} // expected outputs
)
```

Values can be: `int`, `BigInt`, `LogicValue`, or `String` (binary literal).

### 6.4 Sequential (clocked) testing with vectors

For sequential modules, vectors execute one per clock cycle. Include
clock and reset in your vectors:

```dart
final vectors = [
  Vector({'clk': 0, 'reset': 1, 'dataIn': 0}, {'result': 0}),
  Vector({'clk': 1, 'reset': 1, 'dataIn': 0}, {'result': 0}),
  Vector({'clk': 0, 'reset': 0, 'dataIn': 5}, {'result': 0}),
  Vector({'clk': 1, 'reset': 0, 'dataIn': 5}, {'result': 5}),
];
```

### 6.5 Event-driven simulation testing

For complex sequential behavior (FSMs, pipelines), use direct simulation:

```dart
test('pipeline latency', () async {
  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic(name: 'reset');
  final dut = MyPipeline(clk, reset, dataIn, width: 16);
  await dut.build();

  Simulator.setMaxSimTime(500);
  unawaited(Simulator.run());

  // Reset sequence
  reset.inject(1);
  dataIn.inject(0);
  await clk.nextPosedge;
  await clk.nextPosedge;
  reset.inject(0);

  // Inject stimulus
  dataIn.inject(42);
  await clk.nextPosedge;
  dataIn.inject(0);

  // Wait for pipeline latency (2 stages)
  await clk.nextPosedge;
  await clk.nextPosedge;
  expect(dut.result.value.toInt(), equals(42));

  await Simulator.endSimulation();
});
```

### 6.6 WaveDumper for debugging

```dart
test('debug with waves', () async {
  final dut = MyModule(...);
  await dut.build();
  WaveDumper(dut, outputPath: 'tmp_test/debug_waves.vcd');
  Simulator.setMaxSimTime(2000);
  unawaited(Simulator.run());
  // ... stimulus ...
  await Simulator.endSimulation();
});
```

### 6.7 Test BKMs

- **Always `tearDown(() async { await Simulator.reset(); })`** — prevents
  state leakage between tests.
- **Use `inject()` in tests, `put()` in simulation actions** — `inject` is
  safe outside simulation tick context.
- **`Simulator.setMaxSimTime()`** — prevents runaway simulations.
- **Test names describe the scenario**, not the module name.
- **Comment above each test** explaining the stimulus strategy, especially
  for sequential tests where expected behavior is non-obvious.
- **`expect` with `reason:`** for complex checks:

  ```dart
  expect(computed, equals(expected),
      reason: 'a=$aVal, b=$bVal: got $computed, want $expected');
  ```

- **Run single files**: `dart test test/my_test.dart` when iterating.
- **Use `nextNegedge`** to sample combinational results mid-cycle after
  injecting on posedge.
- **Name functor parameters consistently** across all test/source files
  (e.g., always `adderGen`, never `adderFactory` in one place).
- **Make stateless test helpers `static`** — if it doesn't read `this`.
- **Don't pass default values explicitly** — omit params that match the
  default (e.g., don't write `verbose: false` if that's already the default).

---

## 7. Synthesis Verification

### 7.1 SystemVerilog generation

```dart
final sv = dut.generateSynth();
// Verify it contains expected module definitions
expect(sv, contains('module MyModule_W16'));
```

---

## 8. Design Patterns

### 8.1 Abstract base class with shared ports

```dart
abstract class ProcessorBase extends Module {
  @protected late final Logic a;
  @protected late final Logic b;
  late final Logic result;
  @protected late final Logic internalResult;

  ProcessorBase(Logic a, Logic b, {int width = 8, super.name,
      String? definitionName})
      : super(definitionName: definitionName ?? 'ProcessorBase_W$width') {
    this.a = addInput('a', a, width: width);
    this.b = addInput('b', b, width: width);
    internalResult = Logic(name: 'internalResult', width: width);
    result = addOutput('result', width: width);
    result <= internalResult;
  }
}
```

### 8.2 Functor pattern (pluggable sub-components)

```dart
class TreeReduction extends Module {
  TreeReduction(List<Logic> inputs, Logic Function(Logic a, Logic b) op) {
    // Build reduction tree using op
  }
}
// Usage:
final andTree = TreeReduction(signals, (a, b) => a & b);
```

### 8.3 Optional pipelining with `condFlop`

```dart
Logic condFlop(Logic? clk, Logic d, {Logic? en, Logic? reset}) =>
    (clk == null) ? d : flop(clk, d, en: en, reset: reset);

// In base class:
Logic localFlop(Logic input) => condFlop(clk, input, en: enable, reset: reset);
```

### 8.4 Shared swap utility in base class

```dart
abstract class ProcessorBase extends Module {
  @protected
  (Logic, Logic) swap(Logic doSwap, (Logic, Logic) toSwap) => (
    Logic(width: toSwap.$1.width)..gets(mux(doSwap, toSwap.$2, toSwap.$1)),
    Logic(width: toSwap.$2.width)..gets(mux(doSwap, toSwap.$1, toSwap.$2)),
  );
}
// Subclasses call: final (a, b) = swap(doSwap, (super.a, super.b));
```

### 8.5 Input validation

```dart
MyModule(Logic a, Logic b, ...) {
  if (a.width != b.width) {
    throw Exception('inputs a and b must have the same width.');
  }
  // ... port registration follows
}
```

---

## 9. Common Mistakes to Avoid

| # | Mistake | Fix |
| --- | --- | --- |
| 1 | Uppercase `super.name = 'Serializer'` | Use lowercase: `'serializer'` |
| 2 | Using external signal after `addInput` | Reassign: `sig = addInput('sig', sig, ...)` |
| 3 | Missing `definitionName` for parameterized modules | Always encode sizing: `'Mod_W$width'` |
| 4 | Driving `LogicArray` via `swizzle()` | Drive each element individually |
| 5 | Unnamed `LogicStructure` instances | Always pass `name:` parameter |
| 6 | `addOutput` in subclass when base already created it | Use `output('name')` instead |
| 7 | Unnecessary `@protected` getters for ports used only in constructor | Just use the local variable |
| 8 | `Const(1)` fallback for null enable at port level | Keep nullable, use `?? Const(1)` at point of use |
| 9 | Bare `expect` without `reason:` | Add `reason:` with operand values |
| 10 | Test name doesn't match what's tested | Name must describe actual scenario |
| 11 | `sleep` or busy-wait in tests | Use `await clk.nextPosedge` or Simulator events |
| 12 | Forgetting `await dut.build()` before simulation | Always build before simulating |
| 13 | Missing `Simulator.reset()` in `tearDown` | State leaks between tests |
| 14 | Copy-paste `addInput` name string bugs | Verify name string matches signal variable |
| 15 | `ia`/`ib` prefixes to avoid shadowing | Name fields `a`/`b`; use `this.`/`super.` to disambiguate |
| 16 | Repeated `condFlop(clk, ..., en: enable, reset: reset)` calls | Define `localFlop(Logic)` helper in base class |
| 17 | Duplicated `_swap` or utility in every subclass | Promote to `@protected` method on base class |
| 18 | Derived predicate as method: `isValid()` | Use getter: `bool get isValid => ...` |
| 19 | Inconsistent functor param names across files | Pick one name (`adderGen`) and use it everywhere |
| 20 | Factory method mixes compile-time/runtime params | Separate clearly: `Logic? flag` (runtime), `bool defaultFlag` (compile-time) |
| 21 | Module class inside `utils.dart` | One module per file, exported from barrel |
| 22 | Positional-only functor type params | Add names: `Logic Function(Logic term1, Logic term2) op` |
| 23 | Default functor = complex structural impl | Default to simplest wrapper; let synthesis pick structure |
| 24 | Class named `AdderSimple` or `MultiplierFast` | Name after architecture: `RippleCarryAdder`, `MultiplierPipelined` |
| 25 | `late final Logic internalResult` without `@protected` | Mark `@protected` so downstream doesn't access directly |
| 26 | Repeated base-class wiring in every subclass | Lift `output('x') <= internalX` into abstract base constructor |
| 27 | Dead wrapper class carrying one extra field | Add optional params to existing utility instead |
| 28 | Bare TODO: `Issue #194` | Full URL: `// TODO(user): https://github.com/org/repo/issues/194` |
| 29 | Passing default values explicitly: `verbose: false` | Omit params that match the default |
| 30 | Instance method that never reads `this` | Make it `static` |
| 31 | Field name shadows utility function in scope | Rename field to avoid ambiguity (e.g., `swap` → `doSwap`) |
| 32 | `output[carryOut]` in doc comment | Add space: `output [carryOut]` (DartDoc treats `x[…]` as subscript) |
| 33 | Parent reads `child.upstream`, `child.downstream`, or child state | Keep connected clones private; use a parent-owned interface or explicit child output |
| 34 | Public hardware field is not a module port | Make it private/`@protected`, or expose it with the matching `addOutput` API |
| 35 | Root DUT builds, nested use throws a trace error | Add a parent harness build test and audit every cross-module signal |
| 36 | Silencing `rohd_hierarchy/non_port_public_hardware` | Fix ownership; do not suppress the diagnostic |
| 37 | Count width uses `log2Ceil(capacity)` | Use `countWidthForMaximum(capacity)` so the full count is representable |
| 38 | Index width uses count width unnecessarily | Use `indexWidthForCount(entryCount)` for values through `entryCount - 1` |
| 39 | Assigning `index + 1` into a count | Use `oneBasedCountFromIndex`; extend before adding |

---

## 10. File Organization

- **One module per file** (not in `utils.dart`)
- **Group related modules** in subdirectories with barrel files:

  ```text
  lib/src/my_feature/
    my_feature.dart       ← barrel: exports all
    processor.dart
    controller.dart
  ```

- **Tests** in `test/` named `*_test.dart`
- **Examples** in `example/` showing typical usage

---

## 11. Documentation Requirements

- Every public class and member needs `///` doc comments
- First sentence is a summary ending with `.`
- Use `[references]` for signal/class names (creates DartDoc links)
- Link TODOs to full GitHub Issue URLs:
  `// TODO(user): https://github.com/org/repo/issues/194`
- **Space before bracket references**: `output [carryOut]` not `output[carryOut]`
  (DartDoc treats `x[…]` as a subscript operator)
- **Proofread for typos**: `representedin` → `represented in`,
  `oneusing` → `one using`
- **Stale references**: `carryOutP!` → `carryOutP1` — `!` looks like
  null-assertion in doc context

```dart
/// A pipelined multiply-accumulate unit.
///
/// Multiplies [sampleIn] × [coeffIn] in stage 0, adds to [accumIn] in stage 1.
/// See [Pipeline] for the underlying implementation.
class MacUnit extends Module {
  /// The accumulated MAC result.
  Logic get result => output('result');
```

---

## 12. Running Tests

```bash
# Single test file
dart test test/my_module_test.dart

# Single named test
dart test test/my_module_test.dart --name "impulse response"

# All tests
dart test

# With coverage
dart test --coverage=coverage
```

### CI requirements

- Tests must pass on both Dart VM and Node.js (`--platform node`)
- `dart:io` operations (file system, temp dirs) need `testOn: 'vm'`
- `dart:ffi` tests need `@TestOn('vm')` and exclusion from Node runs
