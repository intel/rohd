# rohd_hierarchy

An incremental design dictionary for hardware module hierarchies.

## Motivation

A remote agent — a debugger, a waveform viewer, a schematic renderer, an
AI assistant — needs to understand the structure of a hardware design in order
to ask useful questions about it. Transferring the full design every time is
wasteful. What both sides of a link really need is a shared **dictionary** of
the design: the modules, instances, ports, and signals that make it up, plus
a compact way to refer to any object by address.

Once both sides share the same dictionary, communication becomes cheap:
either side can request data about a specific object by its address alone,
without re-transmitting structural context.

### What is a design dictionary?

A design dictionary captures the **hierarchy and connectivity** of a
hardware design:

- **Modules** — the reusable definitions (e.g. `Counter`, `ALU`).
- **Instances** — placed copies of modules within a parent.
- **Ports** — directional signals on a module boundary (input, output, inout).
- **Signals** — internal wires and registers.

The full "unfolded" view of a design is its **address space**: every instance,
every port, every signal reachable by walking the hierarchy tree.

### Compact, canonical addressing

`rohd_hierarchy` assigns each object a **canonical address** — a short
sequence of child indices (e.g. `0.2.4`) that uniquely identifies it within
the tree.

Addresses are **relative within each module**: a module's address table
maps local indices to its children and signals without relying on any
global namespace. This locality property is what makes the dictionary
**incrementally expandable** — a remote agent can:

1. Request the top-level dictionary table (the root module's children and
   signals).
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

- **`HierarchyNode`** — A tree node representing a module or instance,
  with children, signals, name, kind, and a primitive flag. Call
  `buildAddresses()` to assign a canonical `HierarchyAddress` to every
  node and signal in O(n).
- **`HierarchyAddress`** — An immutable, index-based path through the
  tree (e.g. `[0, 2, 4]`). Supports conversion to/from dot-separated
  strings. Works as an O(1) cache key.
- **`Signal` / `Port`** — Signal metadata: name, width, type, direction,
  full path. `Port` extends `Signal` with a required direction.

### Services & adapters

- **`HierarchyService`** — A mixin providing tree-walking search and
  navigation: `searchSignals()`, `searchModules()`,
  `autocompletePaths()`, glob-star regex search, and address↔pathname
  conversion.
- **`BaseHierarchyAdapter`** — An abstract class wrapping a
  `HierarchyNode` tree with `HierarchyService`. Use
  `BaseHierarchyAdapter.fromTree()` to wrap an existing tree.
- **`NetlistHierarchyAdapter`** — A concrete adapter that parses Yosys
  JSON netlists into a `HierarchyNode` tree.

### Search controller

- **`HierarchySearchController<R>`** — A pure-Dart controller for
  keyboard-navigable search result lists, with `updateQuery()`,
  `selectNext()` / `selectPrevious()`, `tabComplete()`, and scroll-offset
  helpers. Factories `forSignals()` and `forModules()` cover the common
  cases.

## Usage

### Building a dictionary from a Yosys netlist

```dart
import 'package:rohd_hierarchy/rohd_hierarchy.dart';

final dict = NetlistHierarchyAdapter.fromJson(yosysJsonString);
final root = dict.root;  // the top-level dictionary table
```

### Wrapping an existing tree

When you already have a `HierarchyNode` tree (e.g. from a VCD parser, a
ROHD simulation, or any other source), wrap it to gain search and address
resolution:

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
final addr = dict.pathnameToAddress('Counter.clk');

// Send the compact address over the wire: "0.1"
final wire = addr!.toDotString();

// The other side resolves it back
final resolved = dict.nodeByAddress(HierarchyAddress.fromDotString(wire));
final pathname = dict.addressToPathname(addr!);
```

### Searching the dictionary

```dart
final signals = dict.searchSignals('clk');
final modules = dict.searchModules('counter');
final completions = dict.autocompletePaths('top.cpu.');
```

### Constructing nodes manually

```dart
final root = HierarchyNode(
  id: 'Counter',
  name: 'Counter',
  kind: HierarchyKind.module,
  type: 'Counter',
  signals: [
    Port(
      id: 'Counter.clk', name: 'clk', direction: 'input',
      width: 1, type: 'bin', fullPath: 'Counter.clk', scopeId: 'Counter',
    ),
    Port(
      id: 'Counter.count', name: 'count', direction: 'output',
      width: 8, type: 'bin', fullPath: 'Counter.count', scopeId: 'Counter',
    ),
  ],
  children: [
    HierarchyNode(
      id: 'Counter.adder', name: 'adder',
      kind: HierarchyKind.instance, type: 'Adder',
      signals: [], children: [],
    ),
  ],
);
```

### Enriching signals from another source

Signals from one source (e.g. a VCD file) can be upgraded with metadata
from the design dictionary:

```dart
final designSignal = dict.signalByAddress(addr);
if (designSignal is Port) {
  node.signals[i] = Port(
    id: vcdSignal.id, name: vcdSignal.name,
    type: vcdSignal.type, width: vcdSignal.width,
    direction: designSignal.direction!,
    fullPath: vcdSignal.fullPath, scopeId: vcdSignal.scopeId,
  );
}
```

## Design principles

| Principle | How it is achieved |
|---|---|
| **Source-agnostic** | The data model is independent of any HDL toolchain. `NetlistHierarchyAdapter` handles Yosys JSON; `BaseHierarchyAdapter.fromTree()` wraps any tree. |
| **Incremental** | Addresses are relative within each module. A remote agent expands only the subtrees it needs, one dictionary table at a time. |
| **Compact** | `HierarchyAddress` is a short index path (e.g. `0.2.4`), not a full dotted pathname. Both sides resolve it locally. |
| **Canonical** | `buildAddresses()` assigns deterministic indices in tree order. The same design always produces the same addresses. |
| **No global namespace** | Each module's address table is self-contained. Adding or removing a sibling subtree does not invalidate addresses in unrelated parts of the tree. |
| **Transport-independent** | The package defines the dictionary model, not the wire protocol. Any transport (VM service, JSON-RPC, gRPC, WebSocket) can carry the compact addresses. |
