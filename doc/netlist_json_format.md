# ROHD Netlist JSON Format

`NetlistSynthesizer` (`lib/src/synthesizers/netlist/netlist_synthesizer.dart`)
emits a Yosys-JSON-*compatible* netlist: any tool that reads standard Yosys
`write_json` output can load the structural parts of a ROHD netlist. On top
of that shared base, ROHD adds a small number of extension fields so that
richer, ROHD-specific information (struct/array typing, source
cross-probing, generated-vs-authored signals) survives the round trip to
JSON for tools like the schematic viewer.

This document lists every field ROHD's netlist JSON emits that is **not**
part of the standard Yosys JSON schema, what it means, and which schema
version introduced it.

## Versioning policy

```json
{
  "creator": "NetlistSynthesizer (rohd)",
  "version": "0.0.2",
  "files": ["lib/src/my_module.dart"],
  "modules": { "...": "..." }
}
```

- `creator` and `version` are only meaningful together: a consumer should
  only look for the ROHD extensions below when `creator` equals
  `"NetlistSynthesizer (rohd)"`.
- **The version is informational only.** It tells a consumer which
  ROHD-specific fields and conventions *might* be present so it can decide
  whether to light up optional capabilities (e.g. struct-aware rendering).
  A missing, unrecognized, or newer `version` must **not** block loading —
  plain, unbranded Yosys JSON (no `creator` at all) is just as valid an
  input and carries none of these extensions.
- `NetlistSchematicAdapter` (in `rohd-schematic-viewer`) follows this
  policy: it logs a diagnostic when the version is absent or unrecognized,
  but always attempts to load the netlist.
- `files` is only present when source tracing was enabled (see
  `rohd.src_trace` below); it is omitted entirely otherwise.

Current schema version: **`0.0.2`** (`NetlistSynthesizer.formatVersion`).
Everything below applies to this version; it will be extended (with a
version bump) rather than broken as new capabilities are added.

| Version | Change |
| --- | --- |
| `0.0.1` | Initial schema. `rohd.src_trace` (when present) embedded its own per-module `files` list. |
| `0.0.2` | `rohd.src_trace` no longer embeds a per-module `files` list. Instead, a single top-level `files` array is shared by every module's `rohd.src_trace` in the same netlist document (see below). |

## Module-level extensions (`modules.<name>.attributes`)

Yosys already defines module `attributes` as an open string-keyed map, so
ROHD's additions are just specific keys within it:

| Key | Value | Meaning |
| --- | --- | --- |
| `top` | `1` | Standard Yosys convention, set on the root module of the design. Not ROHD-specific, listed here for completeness. |
| `src` | `"generated"` | ROHD always sets the standard Yosys `src` attribute key, but — unlike Yosys frontends, which record a `file:line.col-line.col` source range — ROHD always uses the literal string `"generated"`. |
| `rohd.src_trace` | object (see below) | **ROHD-only, opt-in.** Present only when [`NetlistSynthesizerConfiguration.trace`] is `true` *and* a `SourceTracer` was active during `Module.build()`. See below — **this is not the FLC format.** |

### `rohd.src_trace` is a separate, simpler mechanism from FLC

Despite the name, `attributes.rohd.src_trace` is **not** the FLC
(File-Line-Column) format described in `doc/cross_probing.md`, and it is
**not** what `TraceService` / the DevTools schematic viewer's cross-probe
feature actually reads. The two are independent, opt-in mechanisms that
happen to record similar information:

| | `attributes.rohd.src_trace` (this doc) | Standalone FLC JSON (`doc/cross_probing.md`) |
| --- | --- | --- |
| Where it lives | Inline, inside the netlist JSON's own module `attributes` | A separate JSON document/response (`TraceService.flcJson` / `.flcModuleJson()`, or a sidecar `.flc.json` file) |
| Enabled by | `NetlistSynthesizerConfiguration(trace: true)` passed to `NetlistSynthesizer`/`NetlistService` | `TraceService` (independently of netlist synthesis) |
| Shape | Flat map, one frame per signal/instance | Trie-compacted, v5/v6 format, multiple frames + merged SV output positions per signal |
| Consumed by | The schematic viewer when no standalone FLC sidecar is available | `FlcService`/`FlcData` in the DevTools extension and schematic viewer |

