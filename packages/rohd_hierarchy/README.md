# rohd_hierarchy

An incremental design dictionary for hardware module hierarchies.

## Motivation

A remote agent — a debugger, a waveform viewer, a schematic renderer, an
AI assistant — needs to understand the structure of a hardware design in order
to ask useful questions about it. Transferring the full design every time is
wasteful. What both sides of a link really need is a shared **dictionary** of
the design: the modules, occurrences, and signals that make it up, plus
a compact way to refer to any object by address.

Once both sides share the same dictionary, communication becomes cheap:
either side can request data about a specific object by its address alone,
without re-transmitting structural context.

### What is a design dictionary?

A design dictionary captures the **hierarchy and connectivity** of a
hardware design:

- **Occurrences** — unfolded instances of module definitions in the
  hierarchy tree. Each has a `name`, an optional `definition` (the
  module type), child occurrences, and signals.
- **Signals** — named wires within an occurrence. Each has a `name`,
  `width`, optional `direction` (input/output/inout), and optional
  `value`.

The full "unfolded" view of a design is its **address space**: every
occurrence and every signal reachable by walking the hierarchy tree.

### Compact, canonical addressing

`rohd_hierarchy` assigns each object a **canonical address** — a short
sequence of child indices (e.g. `0.2.4`) that uniquely identifies it within
the tree.

Addresses are **relative within each occurrence**: an occurrence's address
table maps local indices to its children and signals without relying on any
global namespace. This locality property is what makes the dictionary
**incrementally expandable** — a remote agent can:

1. Request the top-level dictionary table (the root occurrence's children
   and signals).
2. Drill into any child by requesting that child's dictionary table.
3. Continue expanding only the parts of the hierarchy it actually needs.

At each step, both sides agree on the addresses, so subsequent data
requests (waveform samples, signal values, schematic fragments) carry
only the compact address, not the full path or structural description.

## Package overview

`rohd_hierarchy` is a source-agnostic Dart package that implements this
dictionary model. It provides data models, search utilities, and adapter
interfaces that work independently of any particular HDL toolchain or
transport layer.

### Data models

- **`HierarchyOccurrence`** — An occurrence of a module definition in the
  unfolded hierarchy tree, with children, signals, name, an optional
  `definition` (module type), and a primitive flag. Call `buildAddresses()`
  to assign a canonical `OccurrenceAddress` to every occurrence and signal
  in O(n). Use `signalCount` and `computedSignalCount` for efficient
  subtree counts.
- **`OccurrenceAddress`** — An immutable, index-based path through the
  tree (e.g. `[0, 2, 4]`). Supports conversion to/from dot-separated
  strings. Works as an O(1) cache key.
- **`SignalOccurrence`** — Signal metadata: name, width, optional
  direction, and optional value. Signals with a `direction` serve as
  ports (input, output, inout).

### Services & adapters

- **`HierarchyService`** — A mixin providing tree-walking search and
  navigation: `searchSignals()`, `searchOccurrences()`,
  `autocompletePaths()`, regex/glob search (`searchSignalsRegex()`,
  `searchOccurrencesRegex()`), and address↔pathname conversion.
- **`BaseHierarchyAdapter`** — An abstract class wrapping a
  `HierarchyOccurrence` tree with `HierarchyService`. Use
  `BaseHierarchyAdapter.fromTree()` to wrap an existing tree.
- **`NetlistHierarchyAdapter`** — A concrete adapter that parses netlist
  JSON into a `HierarchyOccurrence` tree.

### Search queries

- **`HierarchyQuery`** — Abstract base class for pluggable search
  strategies. The matching logic is decoupled from tree traversal.
- **`PrefixQuery`** — Prefix-substring matching. Segments split on `/`
  or `.` are matched case-insensitively via `startsWith` (signals) or
  `contains` (occurrences). Created via `HierarchyQuery.prefix()`.
- **`RegexQuery`** — Regex/glob matching. Each segment is compiled as a
  regex. Supports `*` (any chars), `?` (one char), `**` (zero or more
  hierarchy levels), character classes (`[0-9]`), alternation
  (`(clk|reset)`), and quantifiers. Created via `HierarchyQuery.regex()`.

### Search controller

- **`HierarchySearchController<R>`** — A pure-Dart controller for
  keyboard-navigable search result lists, with `updateQuery()`,
  `selectNext()` / `selectPrevious()`, `tabComplete()`, and scroll-offset
  helpers. Factories `forSignals()` and `forOccurrences()` cover the
  common cases.

