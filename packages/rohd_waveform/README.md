# rohd_waveform

Pure-Dart waveform data services and models for ROHD wave viewers.

This package supplies waveform value data to remote clients, viewers, and
debugging tools while using [`rohd_hierarchy`](../rohd_hierarchy) for module
and signal structure. It defines the boundary between a waveform source, such
as a simulator, debugger, VCD/Wellen reader, or DevTools connection, and a UI
that needs signal values over time.

## Service

`rohd_waveform` provides a small service layer for requesting, caching, and
streaming waveform values:

- `SignalWaveformApi` defines the source-facing API for loading waveform data,
  streaming incremental updates, reading the current simulation time, and
  retrieving value snapshots.
- `SignalWaveformRepository` wraps a `SignalWaveformApi`, waits for asynchronous
  sources to become ready, caches signal metadata and waveform values, and can
  synthesize computed sub-field waveforms from parent signal data.
- `SignalDataService` exposes a signal-centric interface for clients that work
  with `SignalOccurrence` objects from `rohd_hierarchy`.
- `RepositorySignalDataService` adapts the repository cache into `WaveData`
  objects for wave viewers and other clients.

The package does not include a waveform backend. Applications provide a
concrete `SignalWaveformApi` implementation for their data source, while this
package handles the shared service contract, caching, and transfer models.

## Models

The package also includes waveform-specific models used across the service
boundary:

- `ModuleStructure` — top-level waveform structure metadata and hierarchy roots.
- `WaveformData` — transfer payload returned by a `SignalWaveformApi` fetch or
  stream. It carries a signal ID, data points, and whether the values were
  computed, but it does not provide hierarchy metadata or lookup behavior.
- `SignalWaveform` — repository/client-side waveform state for one signal. It
  can be built from `WaveformData`, appended to over time, queried by time or
  range, and linked back to `SignalOccurrence` metadata through a lookup
  function.
- `WaveformUpdateEvent` — event payload for waveform update notifications.
- `WaveData` — combined `SignalOccurrence` metadata and waveform data returned
  by `SignalDataService`.
- `Data`, `WaveFormat`, and `MetaData` — waveform data primitives.

In short, use `WaveformData` at the service/API boundary and `SignalWaveform`
inside clients or repositories that need cached state, incremental appends,
metadata access, or waveform queries.

For hierarchy types such as `HierarchyOccurrence` and `SignalOccurrence`,
import `package:rohd_hierarchy/rohd_hierarchy.dart` directly.

----------------
Copyright (C) 2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