The schematic viewer prefers a standalone FLC sidecar when one exists,
because it can also provide merged SystemVerilog locations. When no
sidecar is present, it uses `rohd.src_trace` as an embedded fallback for
ROHD Dart source navigation. This makes a traced netlist independently
cross-probable without requiring `TraceService` to write a separate file.
The embedded representation remains a lightweight alternative: it only
contains unmerged ROHD locations and cannot provide output-language
locations.

`rohd.src_trace` shape (per module, inside `modules.<name>.attributes`):

```json
{
  "signals": { "count": ["0:42:5"] },
  "instances": { "adder0": ["0:17:17"] }
}
```

- `signals` / `instances`: map of local name → `["fileIndex:line:col", ...]`
  frame list. Only the constructor's own call site is recorded (a single
  frame) — there is no stack, no SV-position merging, and no trie
  compaction, unlike the standalone FLC format.
- **`fileIndex` resolves against the netlist-wide top-level `files` array**
  (see the top-level example above) — *not* a per-module list. There is
  no separate file dictionary inside `rohd.src_trace` itself; every
  module's frames share the one `files` array at the root of the netlist
  document.

### Resolving a `rohd.src_trace` frame to a source location

Given a netlist document `doc` (already `jsonDecode`d) and a frame string
like `"0:42:5"` found under
`doc["modules"]["FilterChannel"]["attributes"]["rohd.src_trace"]["signals"]["count"]`:

1. Split the frame on `:` → `[fileIndex, line, column?]`.
2. Look up the file path with `doc["files"][fileIndex]` — **the top-level
   array, not anything inside `rohd.src_trace`.**
3. `line` (and `column`, if present) are 1-based positions inside that
   file, relative to whatever `packageRoot` was passed to synthesis.

```dart
final files = (doc['files'] as List).cast<String>();
final trace = moduleAttrs['rohd.src_trace'] as Map<String, dynamic>;
final frame = (trace['signals']['count'] as List).first as String;
final parts = frame.split(':');
final file = files[int.parse(parts[0])];
final line = int.parse(parts[1]);
final column = parts.length > 2 ? int.parse(parts[2]) : null;
```

If you only have a single module's JSON in isolation (e.g. from
`NetlistService.moduleJson()` or the DevTools schematic viewer's
incremental per-module fetch), that standalone document also carries its
own top-level `files` array — re-embedded from the same shared dictionary
— so frame indices remain resolvable without needing the full combined
netlist. The same applies to `NetlistService.slimJson`, which nests it
under `netlist.files` alongside `netlist.modules`.

## Port and netname extensions: `logic_type`

Standard Yosys ports/netnames only carry a flat bit width (implicitly, the
length of their `bits` array). ROHD signals can be richer than a flat bus —
`LogicArray` and `LogicStructure` — so both
`modules.<name>.ports.<portName>` and `modules.<name>.netnames.<name>` gain
an optional **ROHD-only** `logic_type` key describing that shape:

- Plain `Logic`: `{"width": N}`
- `LogicArray`: `{"width": N, "arrayDims": [...], "elementWidth": M, "elementType": {...}?}`
  — `elementType` is present (and recurses) only when array elements are
  themselves `LogicStructure` or nested `LogicArray`.
