# ROHD VS Code Extension

A VS Code extension for the [ROHD](https://github.com/intel/rohd) hardware
design framework.  It provides context-aware Dart code snippets, cross-probe
source navigation from ROHD viewers (schematic, waveform), and automatic
port-forwarded URI display for the Dart Tooling Daemon (DTD) and VM Service.

## Features

- **Context-aware ROHD snippets** — conditional constructs (`If`, `Iff`,
  `Else`, `Case`, `CaseZ`) only appear when the cursor is inside
  a `Combinational` or `Sequential` block. Module-body patterns
  (`Sequential`, `Combinational`, `Pipeline`, current-module `FSM`, etc.)
  only appear inside a module body.
- **Cross-probe source navigation** — click a signal or module in an ROHD
  viewer and jump directly to the corresponding Dart source (FLC — **F**ile,
  **L**ine, **C**olumn — crossprobing).
- **Debug adapter tracking** — registers a `DebugAdapterTrackerFactory` for
  Dart sessions to automatically capture DTD and VM Service URIs with
  port-forwarding awareness.
- **DTD bridge** — registers `rohd.goToSource` / `rohd.resolveFrames`
  services on the Dart Tooling Daemon so the DevTools extension can navigate
  the editor remotely.

On activation the extension prints:

```text
════════════════════════════════════════════════════════════
ROHD 0.1.0:  Extension loaded for FLC crossprobing.

DTD:
  URI: ws://127.0.0.1:44123/token
  Fwd: ws://localhost:58201/token        ← only shown if port differs
VM:
  URI: ws://127.0.0.1:40699/TOKEN=/ws
  Fwd: ws://localhost:61969/TOKEN=/ws    ← only shown if port differs
════════════════════════════════════════════════════════════
```

## Snippets

Snippets are registered for Dart files.  Open a `.dart` file and make sure
VS Code shows **Dart** as the language mode in the lower-right status bar.

VS Code does not always expand snippets from `prefix<Tab>` by default.  If
typing `mod<Tab>` only accepts a normal Dart completion, use one of these
flows:

1. Type `mod`, press **Ctrl+Space** to open suggestions, select
   **ROHD: Create Module**, then press **Enter** or **Tab**.
2. Enable tab expansion in your VS Code settings:

   ```json
   {
     "editor.tabCompletion": "onlySnippets",
     "editor.snippetSuggestions": "top"
   }
   ```

   With that setting, `mod<Tab>` expands the ROHD module snippet directly
   when no higher-priority editor action is using Tab.

The extension also has context-aware completion snippets, such as showing
`If`, `Case`, and conditional assignment only inside `Combinational` or
`Sequential` blocks.  These are controlled by the ROHD setting
`rohd.enableCompletions`, which is enabled by default.  If it was disabled,
enable it manually in Settings or add this to `settings.json`:

```json
{
  "rohd.enableCompletions": true
}
```

After changing extension settings or installing a new VSIX, reload the VS Code
window with **Developer: Reload Window**.

### Static snippets

These snippets are contributed by VS Code's snippet system. Context-aware
completions below narrow the ROHD-specific options by cursor location.

| Prefix | Expands to | Description |
|--------|-----------|-------------|
| `mod`, `Module` | `class … extends Module { … }` | Module scaffold with `clk`, `reset`, `a`/`b` inputs, `depth`, `latchData`, `addInput`/`addOutput`, `definitionName`, and instance naming parameters |
| `sim`, `Simulator` | Clock, reset, `WaveDumper`, `Simulator.run()` | Simulation / testbench boilerplate |
| `fsmModule`, `FSMModule` | enum + `class extends Module` + `FiniteStateMachine` | Full standalone FSM module scaffold |
| `vf`, `tb`, `testbench` | `rohd_vf` testbench | Agent / Driver / Monitor / Sequencer template |

### Context-aware — file scope

These appear only at file/top level (not inside a function or class body).

| Prefix | Expands to | Description |
|--------|-----------|-------------|
| `FSM`, `fsm` | enum + `class extends Module` + `FiniteStateMachine` | Full FSM scaffold at file level from context-aware completions |
| `Module`, `mod` | `class extends Module { addInput/addOutput … }` | Module scaffold with `clk`, `reset`, `a`/`b` inputs, `depth`, `latchData`, `definitionName`, and instance naming parameters |
| `Interface`, `intf` | enum + `class extends Interface<Dir>` + `clone()` | Classic Interface with direction enum, `setPorts`, and `clone()` |
| `PairInterface`, `pairintf` | `class extends PairInterface { … clone() }` | PairInterface with provider/consumer roles |

### Context-aware — module body scope

These appear when the cursor is inside a `class … extends Module` body.

| Prefix | Expands to | Description |
|--------|-----------|-------------|
| `FSM`, `fsm` | `FiniteStateMachine` for the current module | Inserts states and the FSM constructor call; inserts the enum before the enclosing class |
| `Pipeline`, `pipe` | `Pipeline(clk, stages: [(p) => […]])` | Pipelined datapath |
| `ReadyValidPipeline`, `rvpipe` | `ReadyValidPipeline(clk, stages: …, valid, ready)` | Pipeline with flow control |
| `Sequential`, `Seq`, `seq` | `Sequential(clk, [If(a, …)])` | `always_ff` block |
| `Combinational`, `Comb`, `comb` | `Combinational([…])` | `always_comb` block |
| `assign` | `out <= expr;` | Continuous assignment outside `_Always` blocks |

### Context-aware — inside `Combinational` or `Sequential`

These snippets only appear when the cursor is inside a `Combinational([…])`
or `Sequential(clk, […])` block, matching ROHD's requirement that
conditionals live inside an `_Always` block.

| Prefix | Expands to | Description |
|--------|-----------|-------------|
| `If` | `If(cond, then: […], orElse: […])` | Inline if/else (most common) |
| `ifthen` | `If(cond, then: […])` | Simple conditional guard |
| `ifnested`, `iforelse` | `If(a, then: …, orElse: [If(b, …)])` | Nested if / else-if / else chain |
| `If.block`, `ifblock` | `If.block([Iff(…), ElseIf(…), Else(…)])` | Flat if/else-if/else block chain |
| `Iff`, `iff` | `If.block([Iff(…), ElseIf(…), Else(…)])` | Complete if/elseif/else block using `Iff` as the first clause |
| `Else`, `else` | `Else([…])` | Final clause in `If.block` |
| `Case` | `Case(expr, [CaseItem(…)], …)` | `case` / `unique case` / `priority case` |
| `CaseZ`, `casez` | `CaseZ(expr, [CaseItem(…)])` | Don't-care matching with `z` syntax |
| `CaseItem`, `caseitem` | `CaseItem(value, […])` | Single arm inside `Case`/`CaseZ` |
| `assign` | `out < expr,` | Conditional assignment (inside `_Always`) |

> **Note:** bare `Iff` (two f's) is *not* a standalone conditional. It is the
> first entry in an `If.block([…])` chain. The `Iff` snippet expands to the
> full `If.block` form so it can be inserted directly inside `Sequential` or
> `Combinational`.

### Context-aware — `test/` directory

These appear only in Dart files under a `test/` directory.

| Prefix | Expands to | Description |
|--------|-----------|-------------|
| `test`, `Test` | `test('description', () async { … })` | Async package:test case |
| `group`, `Group` | `group('description', () { test(…) })` | Test group with an async test inside |
| `tearDown`, `resetTest` | `tearDown(() async { await Simulator.reset(); })` | Reset ROHD simulation state between tests |
| `rohdtest`, `simtest`, `testsim` | Clock/reset/DUT build/`Simulator.run()` scaffold | ROHD simulation test flow based on common ROHD-HCL tests |

## FLC Cross-Probing

FLC (**F**ile, **L**ine, **C**olumn) data maps every signal and submodule
in the generated output back to the Dart source location where it was
constructed.  The extension uses FLC data to navigate from a schematic or
waveform viewer directly to the ROHD Dart source.

### FLC JSON Format (v6)

An `.flc.json` file uses a shared ROHD source file table plus a per-module
trie of source frames.  Each trie leaf is a compact symbol string for a
signal or submodule instance:

```json
{
  "version": 6,
  "files": [
    "lib/src/my_module.dart",
    "lib/src/modules/gates.dart"
  ],
  "modules": {
    "Top": {
      "outputFiles": {
        "sv": ["Top.sv"],
        "sc": ["Top.cpp"]
      },
      "tree": [
        [
          "0:6:20",
          ["0:15:9", "a@sv:2:19,8:7;sc:44:5"],
          ["0:16:15", "b@sv:3:20~originalB"],
          ["1:22:3", "*inner@sv:7:1"]
        ]
      ]
    }
  }
}
```

- **`version`** — v6 is the current format. The extension can still parse
  v5; other explicit versions are rejected.
- **`files`** — array of ROHD source paths, indexed by the first number in
  each trie frame.
- **`outputFiles`** — map from output language to generated file list, for
  example `"sv": ["Top.sv"]` or `"sc": ["Top.cpp"]`. The first file for
  each language is the canonical lookup target.
- **`tree`** — list of trie root nodes. Each node starts with a source frame
  string, then contains child nodes and/or symbol strings that share that
  source-frame prefix.
- **`"0:15:9"`** — ROHD source frame: file index 0, line 15, column 9.
  The column is optional and defaults to 1.
- **`"a@sv:2:19,8:7;sc:44:5"`** — signal `a`, with two SystemVerilog
  output positions and one SystemC output position. Output-language groups
  are separated by semicolons; entries within one language are separated by
  commas. The language tag appears on the first entry in the group, so
  `sv:2:19,8:7` means `sv:2:19` and `sv:8:7`.
- **`"b@sv:3:20~originalB"`** — canonical signal name `b`, original source
  name `originalB`. Lookups may use either name.
- **`"*inner@sv:7:1"`** — submodule instance `inner`. Instance symbols are
  prefixed with `*`; signal symbols are not.

Source frames accumulate along the trie path from outermost to innermost.
When the extension opens ROHD source frames, it presents them innermost first
so the construction site closest to the signal or instance is selected first.

## Commands

| Command | Title |
|---------|-------|
| `rohd.openSourceLocation` | Go to Source Location |
| `rohd.openSourceLocations` | Go to Source Locations (multi-frame) |
| `rohd.nextSourceLocation` | Next Source Frame |
| `rohd.prevSourceLocation` | Previous Source Frame |
| `rohd.connectDtd` | Connect to Dart Tooling Daemon |
| `rohd.showForwardedUris` | Show Forwarded DTD/VM URIs |

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `rohd.enableCompletions` | `true` | Enable context-aware ROHD completions. Set `false` to disable the provider. |
| `rohd.dtdUri` | `""` | WebSocket URI of the Dart Tooling Daemon. Leave empty for auto-discovery. |

## Prerequisites

- **Node.js >= 22** for the pinned VSIX packaging tool (CI uses Node 24):

  ```bash
  nvm install
  nvm use
  node --version
  ```

- **npm** (comes with Node)

## Build

```bash
cd rohd_extension
npm ci
npm run compile        # produces out/extension.js
```

## Local Installation

### Package as VSIX

```bash
cd rohd_extension
npm run package
```

This produces `rohd-0.1.0.vsix`.

### Install

```bash
code --install-extension rohd-0.1.0.vsix --force
```

Then reload the VS Code window (**Developer: Reload Window**).

### One-liner (build + install)

```bash
cd rohd_extension \
  && npm ci \
  && npm run package \
  && code --install-extension rohd-0.1.0.vsix --force \
  && echo "Done — reload the VS Code window to activate."
```

## Remote Installation (Dev Containers / SSH)

Extensions that interact with the Dart debug adapter must be installed on the
**remote** side (inside the container or on the SSH host).

### Option 1: devcontainer.json (recommended)

Place the extension source in your repo and build it on container creation:

```jsonc
// .devcontainer/devcontainer.json
{
  "postCreateCommand": "cd rohd_extension && npm ci && npm run package && code --install-extension rohd-0.1.0.vsix --force"
}
```

### Option 2: Pre-built VSIX

Build the `.vsix` on your host or in CI, then install at container start:

```jsonc
{
  "postStartCommand": "code --install-extension rohd_extension/rohd-0.1.0.vsix --force"
}
```

### Option 3: Install via CLI while connected

```bash
code --install-extension rohd-0.1.0.vsix --force
```

The `code` CLI inside a remote session targets the VS Code Server
automatically.

### Option 4: Install via VS Code UI

1. Connect to the remote host / container.
2. Open Extensions (`Ctrl+Shift+X`).
3. Click `...` → **Install from VSIX...** and select the `.vsix` file.
4. Reload the window.

### Option 5: Copy directly into `.vscode-server/extensions/`

If the `code` CLI is not available (e.g. in a Dockerfile `RUN` step):

```bash
mkdir -p ~/.vscode-server/extensions/rohd.rohd-0.1.0
cp -r rohd_extension/{package.json,out,snippets,resources} \
  ~/.vscode-server/extensions/rohd.rohd-0.1.0/
```

The directory name must follow the pattern `<publisher>.<name>-<version>`.

## File Structure

```text
rohd_extension/
├── package.json          # Extension manifest
├── tsconfig.json         # TypeScript configuration
├── src/
│   ├── extension.ts      # Entry point — activates all modules
│   ├── source_navigator.ts  # Cross-probe → editor navigation
│   ├── dtd_bridge.ts     # DTD JSON-RPC bridge
│   ├── debug_tracker.ts  # Debug adapter tracker (DTD/VM URIs)
│   └── conditional_completions.ts  # Context-aware conditional snippets
├── out/                  # Compiled JS (generated)
├── snippets/
│   └── rohd.json         # ROHD Dart snippets
└── resources/
    └── rohd_icon.png     # Extension icon
```

## License

BSD-3-Clause — see the repository root LICENSE file.
