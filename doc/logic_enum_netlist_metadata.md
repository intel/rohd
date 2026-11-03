# LogicEnum JSON Netlist Metadata

## Purpose

This note defines the proposed JSON-netlist work needed after `LogicEnum<T
extends Enum>` from #599 is merged.

The JSON netlist must always preserve hardware behavior as packed bits. The
proposal adds optional metadata so ROHD-aware tools can also preserve the
source-level enum domain, member names, and explicit encodings.

## Current behavior and gap

An enum member can lower to a mapped packed constant, so a generic netlist can
represent its hardware value correctly. For example, a member mapped to
`2'b10` remains two constant bits with that value.

That is not enough for source-aware consumers. Without additional metadata,
the netlist cannot distinguish:

```text
2'b10
```

from:

```text
Mode.execute, where Mode.execute is encoded as 2'b10
```

The SystemVerilog backend can emit enum typedefs and symbolic values, but the
JSON netlist backend currently has no equivalent enum-definition or
enum-reference serialization.

## Design principles

1. `LogicEnum` remains a driveable signal, not a `Const` subtype.
2. Enum member literals continue to lower to ordinary packed constant bits.
3. Metadata supplements bit-accurate netlist output; it must not change
   ordinary netlist semantics or require generic netlist consumers to
   understand enums.
4. Metadata is emitted only for typed ports and retained named nets, not every
   anonymous temporary signal.
5. Explicit conversion to packed `Logic` erases enum-domain metadata.
6. Incompatible enum mappings must never acquire equivalence solely from
   matching width.

## Proposed representation

Declare enum definitions once per generated module in module attributes:

```json
{
  "attributes": {
    "rohd_enum_definitions": {
      "Mode": {
        "width": 2,
        "members": {
          "idle": "00",
          "execute": "10",
          "halt": "11"
        }
      }
    }
  }
}
```

Reference the definition from typed ports and retained named nets:

```json
{
  "ports": {
    "state": {
      "direction": "input",
      "bits": [1, 2],
      "attributes": {
        "rohd_enum": "Mode"
      }
    }
  },
  "netnames": {
    "next_state": {
      "bits": [3, 4],
      "attributes": {
        "rohd_enum": "Mode"
      }
    }
  }
}
```

The exact attribute spelling may change, but the schema must be stable,
versioned, and documented. Member encodings should use an unambiguous
most-significant-bit-first binary representation with no implied ordinal
meaning.

## Synthesis integration

The shared synthesis model should carry an optional enum-domain descriptor
containing:

- enum definition identity;
- width;
- member-to-encoding mapping;
- preferred/reserved definition-name policy; and
- compatibility identity based on Dart enum type and exact mapping.

The netlist translator should consume that descriptor when emitting:

- module-level enum definitions;
- input, output, and inout port attributes;
- retained named internal net attributes; and
- hierarchy boundary metadata where the child and parent domains remain
  compatible.

Constant folding must continue to emit raw bit constants. A named enum signal
driven by a legal enum constant may retain its enum attribute; a standalone
constant has no independent enum domain.

## Configuration and versioning

Add a configuration option similar to:

```dart
const NetlistSynthesizerConfiguration(
  preserveEnumMetadata: true,
);
```

When disabled, the generated netlist must omit all enum metadata while
preserving exactly the same ports, cells, wire IDs, and packed constant bits.

Adding this schema requires a `NetlistSynthesizer.formatVersion` update and
documentation describing compatibility expectations for consumers.

## Validation

Extend netlist validation to check:

- each enum reference names a definition in its module;
- referenced width matches the associated port or net width;
- member names are unique and valid identifiers for the metadata schema;
- member encodings have the declared width and are unique;
- disabled metadata emits no enum references; and
- aliases and hierarchy transformations do not leave dangling references.

## Required tests

| Scenario | Required assertion |
| --- | --- |
| Enum input and output | Raw bit IDs remain correct and both port attributes reference the expected definition. |
| Named internal enum net | Retained net has the expected enum attribute. |
| Sparse mapping | Metadata preserves non-ordinal member encodings exactly. |
| Enum constant assignment | Netlist retains raw constant bits; the typed destination retains its enum metadata. |
| FSM | State ports/nets retain their mapping, including reset-state encoding. |
| Hierarchy | Compatible enum domains remain annotated across a parent/child boundary. |
| Type mismatch | Incompatible mapping/type connections fail before netlist emission or are explicitly lowered through a packed boundary. |
| Packed conversion | An explicit `Logic` conversion drops enum metadata. |
| Disabled metadata | No enum metadata is emitted and packed netlist behavior is unchanged. |
| Validation | Malformed or dangling enum attributes are rejected. |

Tests should compare both parsed JSON structure and behaviorally relevant bit
connections. They should not rely only on pretty-printed JSON strings.

## Non-goals

- Emitting SystemVerilog typedef syntax in JSON netlists.
- Making a `LogicEnum` signal a constant object.
- Attaching domain metadata to anonymous temporary expressions.
- Treating a whole `LogicStructure`, such as a floating-point value, as an
  enum. Structured literals and codecs are a separate abstraction.

## Acceptance criteria

The work is complete when a ROHD-aware netlist consumer can recover the enum
domain and exact member encodings for retained enum signals, while a generic
consumer can ignore the metadata and still consume a correct packed-bit
netlist.
