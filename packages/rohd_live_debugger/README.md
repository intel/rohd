# ROHD Live Debugger

The ROHD Live Debugger is an opt-in Dart DevTools extension for inspecting ROHD
design hierarchies, signals, waveforms, and schematics. It runs in Dart DevTools
and does not add a Flutter dependency to the program being debugged.

Add it to the ROHD project's `dev_dependencies`:

```yaml
dev_dependencies:
  rohd_live_debugger: ^0.1.0
```

Run `dart pub get`, start debugging the ROHD program, and open DevTools in a
browser. Enable and select the `rohd_live_debugger` tab if prompted. The program
must register ROHD diagnostics services before the debugger can inspect it.

See the [debugger guide](https://github.com/intel/rohd/tree/main/rohd_devtools_extension)
for setup, examples, and the standalone debugger.
