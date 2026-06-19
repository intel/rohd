# 🛠 ROHD DevTools — Help

<!-- tooltip -->

Connection
  ||  Pause         Pause VM connection
  ▷  Resume         Resume VM connection
  🔗  Connect      Open connection dialog
  🔃  Refresh      Reload module tree

Module Tree (left panel)
  Click node       Select module
  Click ▸ / ▾      Expand / collapse
  🔃  Refresh      Reload hierarchy from VM
  Type in search   Filter modules by name

Waveform Viewer (details tab)
  ← / →            Pan left / right
  Shift+↑ / ↓      Zoom in / out
  Shift+Scroll     Zoom at cursor
  F                Fit to viewport
  Click waveform   Place time marker

Schematic Viewer (details tab)
  Scroll           Zoom in / out
  F                Fit to canvas
  Ctrl+F           Search blocks & wires
  Click +/−/⊞      Expand / collapse blocks

Snapshots
  📸  Camera       Capture all signal values
  🎥  Video        Auto-track on breakpoints

Go to Source (requires ROHD Extension)
  Right-click signal  Open source location picker
  DTD URI             Copy from DevTools status bar
  ROHD Extension      Activate in VS Code for source nav

<!-- details -->

## Connection Management

| Key | Description |
| --- | --- |
| Pause | Pause the VM connection |
| Resume | Resume the VM connection |
| 🔗  Connect | Open connection dialog to attach to a VM |
| 🔃  Refresh | Reload module tree from the VM |

## Module Tree (left panel)

| Key | Description |
| --- | --- |
| Click module | Select module and show signals |
| Click ▸ / ▾ | Expand or collapse sub-modules |
| 🔃  Refresh | Reload hierarchy from the VM |
| Type in search | Filter modules by name |

## Waveform Viewer

| Key | Description |
| --- | --- |
| ← / → | Pan waveform left / right |
| ↑ / ↓ | Scroll signal list up / down |
| Shift + ↑ / ↓ | Zoom in / zoom out |
| Shift + Scroll | Zoom in / out at cursor |
| Scroll wheel | Pan horizontally |
| F | Fit entire waveform to viewport |
| Ctrl + Drag | Draw a time region to zoom into |
| Click waveform | Place time marker |
| ← / → (focused) | Jump to previous / next edge |
| Click signal name | Add signal to monitor list |
| DEL | Remove focused signals from monitor list |

## Schematic Viewer

| Key | Description |
| --- | --- |
| Scroll wheel | Zoom in / out at cursor |
| F | Fit entire schematic to canvas |
| Ctrl + F  /  ⌘F | Open search overlay |
| Click + | Fully expand block |
| Click − | Collapse block |
| Click ⊞ | Expand non-primitive children only |
| Click port ▶ | Reveal the connected block |
| Shift + Click ▶ | Expand through trivial gates |
| Double-click | Zoom to block or wire |
| Drag | Pan canvas |

## Snapshots

| Key | Description |
| --- | --- |
| 📸  Camera | Capture all signal values at current time |
| 🎥  Video | Auto-track signal values on breakpoints |

## Go to Source — ROHD Extension

The **Go to Source** feature lets you jump from a signal in the waveform or
schematic viewer directly to the Dart source code that defines it.  It
requires the **ROHD Extension** for VS Code.

### Setup

1. **Install the ROHD Extension** — open the Extensions panel in VS Code and
   install `rohd-extension` (the `.vsix` from the `rohd_extension/`
   directory).
2. **Copy the DTD URI** — when the DevTools app connects to a running
   ROHD simulation, the Dart Tooling Daemon (DTD) URI is shown in the
   connection log (e.g. `ws://127.0.0.1:43369/xiiRI61v9qc=`).  Copy this
   URI.
3. **Activate the ROHD Extension** — open the VS Code Command Palette
   (`Ctrl+Shift+P`) and run **ROHD: Connect to DTD**.  Paste the DTD URI
   when prompted.  The extension registers source-navigation services
   (`rohd.goToSource`, `rohd.resolveFrames`) on the DTD so the DevTools
   app can request editor navigation.

### Using Go to Source

| Action | Description |
| --- | --- |
| Right-click signal (waveform) | Triggers Go to Source for that signal |
| Right-click signal (schematic) | Triggers Go to Source for that signal |
| Single source frame | Editor opens the file and line automatically |
| Multiple source frames | A popup picker appears listing each call site |

When the ROHD compiler records multiple source locations for a signal
(e.g. a port wired through several `build()` methods), a **popup menu**
appears near your click.  Each entry shows the enclosing method name and
file location (e.g. `Serializer.build() — serializer.dart:55`).  Select
an entry to open that location in VS Code.

If the ROHD Extension is not connected, Go to Source falls back to opening
the outermost (first) frame automatically via the VM service.
