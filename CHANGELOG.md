## 0.5.1

- Fixed bugs and improved controllability around naming of internal signals and collapsing of inlineable functionality, leading to significantly more readable generated SystemVerilog (<https://github.com/intel/rohd/pull/439>).
- Fixed a bug where identical module definitions with different reserved definition names would merge incorrectly in generated outputs(<https://github.com/intel/rohd/issues/345>).
- Improved organization of port and internal signal declarations in generated outputs.
- Fixed bugs where generated SystemVerilog could flag lint issues due to unsafe truncation of signals in cases like `+` and `<<` (<https://github.com/intel/rohd/pull/423>).

## 0.5.0

- Added `LogicArray` for N-dimensional packed and unpacked (and mixed) arrays. Added `LogicStructure` for grouping sets of related signals together in a convenient way (<https://github.com/intel/rohd/pull/375>).
- Added a `ConditionalGroup` which can group a collection of other `Conditional`s into one `Conditional` object.
- Breaking: some APIs which previously returned `ConditionalAssign` now return a `Conditional`, such as the `<` operator for `Logic`.
- Updated `LogicValue.of` which now accepts a `dynamic` input and tries its best to build what you're looking for. Added `LogicValue.ofIterable` to replace the old `LogicValue.of`.
- Added `previousValue` to `Logic` to make testbench and modelling easier for things like clock edge sampling.
- Breaking: Modified the way `Combinational` sensitivities are implemented to improve performance and prevent some types of simulation/synthesis mismatch bugs. Added `Combinational.ssa` as a method to safely build procedural logic. `Combinational` will now throw fatal exceptions in cases of "write after read" violations. (<https://github.com/intel/rohd/pull/344>)
- Deprecated `getReceivers`, `getDrivers`, and `getConditionals` in always blocks like `Combinational` and `Sequential` in favor of simpler and more efficient APIs `receivers`, `drivers`, and `conditionals`.
- Breaking: shorthand notation APIs for `incr`, `decr`, `mulAssign`, and `divAssign` have been modified.
- Replaced `IfBlock` with `If.block` (deprecated `IfBlock`).
- Replaced `StateMachine` with `FiniteStateMachine` (deprecated `StateMachine`).
- Added support for multi-trigger (e.g. async reset) to abstractions like `FiniteStateMachine` and `Pipeline`. Deprecated `clk` on `FiniteStateMachine` and `Pipeline`.
- Added ability to generate an FSM diagram in mermaid from a `FiniteStateMachine`.
- Added `PairInterface` to make it easier to build and use simple `Interface`s.
- Breaking: `connectIO` in `Interface` now accepts `Iterable`s instead of only `Set`s.
- Improved numerous `Exception`s throughout to provide more specific information about errors and make them easier to catch and handle.
- Upgraded some operations to avoid generating unnecessary hardware and SystemVerilog when configured to leave a signal unchanged (e.g. `getRange`, `swizzle`, `slice`, etc.).
- Added extension to generate randomized `LogicValue`s from a `Random`.
- Added replication operations to `LogicValue` and `Logic`.
- Added `equalsWithDontCare` to `LogicValue` for comparisons where invalid bits are "don't-care".
- Improved timestamps in generated outputs to make timezones apparent.
- Added the `flop` function to construct `FlipFlop`s in an easier way.
- Added the `cases` function to construct simple `Case` statements in an easier way.
- Added APIs for configuring reset and reset values in `Sequential` and flip flops.
- Added APIs for adding an enable to flip flops.
- Implemented a variety of performance enhancements for both build and simulation.
- Added `tryInput` and `tryOutput` to `Module` and `tryPort` to `Interface` to more easily handle conditionally present ports by leveraging Dart's `null` safety by returning `null` if the port does not exist (instead of an exception).
- Added `gt` and `gte` to `Logic` to make APIs more consistent.
- Added `clog2` to `LogicValue`.
- Added `neq` and `pow` to both `Logic` and `LogicValue`.
- Made `LogicValue` implement `Comparable`, enabling things like sorting.
- Enabled `WaveDumper` to recursively create necessary directories for specified output paths.
- Fixed a bug where ports could be created with an empty string as the name (<https://github.com/intel/rohd/issues/281>).
- Fixed a bug where generated SystemVerilog for arithmetic shift-right operations would sometimes be incorrect (<https://github.com/intel/rohd/issues/295>).
- Fixed a bug where `SynthBuilder` would not flag an error when run on a `Module` that hadn't yet been built (<https://github.com/intel/rohd/issues/246>).
- Disallowed signals from being connected directly to themselves in a combinational loop.
- Fixed a bug where non-synthesizable deposits on undriven signals could affect the generated output SystemVerilog by inserting a non-floating constant (<https://github.com/intel/rohd/issues/254>).
- Reinstated an accidentally removed exception for when signal width mismatch occurs (<https://github.com/intel/rohd/issues/311>).
- Fixed a bug where indexing a constant value could generate invalid SystemVerilog.
- Fixed a bug where constants and values that could be interpreted as negative 64-bit values would sometimes generate a `-` sign in output SystemVerilog.
- Fixed bugs so `If`s that are illegally constructed throw an `Exception` (<https://github.com/intel/rohd/issues/382>).
- Fixed a bug where `FiniteStateMachine` could create an inferred latch (<https://github.com/intel/rohd/pull/390>).
- Fixed an issue where `Case` statements with multiple matches would throw an `Exception` instead of driving `x` on the output, which could cause spurious crashes during glitch simulation (<https://github.com/intel/rohd/issues/107>).
- Fixed a number of bugs related to logical, shift, math, and comparison operations related to width and sign interpretation.
- Fixed a bug where `Case` and `CaseZ` would not use the properly edge-sampled value in `Sequential` blocks (<https://github.com/intel/rohd/issues/348>).
- Fixed bugs where logic that is driven by floating signals would sometimes drive `z` instead of `x` on outputs (<https://github.com/intel/rohd/issues/235>).

## 0.4.2

- Added a GitHub Codespace to the repository as a quick way to experiment with ROHD without any environment setup.
- Added `Conditional` operations similar to `++x` (`incr`), `--x` (`decr`), `x *=` (`mulAssign`), and `x /=` (`divAssign`) to `Logic` (<https://github.com/intel/rohd/issues/141>).
- Fixed a bug where generated SystemVerilog could perform index accesses on single-bit signals (<https://github.com/intel/rohd/issues/204>).
- Expanded capability to construct single-`Conditional` more succinctly via `Else.s` (<https://github.com/intel/rohd/issues/225>).
- Fixed a bug where sensitivities for `Combinational`s were excessively pessimistic (<https://github.com/intel/rohd/issues/233>).
- Improved exceptions raised by `Logic.put` to include context on which signal was affected to help with debug (<https://github.com/intel/rohd/pull/243>).
- Optimized `WaveDumper` to only periodically write data to the VCD file to improve performance (<https://github.com/intel/rohd/pull/242>).
- Made `endIndex` in `getRange` an optional positional argument with a default value of `width`, enabling a more convenient method for collecting all bits from some index until the end (<https://github.com/intel/rohd/issues/228>).
- Added an exception in cases where names of interface ports are invalid/unsanitary (<https://github.com/intel/rohd/issues/234>).
- Upgraded the `Simulator` so that it would `await` asynchronous registered actions (<https://github.com/intel/rohd/pull/252>).
- Deprecated `Logic.hasValidValue` and `Logic.isFloating` in favor of similar operations on `Logic.value` (<https://github.com/intel/rohd/issues/198>).
- Added `Logic.isIn`, which generates logic computing whether the signal is equal to any values in a (optionally mixed) list of constants or other signals (<https://github.com/intel/rohd/issues/7>).

## 0.4.1

- Fixed a bug where `Module`s could have invalid names in generated SystemVerilog (<https://github.com/intel/rohd/issues/138>).
- Fixed a bug where `Logic`s could have invalid names in generated SystemVerilog.
- Added a feature allowing access of an index of a `Logic` via another `Logic` (<https://github.com/intel/rohd/issues/153>).
- Fixed a bug where multiple sequential driver issues might not be caught during ROHD simulation (<https://github.com/intel/rohd/issues/114>).
- Improved `Exception`s in ROHD with better error messages and more granular exception types to make handling easier.
- Improved generated SystemVerilog for sign extension and added capability for replication (<https://github.com/intel/rohd/issues/157>).
- Fixed a bug where signal names and module instance names could collide in generated SystemVerilog (<https://github.com/intel/rohd/issues/205>).
- Fixed a bug where in some cases modules might not be properly detected as sub-modules, leading to erroneous omission in generated outputs.
- Added capability to perform modulo and shift operations on `Logic` via a constant values (<https://github.com/intel/rohd/pull/208>).
- Completed a fix for a bug where shifting a `Logic` by a constant would throw an exception (<https://github.com/intel/rohd/issues/170>).
- Modified the mechanism by which signal propagation occurs between `Logic`s so that connected `Logic`s share an underlying value-holding entity (<https://github.com/intel/rohd/pull/199>).  One significant implication is that modifying a value of a `Logic` (e.g. via `put` or `inject`) will now affect the value of both downstream *and* upstream connected `Logic`s instead of only downstream.  This change also can significantly improve simulation performance in connection-heavy designs.  Additionally, this change helps mitigate an issue where very long combinational chains of logic can hit the stack size limit (<https://github.com/intel/rohd/issues/194>).
- Fixed a bug where large unsigned values on `LogicValue`s would convert to incorrect `int` values (<https://github.com/intel/rohd/issues/212>).
- Added an extension on `BigInt` to perform unsigned conversion to an `int`.
- Added a capability to construct some `Conditional` types (e.g. `If`) which have only a single `Conditional` more succinctly (<https://github.com/intel/rohd/issues/12>).
- Optimized some operations in `LogicValue` for performance (<https://github.com/intel/rohd/pull/215>).
- Added a shortcut to create a 0-width `LogicValue` called `LogicValue.empty` (<https://github.com/intel/rohd/issues/202>).
- Fixed a bug where equal `LogicValue`s could have unequal hash codes (<https://github.com/intel/rohd/issues/206>).  The fix also improved internal representation consistency for `LogicValue`s, which could provide a significant performance improvement when wide values are used often.

## 0.4.0

- Fixed a bug where generated SystemVerilog could apply bit slicing to an expression (<https://github.com/intel/rohd/issues/163>).
- Fixed a bug where constant collapsing in SystemVerilog could erroneously remove constant assignments (<https://github.com/intel/rohd/issues/159>).
- Fixed a bug where `Combinational` could have an incomplete sensitivity list causing incorrect simulation behavior (<https://github.com/intel/rohd/issues/158>).
- Significantly improved simulation performance of `Combinational` (<https://github.com/intel/rohd/issues/106>).
- Upgraded and made lints more strict within ROHD, leading to some quality and documentation improvements.
- Added a feature allowing negative indexing to access relative to the end of a `Logic` or `LogicValue` (<https://github.com/intel/rohd/issues/99>).
- Breaking: Increased minimum Dart SDK version to 2.18.0.
- Fixed a bug when parsing unsigned large binary integers (<https://github.com/intel/rohd/issues/183>).
- Exposed `SynthesisResult`s from the `SynthBuilder`, making it easier to generate SystemVerilog modules into independent files (<https://github.com/intel/rohd/issues/172>).
- Breaking: Renamed `topModuleName` to `definitionName` in `ExternalSystemVerilogModule` (<https://github.com/intel/rohd/issues/169>).
- Added the `mux` function as a shortcut for building a `Mux` and returning the output of it (<https://github.com/intel/rohd/issues/13>).
- Deprecation: Improved naming of ports on basic gates, old port names remain accessible but deprecated for now (<https://github.com/intel/rohd/issues/135>).
- Fixed list of reserved SystemVerilog keywords for sanitization (<https://github.com/intel/rohd/issues/168>).

## 0.3.2

- Added the `StateMachine` abstraction for finite state machines.
- Added support for the modulo `%` operator.
- Added ability to register actions to be executed at the end of the simulation.
- Modified the `WaveDumper` to write to the `.vcd` file asynchronously to improve simulation performance while waveform dumping is enabled (<https://github.com/intel/rohd/issues/3>)

## 0.3.1

- Fixed a bug (introduced in v0.3.0) where `WaveDumper` doesn't properly dump multi-bit values to VCD (<https://github.com/intel/rohd/issues/129>).

## 0.3.0

- Breaking: Merged `LogicValue` and `LogicValues` into one type called `LogicValue`.
- Deprecation: Aligned `LogicValue` to `Logic` by renaming `length` to `width`.
- Breaking: `Logic.put` no longer accepts `List<LogicValue>`, swizzle it together instead.
- Deprecated `Logic.valueInt` and `Logic.valueBigInt`; instead use equivalent functions on `Logic.value`.
- Deprecated `bit` on both `LogicValue` and `Logic`; instead just check `width`.
- Added ability in `LogicValue.toString` to decide whether or not to include the width annotation through `includeWidth` argument.
- Fixed a bug related to zero-width construction of `LogicValue`s (<https://github.com/intel/rohd/issues/90>).
- Fixed a bug where generated constants in SystemVerilog had no width, which can cause issues in some cases (e.g. swizzles) (<https://github.com/intel/rohd/issues/89>)
- Added capability to convert binary strings to ints with underscore separators using `bin` (<https://github.com/intel/rohd/issues/56>).
- Added `getRange` and `reversed` on `Logic` and `slice` on `LogicValue` to improve consistency.
- Using `slice` in reverse-index order now reverses the order.
- Added the ability to extend signals (e.g. `zeroExtend` and `signExtend`) on both `Logic` and `LogicValue` (<https://github.com/intel/rohd/issues/101>).
- Improved flexibility of `IfBlock`.
- Added `withSet` on `LogicValue` and `Logic` to make it easier to assign subsets of signals and values (<https://github.com/intel/rohd/issues/101>).
- Fixed a bug where 0-bit signals would sometimes improperly generate 0-bit constants in generated SystemVerilog (<https://github.com/intel/rohd/issues/122>).
- Added capability to reserve instance names, as well as provide and reserve definition names, for `Module`s and their corresponding generated outputs.

## 0.2.0

- Updated implementation to avoid `Iterable.forEach` to make debug easier.
- Added `ofBool` to `LogicValue` and `LogicValues` (<https://github.com/intel/rohd/issues/34>).
- Breaking: updated `Interface` API so that `getPorts` returns a `Map` from port names to `Logic` signals instead of just a list, which makes it easier to work with when names are uniquified.
- Breaking: removed `setPort` from `Interface`.  Use `setPorts` instead.
- Deprecated `swizzle` and `rswizzle` global functions and replaced them with extensions on `List`s of certain types including `Logic`, `LogicValue`, and `LogicValues` (<https://github.com/intel/rohd/issues/70>).
- Breaking: renamed `ExternalModule` to `ExternalSystemVerilogModule` since it is specifically for SystemVerilog.
- Breaking: made `topModuleName` a required named parameter in `ExternalSystemVerilogModule` to reduce confusion.
- Added `simulationHasEnded` bool to `Simulator`.
- Updated `Simulator` to allow for injected actions to return `Future`s which will be `await`ed.
- Fixed bug where `Simulator` warns about maximum simulation time when not appropriate.
- Fixed a bug where `ExternalSystemVerilogModule` could enter infinite recursion.
- Some improvements to `SimCompare` to properly check values at the end of a tick and support a wider variety of values in `Vector`s.
- Fixed a bug related to `Sequential` signal sampling where under certain scenarios, signals would pass through instead of being flopped (<https://github.com/intel/rohd/issues/79>).
- Deprecated a number of `from` functions and replaced them with `of` to more closely follow Dart conventions (<https://github.com/intel/rohd/issues/72>).

## 0.1.2

- Optimized construction of `LogicValues` to improve performance
- Renamed `FF` to `Sequential` (marked `FF` as deprecated) (breaking: removed `clk` signal)
- Added `Sequential.multi` for multi-edge-triggered blocks (<https://github.com/intel/rohd/issues/42>)
- Improved exception and error messages (<https://github.com/intel/rohd/issues/64>)

## 0.1.1

- Fix `Interface.connectIO` bug when no tags specified (<https://github.com/intel/rohd/issues/38>)
- Fix uniquified `Interface.getPorts` bug (<https://github.com/intel/rohd/issues/59>)

## 0.1.0

- The first formally versioned release of ROHD.
