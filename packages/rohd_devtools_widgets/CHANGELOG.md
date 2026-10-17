## 0.1.2

- Add shared signal display-format menus and regex utilities, and update shared controls for hierarchy-driven signal formatting.
- Retain hierarchy 0.1.x compatibility and accept ROHD 0.6.10 through 0.7.x.
- Accept Material UI 1.1.0 through 1.x, including 1.7.0, without increasing the Dart or Flutter lower bounds.

## 0.1.1

- Fix the ROHD dependency lower bound: require `^0.6.10` instead of `^0.6.9`,
  since signal formatting uses `toRadixString`'s `includeWidth` and `sepChar`
  parameters introduced in ROHD 0.6.10
  (<https://github.com/intel/rohd/pull/718>).

## 0.1.0

- Initial release of shared ROHD DevTools widgets.
