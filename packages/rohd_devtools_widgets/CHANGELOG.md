## 0.2.0

- Add shared signal display-format menus and regex utilities, and update
  shared controls for hierarchy-driven signal formatting.

## 0.1.1

- Fix the ROHD dependency lower bound: require `^0.6.10` instead of `^0.6.9`,
  since signal formatting uses `toRadixString`'s `includeWidth` and `sepChar`
  parameters introduced in ROHD 0.6.10
  (<https://github.com/intel/rohd/pull/718>).

## 0.1.0

- Initial release of shared ROHD DevTools widgets.
