## 0.3.0
- Breaking: Merged `LogicValue` and `LogicValues` into one type called `LogicValue`.
- Deprecation: Aligned `LogicValue` to `Logic` by renaming `length` to `width`.
- Breaking: `Logic.put` no longer accepts `List<LogicValue>`, swizzle it together instead.
- Deprecated `Logic.valueInt` and `Logic.valueBigInt`; instead use equivalent functions on `Logic.value`.
- Deprecated `bit` on both `LogicValue` and `Logic`; instead just check `width`.
- Added ability in `LogicValue.toString` to decide whether or not to include the width annotation through `includeWidth` argument.
- Fixed a bug related to zero-width construction of `LogicValue`s (https://github.com/intel/rohd/issues/90).
- Fixed a bug where generated constants in SystemVerilog had no width, which can cause issues in some cases (e.g. swizzles) (https://github.com/intel/rohd/issues/89)
- Added capability to convert binary strings to ints with underscore separators using `bin` (https://github.com/intel/rohd/issues/56).
- Added `getRange` and `reversed` on `Logic` and `slice` on `LogicValue` to improve consistency.
- Using `slice` in reverse-index order now reverses the order.
- Added the ability to extend signals (e.g. `zeroExtend` and `signExtend`) on both `Logic` and `LogicValue` (https://github.com/intel/rohd/issues/101).
- Improved flexibility of `IfBlock`.
- Added `withSet` on `LogicValue` and `Logic` to make it easier to assign subsets of signals and values (https://github.com/intel/rohd/issues/101).
- Fixed a bug where 0-bit signals would sometimes improperly generate 0-bit constants in generated SystemVerilog (https://github.com/intel/rohd/issues/122).
- Added capability to reserve instance names, as well as provide and reserve definition names, for `Module`s and their corresponding generated outputs.

## 0.2.0
- Updated implementation to avoid `Iterable.forEach` to make debug easier.
- Added `ofBool` to `LogicValue` and `LogicValues` (https://github.com/intel/rohd/issues/34).
- Breaking: updated `Interface` API so that `getPorts` returns a `Map` from port names to `Logic` signals instead of just a list, which makes it easier to work with when names are uniquified.
- Breaking: removed `setPort` from `Interface`.  Use `setPorts` instead.
- Deprecated `swizzle` and `rswizzle` global functions and replaced them with extensions on `List`s of certain types including `Logic`, `LogicValue`, and `LogicValues` (https://github.com/intel/rohd/issues/70). 
- Breaking: renamed `ExternalModule` to `ExternalSystemVerilogModule` since it is specifically for SystemVerilog.
- Breaking: made `topModuleName` a required named parameter in `ExternalSystemVerilogModule` to reduce confusion.
- Added `simulationHasEnded` bool to `Simulator`.
- Updated `Simulator` to allow for injected actions to return `Future`s which will be `await`ed.
- Fixed bug where `Simulator` warns about maximum simulation time when not appropriate.
- Fixed a bug where `ExternalSystemVerilogModule` could enter infinite recursion.
- Some improvements to `SimCompare` to properly check values at the end of a tick and support a wider variety of values in `Vector`s.
- Fixed a bug related to `Sequential` signal sampling where under certain scenarios, signals would pass through instead of being flopped (https://github.com/intel/rohd/issues/79).
- Deprecated a number of `from` functions and replaced them with `of` to more closely follow Dart conventions (https://github.com/intel/rohd/issues/72).

## 0.1.2
- Optimized construction of `LogicValues` to improve performance
- Renamed `FF` to `Sequential` (marked `FF` as deprecated) (breaking: removed `clk` signal)
- Added `Sequential.multi` for multi-edge-triggered blocks (https://github.com/intel/rohd/issues/42)
- Improved exception and error messages (https://github.com/intel/rohd/issues/64)

## 0.1.1
- Fix `Interface.connectIO` bug when no tags specified (https://github.com/intel/rohd/issues/38)
- Fix uniquified `Interface.getPorts` bug (https://github.com/intel/rohd/issues/59)

## 0.1.0

- The first formally versioned release of ROHD.
