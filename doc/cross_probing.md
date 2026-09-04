# Cross-Probing with FLC (File-Line-Column) Traces

ROHD can record the Dart source location of every signal and submodule
created during `Module.build()`, then embed that information alongside
the synthesised output.  This enables **cross-probing**: clicking a
signal in generated SystemVerilog, a Yosys netlist, or an HTML viewer
and jumping straight to the Dart code that created it.

## Quick-Start

All scenarios share the same prerequisite — enable the tracer **before**
the build:

```dart
import 'package:rohd/rohd.dart';

SignalSourceTracer.enabled = true;
final mod = Top(Logic(name: 'a', width: 8));
await mod.build();
SignalSourceTracer.enabled = false;
```

From here the APIs diverge into progressively richer output styles.

---

## 1. Source-Only FLC (simplest)

Maps every signal and submodule instance to the Dart source line where
it was constructed.  No SystemVerilog synthesis is needed.

```dart
final flc = SignalSourceTracer.traceJsonForHierarchy(
    mod, packageRoot: Directory.current.path);
print(jsonEncode(flc));
```

Output (FLC v2 JSON):

```json
{
  "version": 2,
  "files": [
    "lib/src/my_module.dart",
    "lib/src/modules/gates.dart"
  ],
  "modules": {
    "Top": {
      "signals": {
        "a": ["0:15:9"],
        "b": ["0:16:15"]
      },
      "instances": {
        "inner": ["0:6:20", "0:17:17"]
      }
    },
    "Inner": {
      "signals": {
        "a": ["0:7:9"],
        "b": ["0:8:15"]
      },
      "instances": {
        "add": ["0:9:12"]
      }
    }
  }
}
```

Each trace entry like `"0:15:9"` means **file index 0, line 15,
column 9**.  The `files` array maps indices to workspace-relative paths.

When the canonical (Namer-disambiguated) name of a signal differs from
its original `Logic.name`, an `origName` field is added:

```json
"8'h1": {
  "src": ["0:9:14"],
  "origName": "const_1"
}
```

### When to use source-only FLC

- Quick debugging — you only need the ROHD → Dart mapping.
- CI checks — verify that every signal has a known source location.
- Tools that consume only JSON (no SV files required).

---

## 2. SV-Enriched FLC (standalone JSON)

Adds the SystemVerilog line/column for each symbol, so the trace links
Dart source **and** the generated `.sv` file.

```dart
final sv  = SvService(mod);
final ts  = TraceService(mod, svService: sv);

// JSON for the whole hierarchy:
print(ts.flcJson);

// JSON for one module only:
print(ts.flcModuleJson('Inner'));
```

`TraceService` automatically collects `svLineMap` data from the
synthesis results, so there is nothing extra to wire up.

Output:

```json
{
  "version": 2,
  "files": ["lib/src/my_module.dart", "lib/src/modules/gates.dart"],
  "modules": {
    "Top": {
      "svFile": "Top.sv",
      "signals": {
        "a":  { "sv": "2:19", "src": ["0:15:9"] },
        "b":  { "sv": "3:20", "src": ["0:16:15"] }
      },
      "instances": {
        "inner": { "sv": "7:1", "src": ["0:6:20", "0:17:17"] }
      }
    },
    "Inner": {
      "svFile": "Inner.sv",
      "signals": {
        "a": { "sv": "2:19", "src": ["0:7:9"] },
        "b": { "sv": "3:20", "src": ["0:8:15"] }
      },
      "instances": {
        "add": { "sv": "9:1", "src": ["0:9:12"] }
      }
    }
  }
}
```

The `sv` field gives the **line:column** in the generated SV file named
by `svFile`.

### When to use SV-enriched FLC

- Feeding an external IDE or viewer that wants a sidecar JSON next to
  each `.sv` file.
- DevTools queries (via `TraceService.current?.flcJson`).

---

## 3. Multi-File Output (SV + FLC + HTML)

Write per-module `.sv` files, a hierarchy `.flc.json`, and an
interactive HTML viewer into a build directory:

```dart
final sv = SvService(mod);
final ts = TraceService(mod, svService: sv);

sv.writeFiles('build/output');       // Top.sv, Inner.sv, Add.sv
ts.writeFlcFiles('build/output');    // Top.flc.json  (hierarchy)
ts.writeFlcHtml('build/output');     // Top.flc.html  (viewer)
```

Resulting directory:

```text
build/output/
  Inner.sv
  Top.sv
  Top.flc.json       ← hierarchy FLC (all modules)
  Top.flc.html        ← self-contained HTML cross-probing viewer
```

The HTML file is fully self-contained (embedded CSS/JS) with:

- Searchable table of every signal and submodule instance
- Columns: Module, Symbol, Kind, SV Line, Source Locations
- Clickable `vscode://file/` links that open the Dart source in VS Code

### When to use multi-file output

- Handing off to design reviewers who want a browsable report.
- Archiving a build with full provenance alongside the RTL.

