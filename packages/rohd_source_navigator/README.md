# rohd_source_navigator

Shared Dart source-navigation models and utilities for ROHD debug tools,
including the [ROHD Schematic Viewer](https://github.com/intel/rohd-schematic-viewer).

## Installation

```sh
dart pub add rohd_source_navigator
```

For Flutter applications, use `flutter pub add rohd_source_navigator`.

## API

- `FlcData`, `FlcEntry`, and `FlcFrame`: parse and look up file/line/column
  traces from v5/v6 FLC hierarchy JSON or embedded netlist trace attributes.
- `SourceFrame` and `FrameCycler`: represent source locations and cycle through
  a selection's frames.
- `normalizePath` and `resolveCandidatePaths`: prepare source paths for a
  host application's file resolution.
- `DtdService` and request encoding helpers: source-navigation communication
  for Dart Tooling Daemon integrations.

Import the complete API:

```dart
import 'package:rohd_source_navigator/rohd_source_navigator.dart';
```

Use focused imports for FLC data, source-navigation utilities, or DTD integration:

```dart
import 'package:rohd_source_navigator/flc_data.dart';
import 'package:rohd_source_navigator/source_navigator.dart';
import 'package:rohd_source_navigator/dtd_service.dart';
```

For example, look up a signal's source location:

```dart
import 'package:rohd_source_navigator/flc_data.dart';

void main() {
  final data = FlcData.fromJson({
    'version': 5,
    'files': ['lib/top.dart'],
    'modules': {
      'Top': {
        'tree': [
          ['0:42:5', 'result'],
        ],
      },
    },
  });

  final frames = data.lookupSignal('Top', 'result');
  print(frames?.first); // lib/top.dart:42:5 [rohd]
}
```

This is a Dart library, not an editor extension. Installing this package does not
install or activate the
[ROHD VS Code extension](https://github.com/intel/rohd/tree/main/rohd_extension)
or its separate TypeScript implementation.

## Development

The package lives in `packages/rohd_source_navigator` in the ROHD repository. Run
`dart pub get`, `dart analyze`, and `dart test` from that directory.
