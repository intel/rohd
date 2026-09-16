# rohd_source_navigator

Internal Dart port of ROHD source-navigation logic, including source frames,
path normalization, frame cycling, file/line/column data, and a Dart Tooling
Daemon (DTD) service. This package uses `publish_to: none` and is not released
on pub.dev.

The [ROHD VS Code extension](../README.md) uses its TypeScript implementation.
Its `npm run compile` command runs `tsc` to generate JavaScript in `out/`, and
`.vscodeignore` excludes `dart/` from the VSIX. This Dart port is not compiled
to JavaScript or consumed by the extension's current build.

## Development

Run `dart pub get`, `dart analyze`, and `dart test` from this directory.