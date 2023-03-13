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
