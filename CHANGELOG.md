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