## Usage

### Building a dictionary from a netlist

```dart
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

final dict = NetlistHierarchyAdapter.fromJson(netlistJsonString);
final root = dict.root;  // the top-level dictionary table
```

### Wrapping an existing tree

When you already have a `HierarchyOccurrence` tree (e.g. from a VCD
parser, a ROHD simulation, or any other source), wrap it to gain search
and address resolution:

```dart
final dict = BaseHierarchyAdapter.fromTree(rootNode);
```

### Incremental expansion by a remote agent

A remote agent does not need the full tree up front. It can expand the
dictionary one level at a time:

```dart
// Agent receives the root table
final root = dict.root;

// Agent picks a child to expand (e.g. child 2)
final child = root.children[2];

// The child's own children and signals are its local dictionary table.
// The agent now knows addresses 2.0, 2.1, ... for that subtree.
```

### Compact address-based communication

Once both sides share the dictionary, data requests use addresses only:

```dart
// Resolve a human-readable pathname to a canonical address
final addr = dict.pathnameToAddress('Counter/clk');

// Send the compact address over the wire: "0.1"
final wire = addr!.toDotString();

// The other side resolves it back
final resolved = dict.occurrenceByAddress(OccurrenceAddress.fromDotString(wire));
final pathname = dict.addressToPathname(addr!);
```

### Searching the dictionary

#### Prefix search (default)

Segments are split on `/` or `.` and matched as case-insensitive
substrings:

```dart
// Find all signals whose path contains 'cpu' then 'clk'
final signals = dict.searchSignals('cpu/clk');

// Find occurrences containing 'counter'
final modules = dict.searchOccurrences('counter');

// Tab-completion for partial paths
final completions = dict.autocompletePaths('Top/CPU/');
```

#### Regex / glob search

Each segment is a regex anchored to the full name. Glob wildcards `*`
and `?` are auto-converted. Use `**` to match across hierarchy levels:

```dart
// All 'clk' signals anywhere in the design
final clocks = dict.searchSignalsRegex('Top/**/clk');

// Signals named d0–d15 in any regfile
final data = dict.searchSignalsRegex('Top/**/regfile/d[0-9]+');

// Either 'clk' or 'reset' anywhere
final resets = dict.searchSignalsRegex('Top/**/(clk|reset)');

// All cache channels ch0–ch2
final channels = dict.searchOccurrencesRegex('Top/mem_ctrl/ch[0-2]');

// Signals containing 'mux' in their name
final muxed = dict.searchSignalsRegex('Top/**/.*mux.*');

// All signals in a specific module
final all = dict.searchSignalsRegex('Top/CPU/ALU/*');
```

### Constructing occurrences manually

```dart
final root = HierarchyOccurrence(
  name: 'Counter',
  definition: 'Counter',
  signals: [
    SignalOccurrence(name: 'clk', width: 1, direction: 'input'),
    SignalOccurrence(name: 'count', width: 8, direction: 'output'),
  ],
  children: [
    HierarchyOccurrence(
      name: 'adder',
      definition: 'Adder',
      signals: [
        SignalOccurrence(name: 'a', width: 8),
        SignalOccurrence(name: 'b', width: 8),
        SignalOccurrence(name: 'sum', width: 8),
      ],
    ),
  ],
);

// Assign canonical addresses
root.buildAddresses();

// Now every occurrence and signal has an address
print(root.children.first.path());  // 'Counter/adder'
print(root.signals.first.path());   // 'Counter/clk'
```

## Design principles

| Principle                 | How it is achieved                                                                                                                                      |
|---------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Source-agnostic**       | The data model is independent of any HDL toolchain. `NetlistHierarchyAdapter` handles netlist JSON; `BaseHierarchyAdapter.fromTree()` wraps any tree.   |
| **Incremental**           | Addresses are relative within each occurrence. A remote agent expands only the subtrees it needs, one dictionary table at a time.                       |
| **Compact**               | `OccurrenceAddress` is a short index path (e.g. `0.2.4`), not a full dotted pathname. Both sides resolve it locally.                                    |
| **Canonical**             | `buildAddresses()` assigns deterministic indices in tree order. The same design always produces the same addresses.                                     |
| **No global namespace**   | Each occurrence's address table is self-contained. Adding or removing a sibling subtree does not invalidate addresses in unrelated parts of the tree.   |
| **Transport-independent** | The package defines the dictionary model, not the wire protocol. Any transport (VM service, JSON-RPC, gRPC, WebSocket) can carry the compact addresses. |