---

## 4. SV Inline Comments

When traces are active, the SystemVerilog synthesiser **automatically**
embeds `// ROHD:` comments on signal declarations and submodule
instantiations.  No extra API calls are required.

```dart
final sv = SvService(mod);
print(sv.allContents);     // or sv.writeFiles(dir)
```

Generated SV with inline comments:

```systemverilog
module Inner (
input logic [7:0] a,
output logic [7:0] b
);
// Source files:
//   0: lib/src/modules/gates.dart
//   1: lib/src/my_module.dart
logic _a_add_const_1_carry;    // ROHD: 0:581:5 1:9:12
assign {_a_add_const_1_carry, b} = a + 8'h1; // ROHD: ^
endmodule : Inner

module Top (
input logic [7:0] a,
output logic [7:0] b
);
// Source files:
//   0: lib/src/my_module.dart
Inner  inner_0(.a(a),.b(b));   // ROHD: 0:6:20 0:17:17
endmodule : Top
```

Each module begins with a `// Source files:` block mapping indices to
paths.  The `// ROHD:` suffix on a code line lists one or more
`fileIdx:line:col` references.

**Delta encoding** keeps comments compact:

- `^N` — the first N trace entries are identical to the previous line.
- `^` — the entire trace is identical to the previous line.
- `| frame` — a trailing join-frame shared with the preceding trace.

### When to use SV inline comments

- Browsing generated SV directly in an editor.
- Integrating with tools that parse SV comments (e.g. linters, custom
  scripts).
- The comments are **always present** when `SignalSourceTracer.hasTraces`
  is `true` — there is no flag to disable them separately.

---

## 5. Netlist Inline Attributes (`rohd.src_trace`)

When synthesising a Yosys-format netlist JSON, passing `packageRoot`
injects a `rohd.src_trace` attribute into each module entry:

```dart
final nl = await NetlistService.create(
    mod, packageRoot: Directory.current.path);
print(nl.toJson());   // full Yosys JSON with rohd.src_trace
```

Inside the Yosys JSON each module gains:

```json
"Inner": {
  "attributes": {
    "rohd.src_trace": {
      "files": ["lib/src/my_module.dart", "lib/src/modules/gates.dart"],
      "signals": {
        "a": ["0:7:9"],
        "b": ["0:8:15"],
        "_a_add_const_1_carry": ["1:581:5", "0:9:12"]
      },
      "instances": {
        "add": ["0:9:12"]
      }
    }
  }
}
```

This is the **compact per-module format** (same as Level 1, but scoped
to one module and embedded as a Yosys attribute).  Each module has its
own `files` array because the attribute is self-contained.

Standalone FLC sidecar generation is owned by `TraceService`. The
netlist path may still embed inline `rohd.src_trace` attributes for
netlist consumers, but DevTools/DTD FLC requests should be served by a
registered `TraceService`.

### When to use netlist inline attributes

- Feeding Yosys-based EDA tools that can read custom module attributes.
- Cross-probing in a netlist viewer (e.g. DevTools schematic panel).
- When you want both the netlist JSON **and** FLC in a single file.

---

## Summary Table

| Level | API | SV Lines? | Output | Use Case |
| ----- | --- | --------- | ------ | -------- |
| 1. Source-only | `SignalSourceTracer.traceJsonForHierarchy` | No | JSON map | Minimal; debugging / CI |
| 2. SV-enriched | `TraceService(mod, svService: sv)` | Yes | `.flcJson` / `.flcModuleJson` | Sidecar JSON for IDEs |
| 3. Multi-file | `sv.writeFiles` + `ts.writeFlcFiles/Html` | Yes | `.sv` + `.flc.json` + `.flc.html` | Build archives / review |
| 4. SV inline | `SvService(mod)` *(automatic)* | N/A | `// ROHD:` comments in `.sv` | Browsing SV directly |
| 5. Netlist inline | `NetlistService.create(mod, packageRoot:)` | No | `rohd.src_trace` in Yosys JSON | EDA tools / schematic viewers |

---

## FLC JSON Format Reference (v2)

```json
{
  "version": 2,
  "files": [ "<relative-path>", "..." ],    // shared file table
  "modules": {
    "<definitionName>": {
      "svFile": "<name>.sv",               // optional (Levels 2-3 only)
      "signals": {
        "<canonicalName>": {               // enriched form
          "sv":       "line:col",          // optional SV position
          "src":      ["fileIdx:line:col", ...],
          "origName": "<Logic.name>"       // present when canonical ≠ original
        },
        "<name>": ["fileIdx:line:col", ...]  // compact form (no SV)
      },
      "instances": {
        "<name>": ["fileIdx:line:col", ...]  // or enriched form with "sv"
      }
    }
  }
}
```

The compact form (bare array) and enriched form (object with `sv`/`src`)
can coexist in the same file — a signal without an SV mapping uses the
compact form while siblings with SV mappings use the enriched form.
