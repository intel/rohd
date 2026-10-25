# Gate Catalog Tools

`generate_gate_catalog.dart` elaborates the `GateCatalog` module in
`gate_catalog.dart` and writes a netlist JSON catalog. The catalog exercises
the standard gate and primitive mappings used by the netlist synthesizer.

From the repository root:

```sh
dart run tool/catalog/generate_gate_catalog.dart \
  rohd_devtools_extension/assets/gate_catalog.rohd.json
```

Pass another output path as the sole positional argument when generating a
temporary catalog for inspection.
