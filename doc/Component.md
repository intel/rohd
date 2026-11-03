# How to Build a Great Component in ROHD

Since ROHD is an extension of the Dart programming language, please follow all
Dart programming and documentation conventions.

The `Module` class is the base class used in ROHD to build components, and
calling the constructor the `Module` instantiates the component and connects it
to signals passed into the constructor.

Since ROHD is written in Dart, you should use the Dart best practices, such as
camel-case variable naming, commenting patterns for all public APIs, and take
advantage of dart format and dart analyze tools.

## Port Construction and Connection

A `Module` constructor takes `Logic` arguments and parameters to generate a
hardware component. The `Logic` arguments are actually the external signals
being connected to by the `Module`, and so internal copies must be constructed
and connected to these arguments by the constructor and only then can other
logic signals be connected to these copies. If you do not do this, a trace error
will occur, but that only happens when this module is instantiated in another --
it will not show up while testing which just instantiates the module in a test
environment.  See [Modules](https://intel.github.io/rohd-website/docs/modules/)
for more detail.

A key pattern used in ROHD-HCL is to have the constructor take only input
signals as arguments and generate the output signal widths based on these
signals and other parameters.

## Port Types

Signals can take various forms in ROHD, and it is important to consider what form
you want for the API of the `Module` you are building. ROHD supports the basic
`Logic` signal which has its width encode (therefore you should not be using
width as a parameter to a `Module`). ROHD provides basic cloning and accessor
helper functions like `addInput` and `input`.

`LogicArray` is a uniform multidimensional array of leaf `Logic` signals. Use
`addTypedInput` and `addTypedOutput` when a generic component must preserve the
caller's complete array shape. Use `addInputArray` and `addOutputArray` when
the module intentionally declares a particular shape; those APIs require the
correct dimensions, element width, and unpacked-dimension metadata rather than
inferring it from the source. Examples of using `LogicArray` are in the
`Serializer` and `Deserializer` components.

`LogicStructure` is a hierarchical concatenation of named `Logic` fields, where
the `FloatingPoint` arithmetic type is an example used in the
`FloatingPointMultiplierSimple` module. We can also pass in `LogicStructure` as
a type for certain components so that the field structure is not lost on input
and output. A good example of this is `Fifo`, which is templatized on
`LogicType` to allow for us to generate a `Fifo` for a particular
`LogicStructure` to use when pushing and popping the data in and out. Here,
`addTypedInput` is a method used to help with creating the internal signals.

`Interface` is similar to `LogicStructure`, yet it provides an ability to define
directionality to the internal fields, useful in connecting modules that share a
common protocol such as the `ApbInterface`. See
[Interfaces](https://intel.github.io/rohd-website/docs/interfaces). A few
examples of key general interface types that you can inherit from are the
`PairInterface` and the `DataPortInterface`.  the `Memory` module has a good
example of how `DataPortInterface`s are cloned internally using its `connectIO`
method.
The `Fifo` has a good example of using an `Interface` to wrap a `LogicStructure`.

When wrapping `LogicStructure` with `Interface`, don't name the `LogicStructure`
as `Interface` will need to uniquify (a known bug in `Interface`).

An important kind of `Interface` is the `PairInterface` which is designed for
bidirectional communication and provides a `pairConnectIO` method for connecting
external and internal ports based on producer/consumer filtering.

## Logic Internals

Signal logic is constructed in a ROHD component by assignment and simple logic
operations like and (`&`) and or (`|`) as well as multiplexing (`mux`) and
flopping (`flop`).  See
[operations](https://intel.github.io/rohd-website/docs/logic-math-compare/) for
more detail.

 More complex logic can be constructed using
 [`Sequental`](https://intel.github.io/rohd-website/docs/sequentials/) and
 [`Combinational`](https://intel.github.io/rohd-website/docs/conditionals/)
 blocks similar to SystemVerilog `always` blocks.  There is also a
 [`FiniteStateMachine`](https://intel.github.io/rohd-website/docs/fsm/)
 construct for state machines and a
 [`Pipeline`](https://intel.github.io/rohd-website/docs/pipelines/) construct
 for assisting with pipelined logic.

 Try to minimize the addition of new internal signals, by just reusing the
 signals created by the ports or by subcomponents.  Use `.named` to create clean
 SystemVerilog names.

### Debug

 If you want to expose internal signals onto the interface of a `Module` for
 debug, a simple method is to declare them as a field in the class (Use
`@protected` in case this is exposed, so it doesn't become part of the API). This
 signal will be available in tests as module.field.

## Unit Testing

 A good component has unit tests to validate the component and provide examples
 of use. We use the Dart testing framework which requires that tests are stored
 in the `test/` directory and are named ending in `_test.dart`. An example of
 unit tests for a component is shown below.  Note that grouping of tests can
 reuse a common component built for multiple tests.  Also note that each test
 with sequential logic will need a `SimpleClockGenerator`, a `Simulator.run()`
 and an `endSimulation`. Some helper methods (like `.waitCycles`) are available
 in the rohd-fv package.

 ```dart
void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('test narrow component', () {
    final input = Logic(width: 5);
    final component = MyComponent(input);
    final output = component.out;

    test('MyComponent smoke test', () async {
      final clk = SimpleClockGenerator(10).clk;

      unawaited(Simulator.run());
        reset.inject(1);
        await clk.waitCycles(3);
        reset.inject(0);
        await clk.waitCycles(1);
        input.inject(1);
        await clk.waitCycles(3);
        expect(output.value, equals(Const(1, width: output.width)));

      await Simulator.endSimulation();
    });

    test('MyComponent second test', () async {
      final clk = SimpleClockGenerator(10).clk;

      unawaited(Simulator.run());
        reset.inject(1);
        await clk.waitCycles(3);
        reset.inject(0);
        await clk.waitCycles(1);
        input.inject(6);
        await clk.waitCycles(3);
        expect(output.value, equals(Const(6, width: output.width)));

      await Simulator.endSimulation();
    });
  });
}
```

Prefer using `waitCycles` instead of `nextPosedge` and use `inject` instead of
`put` when working with sequential tests.

When testing a combinational path, and you `inject` inputs after a positive
clock edge, if you sample at the next clock edge, you will miss the
combinational value.  Instead, use the output `previousValue` at the next clock
edge, or sample the output at `nextNegEdge` to look at the value midway through
the clock cycle.

While creating unit tests, run the tests for your component rather than the
entire ROHD regression suite. The broader suite is needed when a change affects
core functionality.

## Optional ROHD-HCL Component Integration

The preceding guidance applies to any ROHD component. The following
requirements apply only when contributing the component to the
[ROHD-HCL](https://github.com/intel/rohd-hcl) component library.

Export the component from the appropriate ROHD-HCL library barrel and
`lib/rohd_hcl.dart`. Add focused tests under `test/`, including a nested-parent
build test for every composable module.

Every documented, synthesizable public `Module` must have a `Configurator`
under `lib/src/component_config/components/` and an entry in
`lib/src/component_config/components/component_registry.dart`. Update an
existing configurator whenever its component gains a user-selectable
elaboration parameter. Expose compile-time choices as `ConfigKnob`s and
runtime-selectable controls as generated named `Logic` inputs. Pure
`LogicStructure`/`Interface` APIs, callback-only implementation primitives,
and simulation-only models do not require configurators. The registry drives
both the configuration app and documentation netlist generation.

Complete the Confapp source-asset, generated-view, and regression-test work
described in the
[ROHD-HCL Confapp documentation](https://github.com/intel/rohd-hcl/tree/main/confapp).

## Component Validation

Run focused validation while iterating:

```bash
dart format lib test
dart analyze --fatal-infos
dart test test/path/to/component_test.dart
```

Before submitting a component change, run the applicable broader test suite and
verify that the component builds when instantiated beneath a parent module.
