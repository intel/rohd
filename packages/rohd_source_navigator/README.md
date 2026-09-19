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

The existing focused imports remain supported:

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

This is a Dart library, not an editor extension. The
[ROHD VS Code extension](https://github.com/intel/rohd/tree/main/rohd_extension)
continues to use its separate TypeScript implementation; installing this
package does not install or activate that extension.

## Migrating from a Git dependency

Once version 0.1.0 is available on pub.dev, replace the Git dependency with:

```yaml
dependencies:
  rohd_source_navigator: ^0.1.0
```

Also remove any Git or path entry for `rohd_source_navigator` from
`dependency_overrides` or `pubspec_overrides.yaml`; otherwise Pub will continue
using that override instead of the hosted package. Run `dart pub get` (or
`flutter pub get`) to update the lockfile. Existing Dart imports do not change.

If continuing to use a Git dependency at a commit containing the package move,
change its `path` from `rohd_extension/dart` to
`packages/rohd_source_navigator`. Dependencies pinned to older commits or tags
keep their original path.

## Development

The package lives in `packages/rohd_source_navigator` in the ROHD repository. Run
`dart pub get`, `dart analyze`, and `dart test` from that directory.
Use `dart pub publish --dry-run` there to inspect the publication archive, or
`tool/check_release.sh rohd_source_navigator` from the repository root.
