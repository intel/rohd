---
name: rohd-hierarchy
description: "Use when building, adapting, navigating, or searching hardware design hierarchies with the rohd_hierarchy Dart package."
---

# Working with rohd_hierarchy

Use `rohd_hierarchy` to represent and navigate hardware design hierarchy
independently of the HDL source or transport that provides it.

## Workflow

1. Inspect the package API and the hierarchy source before choosing an adapter.
   Use `NetlistHierarchyAdapter.fromJson` for netlist JSON, or
   `BaseHierarchyAdapter.fromTree` when adapting an existing
   `HierarchyOccurrence` tree.
2. Model the unfolded design as module occurrences and signal occurrences.
   Include useful module `definition` names and signal widths, directions, and
   values when the source provides them.
3. Call `buildAddresses()` when constructing a tree directly. Addresses are
   canonical index paths within the hierarchy, not human-readable signal
   pathnames. Use `OccurrenceAddress.toDotString()` and
   `OccurrenceAddress.fromDotString()` when serializing addresses.
4. Use `HierarchyService` for pathname/address conversion and navigation.
   Treat `pathnameToAddress()` as nullable: a pathname may not exist.
5. Choose search semantics deliberately. Prefix queries are case-sensitive;
   regex queries support segment patterns and `**` for matching across
   hierarchy levels. Use the dedicated signal or occurrence search API.
6. Keep transport, waveform, schematic, and UI concerns outside the hierarchy
   model. The package provides the design dictionary and search/navigation
   primitives, not a wire protocol.

## Validation

- Add focused tests for tree shape, address assignment and round-tripping,
  pathname resolution, and the relevant search behavior.
- Prefer a small hierarchy fixture with readable names and distinct signal
  widths/directions.
- When adding an adapter, verify it preserves hierarchy and signal metadata
  and produces the same search/navigation results as a manually constructed
  tree.
