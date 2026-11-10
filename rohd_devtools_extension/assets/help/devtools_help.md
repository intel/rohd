# ROHD Live Debugger v{{VERSION}} — Help

<!-- tooltip -->

Connection
  Connect to a Dart VM or discover one through DTD.
  Pause / resume controls waveform updates, not the simulation.

Module Tree
  Select, expand, or search for modules.

Right Pane
  Details      Inspect the selected module's signals.
  Waveform     Monitor and navigate signal histories.
  Schematic    Explore the design's connectivity.
  ❓           Open help for the selected pane.

<!-- details -->

## Connection and Setup

Build the design and register its ROHD diagnostics services before connecting.
The standalone debugger can discover a VM through DTD or connect to a VM
service URI. The embedded extension uses the Dart DevTools connection.

| Action | Description |
| --- | --- |
| Connect | Connect or switch VM in the standalone debugger |
| Pause / resume | Pause or resume waveform updates; the simulation keeps running |
| Refresh | Reload the hierarchy and available design data |
| Load Design / Waveform | Open local design and waveform files in standalone loopback mode |
| ROHD logo | Open the ROHD website in a browser |

## Module Tree

| Action | Description |
| --- | --- |
| Click module | Select a module for the right pane |
| Click ▸ / ▾ | Expand or collapse submodules |
| Search Modules | Search module names and paths |
| 🔃 Refresh | Reload the hierarchy |

## Details

| Action | Description |
| --- | --- |
| Signal list | Inspect the selected module's signals, widths, and values |
| Search / filter | Find signals and choose visible signal directions |
| Send signals | Send selected signals to other panes |
| Go to Source | Navigate to available source locations |

## Waveform

| Action | Description |
| --- | --- |
| Monitor signals | Add signals and inspect their captured values over time |
| Navigate | Pan, zoom, fit the waveform, or place a time marker |
| Snapshot | Inspect values at a selected time when snapshots are available |

## Schematic

| Action | Description |
| --- | --- |
| Explore design | Inspect blocks, ports, wires, and connectivity |
| Expand / collapse | Navigate the hierarchy and reveal connected blocks |
| Zoom / fit | Adjust the schematic view |

## Shell and Pane Help

The standalone debugger includes a ROHD Debug Shell below the module tree.
Use its help button for command syntax and available operations.
The question-mark button in the right pane opens detailed help for the
currently selected Details, Waveform, or Schematic tab.

## Tools

The embedded extension's Tools menu opens the hosted Wave Viewer, Schematic
Viewer, and Live Debugger in separate browser tabs. They require network
access and do not automatically share the embedded connection.
