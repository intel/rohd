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
