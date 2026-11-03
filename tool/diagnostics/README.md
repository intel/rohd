# Diagnostic Fixture Tools

`gen_filterbank_flc.dart` regenerates the checked-in FilterBank netlist and FLC
fixture assets used by ROHD DevTools and source-navigation development.

From the repository root:

```sh
dart run tool/diagnostics/gen_filterbank_flc.dart
```

The generator intentionally rewrites fixture assets under
`rohd_devtools_extension/` and the developer-local schematic-viewer asset under
`$HOME/release/rohd-schematic-viewer/`. Review its output before committing
regenerated files.
