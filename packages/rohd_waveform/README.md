# rohd_waveform

Pure-Dart waveform data models and APIs for ROHD wave viewers.

This package provides waveform-specific data models that build on top of
[`rohd_hierarchy`](../rohd_hierarchy):

- `ModuleStructure` — top-level waveform structure (metadata + hierarchy roots).
- `SignalWaveform` — time-series waveform data with a backpointer to signal
  metadata in `rohd_hierarchy`.
- `WaveformData` — transfer object for incremental waveform updates.
- `Data`, `WaveFormat`, and `MetaData` — waveform data primitives.

For hierarchy types such as `HierarchyOccurrence` and `SignalOccurrence`,
import `package:rohd_hierarchy/rohd_hierarchy.dart` directly.

## Status

This is a small, dependency-light starting package. It depends only on
`equatable` and `rohd_hierarchy`, and does **not** depend on any waveform
backend (such as a Wellen/FFI reader). Backend integrations live in separate
packages that depend on `rohd_waveform`.

## Testing

```sh
dart pub get
dart test
```
