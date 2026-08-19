# ROHD DevTools Widgets

Shared Flutter widgets and utilities for ROHD DevTools debugger views.

This package contains reusable UI pieces used across ROHD debugger tools such as
schematic and waveform viewers. It is intended for common controls,
presentation helpers, and extension-facing models that should stay consistent
across DevTools packages.

## What It Provides

- `MarkdownHelpButton` for structured in-app help content.
- `AppBarOverlay` for auto-hiding toolbar layouts in dense viewer surfaces.
- `ExportPngButton`, `captureBoundaryToPng`, `showExportToast`, and platform
 PNG save helpers for screenshot/export flows.
- `CrossProbeService`, `LocalCrossProbeChannel`, `LocalCrossProbeService`,
 `NullCrossProbeService`, and `CrossProbeButton` for sharing signal selections
 between viewers.
- Source-navigation menu helpers, including `buildGotoSourceMenuItems`,
 `sourceFormatIconStrip`, and related `RohdSourceFormat` formatting utilities.
- Bit-expansion menu and dialog helpers for multi-bit signals:
 `buildBitExpansionMenuItems`, `resolveBitExpansionMenuValue`,
 `BitExpandRangeAction`, `BitDefineFieldsAction`, and `BitFieldDef`.
- Logic-type formatting utilities, including `expandLogicType`,
 `formatFieldValue`, and `formatTypeTooltip`.
- ROHD extension client/status abstractions: `RohdExtensionClient`,
 `NullExtensionClient`, `RohdModuleInfo`, and `RohdFormatInfo`.

## Widgets & Utilities

### UI Controls & Buttons

- **`MarkdownHelpButton`** — A help button that displays Markdown content from an asset file in a dialog. Supports tooltip text and rich formatting.

- **`ExportPngButton`** — A camera icon button for triggering PNG export functionality. Includes customizable tooltip text.

- **`CrossProbeButton`** — A toolbar button for toggling cross-probing between viewers. Shows a bidirectional arrows icon that reflects the active/inactive state.

### Overlays & Layout

- **`AppBarOverlay`** — An auto-hiding AppBar that slides in from the top edge when the mouse approaches. When disabled, behaves like a standard AppBar.

### Export & Capture

- **`CaptureBoundary`** — Utility for capturing a `RepaintBoundary` as PNG, saving/downloading, and showing user feedback via toast notifications.

- **`ExportToast`** — Toast notification widget for export feedback and status messages.

### Cross-Probing

- **`CrossProbeService`** — Service for managing cross-probe state between multiple viewers/debuggers. Handles bidirectional signal selection synchronization.

- **`CrossProbeMenu`** — Shared context menu integration for cross-probing actions across different ROHD DevTools surfaces.

### Signal & Bit Field Utilities

- **`LogicTypeUtils`** — Utilities for working with ROHD logic types and formatting logic values for display.

- **`BitFieldUtils`** — Utilities for parsing, validating, and formatting bit field ranges and named bit fields.

- **`BitExpansionMenu`** — Shared popup menu items for "Expand Bits" and "Define Bit Fields" actions used across signal selection overlays and panels.

- **`SignalValueFormatRegistry`** — Shared registry for signal display-format preferences, allowing consistent formatting across multiple viewers.

### Extension Integration

- **`RohdExtensionClient`** — Abstract interface for querying the ROHD VS Code extension. Supports multiple implementations (DevTools, VS Code webview, offline mode).

- **`RohdExtensionStatus`** — Status information and connection state for the ROHD extension.

## Usage

Add this package as a path dependency from a ROHD DevTools package and import the shared widgets you need:

```dart
import 'package:rohd_devtools_widgets/rohd_devtools_widgets.dart';
```

The package exports a single barrel library. Consumers should import
`rohd_devtools_widgets.dart` rather than reaching into `lib/src`.

----------------
Copyright (C) 2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
