# Merge Order

Use this order when preparing the current stack of ROHD PRs. This is the
upstream PR order, not necessarily the exact local replay order in
`/home/desmond/Cockpit/build_waves11/baseRepo.sh`.

## Future PR Order

1. `feature/signal-value-format-registry`
2. `add-rohd-waveform-package`
3. `netlist_pre`
4. `module_services_api`
5. `netlist`
6. `fst`
7. `systemc`
8. `systemc_naming`
9. `module_services`
10. `review/systemc-service`
11. `source_debug`
12. `review/systemc-trace-clean`
13. `fst-writer`

`netlist_pre` should be PR'd and merged separately before `netlist`, even though
the local replay script does not merge that branch tip directly. Its changes are
already carried by downstream branches, especially `netlist`.

`feature/signal-value-format-registry` establishes the shared DevTools signal
format registry. Consumer migrations in the wave and schematic viewers must
follow this branch so they resolve one process-wide registry rather than local
copies.

## Local Replay Order

`baseRepo.sh` currently replays the stack in this order:

1. `add-rohd-waveform-package`
2. `module_services_api`
3. `fst`
4. `systemc`
5. `systemc_naming`
6. `module_services`
7. `review/systemc-service`
8. `netlist`
9. `source_debug`
10. `review/systemc-trace-clean`
11. `fst-writer`

The replay order intentionally differs from the PR order because it preserves
the known conflict-resolution path. In particular, `netlist_pre` is not replayed
as a standalone merge, and `fst`/`systemc` remain before `netlist` locally.

These branch tips are intentionally not part of the scripted merge order because
their content is already in upstream `main`, or the branch tip can lag and
overwrite newer upstream changes:

- `devtools`
- `central_naming`
- `netlist_pre`
- `devtool_utilities`
- `rohd_hierarchy`
- `rohd_extension`

The dependency shape is not fully linear, but future PRs should follow the list
above unless the stack changes. If `baseRepo.sh` changes, update this file in
the same change so the PR-order documentation and replay notes stay in sync.

## Last Scratch Check

Validated with a scratch run from `/tmp/baseRepo-scratch.U9OSe4` on 2026-07-15.
The scratch output completed with a clean worktree and matched the protected
committed tree in `/home/desmond/Cockpit/build_waves11/merged`:

```text
scratch tree:   64767f94b60bb3a6944c08d5b3368bbb186f953b
protected tree: 64767f94b60bb3a6944c08d5b3368bbb186f953b
```