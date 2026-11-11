# ROHD DevTools application notes

This private Flutter application is not independently published or released.
CI builds its web bundle and includes it in the opt-in `rohd_live_debugger`
pub.dev package under `extension/devtools`.

The `version` in `pubspec.yaml` is Flutter build metadata shown in the help
dialog. Keep it aligned with the debugger package and DevTools `config.yaml`
versions. Release notes are recorded in the debugger package's
[`CHANGELOG.md`](../packages/rohd_live_debugger/CHANGELOG.md).