- `LogicStructure`: `{"typeName": "ClassName", "fields": [...]}` where each
  field is `{"name": ..., "width": ..., "bits": [...]?}` for a leaf field,
  or `{"name": ..., "type": {...}, "bits": [...]?}` for a nested structure/
  array field. Fields are listed LSB-to-MSB (matching `rswizzle` /
  `elements[0]` = lowest bits). The per-field `bits` key (a slice of the
  parent's bit-ID list) is only included when the caller supplied bit IDs,
  which lets a consumer identify which wire IDs belong to which field even
  when the signal is only partially connected.

Netnames additionally reuse the standard `attributes` map for one
ROHD-only marker:

| Key | Value | Meaning |
| --- | --- | --- |
| `attributes.computed` | `1` | **ROHD-only.** Marks a netname as generated/inserted infrastructure (constant drivers, `InlineSystemVerilog` internals) rather than a name the user gave a signal directly, so viewers can visually de-emphasize it. |

## Cell-level extensions

ROHD maps most hardware constructs onto standard Yosys internal cell types
(`$buf`, `$const`, `$mux`, `$or`, `$dff`, `$dffe`, `$adffe`, `$aldffe`,
`$sdffe`, `$slice`, `$concat`, ...) using their normal Yosys parameter names
(`WIDTH`, `A_WIDTH`, `B_WIDTH`, `Y_WIDTH`, `CLK_POLARITY`, `EN_POLARITY`,
`OFFSET`, etc.) — those are not ROHD extensions.

Two cell **types** are ROHD-only and have no Yosys equivalent:

### `$struct_unpack`

Splits a single input bus `A` into one output port per named field,
modeling read access to a ROHD `LogicStructure`'s fields.

```json
{
  "hide_name": 0,
  "type": "$struct_unpack",
  "parameters": {
    "STRUCT_NAME": "sample",
    "FIELD_COUNT": 2,
    "FIELD_0_NAME": "data",
    "FIELD_0_OFFSET": 0,
    "FIELD_0_WIDTH": 16,
    "FIELD_1_NAME": "valid",
    "FIELD_1_OFFSET": 16,
    "FIELD_1_WIDTH": 1
  },
  "attributes": {},
  "port_directions": { "A": "input", "data": "output", "valid": "output" },
  "connections": { "A": [...], "data": [...], "valid": [...] }
}
```

### `$struct_pack`

The inverse: combines one input port per named field into a single output
bus `Y`, modeling construction of a `LogicStructure` from its fields. Uses
the same `STRUCT_NAME` / `FIELD_COUNT` / `FIELD_<i>_NAME` /
`FIELD_<i>_OFFSET` / `FIELD_<i>_WIDTH` parameters as `$struct_unpack`, but
with `port_directions` reversed (fields are `input`, `Y` is `output`).

Both cell types exist purely so the schematic viewer can render struct
pack/unpack as a first-class node with named field ports, instead of an
anonymous bundle of bit-slice/concat operators. A consumer that does not
understand these two types can still treat them as opaque black-box cells
using their `port_directions`/`connections`, exactly like any other
unrecognized cell type — nothing about them requires special-case parsing
to preserve netlist connectivity.

## Summary table

| Field | Location | Introduced | Standard Yosys? | Part of the FLC pipeline? |
| --- | --- | --- | --- | --- |
| `version` | top-level | 0.0.1 | No | n/a |
| `files` | top-level | 0.0.2 | No | **No** — shared dictionary for `rohd.src_trace` frames only; unrelated to FLC's own `files` array |
| `attributes.rohd.src_trace` | module | 0.0.1 (per-module `files` removed, resolves against top-level `files` in 0.0.2) | No | **No** — separate, opt-in, not read by `TraceService`/schematic viewer |
| `attributes.src = "generated"` | module | 0.0.1 | Key is standard; this value convention is not | n/a |
| `logic_type` | port, netname | 0.0.1 | No | n/a |
| `attributes.computed` | netname | 0.0.1 | No | n/a |
| `$struct_unpack` cell type | cell | 0.0.1 | No | n/a |
| `$struct_pack` cell type | cell | 0.0.1 | No | n/a |
