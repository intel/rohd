# Repository Tools

This directory contains developer, CI, and release utilities. Run commands
from the repository root unless a tool's documentation says otherwise.

| Directory | Purpose |
| --- | --- |
| [catalog/](./catalog) | Generates the gate-catalog netlist used to exercise cell mapping. |
| [coverage/](./coverage/README.md) | Collects and serves root or package coverage reports. |
| [diagnostics/](./diagnostics) | Regenerates checked-in diagnostic fixture assets. |
| [release/](./release) | Prepares and validates package and VS Code extension releases. |
| [devtools/](./devtools) | Starts and supports local ROHD DevTools development. |
| [gh_actions/](./gh_actions) | Implements GitHub Actions setup, validation, and test steps. |
| [gh_codespaces/](./gh_codespaces) | Configures GitHub Codespaces and development containers. |
| [test/](./test) | Contains hermetic regression tests for shell, workflow, and release helpers. |

The root-level `run_checks.sh` remains a top-level entry point because it
supports the general developer workflow.
