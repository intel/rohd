# Release Tools

These tools prepare and validate release inputs. They do not publish to pub.dev,
create tags, push branches, or upload Marketplace artifacts. `local_pub.sh`
deliberately forwards an explicitly requested command to a loopback local
registry, and `prepare_release_metadata.dart` performs the documented local
metadata preparation step. See [the release guide](../../doc/releases.md) for
the complete process.

| Tool | Purpose |
| --- | --- |
| `prepare_release.sh` | Prepares selected package metadata, validates required artifacts, runs enabled checks, and performs publication dry runs. |
| `check_release.sh` | Checks selected publication archives with `pub publish --dry-run`. |
| `run_pana.sh` | Runs isolated hosted-dependency compatibility and Pana score gates. |
| `local_pub.sh` | Runs a command against an already-running loopback Pub registry with an isolated cache. |
| `package_vscode.sh` | Builds and verifies a local Marketplace-qualified ROHD VSIX. |
| `prepare_release_metadata.dart` | Internal metadata helper invoked by `prepare_release.sh`. |

Common commands from the repository root:

```sh
bash tool/release/prepare_release.sh --run-tests
bash tool/release/check_release.sh rohd_hierarchy rohd_waveform
bash tool/release/run_pana.sh rohd_source_navigator
bash tool/release/package_vscode.sh /absolute/path/to/check.vsix
```

For local hosted-package experiments, see
[local Pub testing](../../doc/local_pub_testing.md).
