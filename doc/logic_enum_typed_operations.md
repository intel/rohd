# LogicEnum Integration with Generic Typed Operations

## Purpose

This note records the work required in #704 after `LogicEnum<T extends Enum>`
from #599 is merged and rebased onto the current codebase.

The goal is to make `LogicEnum<T>` a first-class scalar domain type for the
existing generic operation APIs. This work must extend `mux`, `flop`, `cases`,
selection, and passthrough rather than introducing parallel typed-operation
APIs.

## Preconditions

Before implementing this work:

1. Rebase #599 onto current `main`.
2. Preserve the existing `LogicEnum<T>` mapping, clone, assignment, case, FSM,
   and SystemVerilog contracts.
3. Keep the generic operation APIs introduced by #704 as the only public
   operation spellings.

## Domain and literal contract

`LogicEnum<T>` is a driveable domain signal, not a `Const` subtype.

- A `LogicEnum<T>` clone must retain its Dart enum type, mapping, width,
  `definitionName`, and definition-name reservation policy while creating a
  driveable signal.
- A Dart enum member is a domain literal only in the context of a
  `LogicEnum<T>` mapping. It must never silently mean the member ordinal.
- `getsEnum`, `put`, `inject`, and conditional assignment map a member through
  the receiving enum's explicit mapping.
- A packed `Const` may drive an enum only when its exact value is represented
  in the enum mapping.
- Raw packed `Logic` may cross into an enum domain under the enum's existing
  runtime validation policy. It is an explicit bit-level boundary.
- Requesting `<Logic>` is the explicit domain-erasure path for an operation
  result.

These rules match the existing distinction between a literal source and a
driveable operation output.

## Operation behavior

### Mux

`mux<T>` and `Mux<T>` must infer `LogicEnum<T>` from enum operands.

- The default result schema is `d0`, including its mapping and configuration.
- An output generator can intentionally select another compatible enum schema.
- Inputs with different Dart enum types or incompatible mappings must be
  rejected rather than reinterpreted by width.
- A constant control without an output generator returns the selected source by
  identity.
- A supplied output generator is invoked once and materializes a fresh,
  driveable result even for a constant control.
- `mux<Logic>` deliberately drops enum-domain information and operates on
  packed bits.

### Flop

`flop<T>` and `FlipFlop<T>` must preserve `LogicEnum<T>`.

- The default result schema is `d`.
- A reset by enum member must use the output mapping.
- A packed reset constant is legal only when its encoding belongs to the
  output mapping.
- An unmapped reset value must fail with a mapping-specific diagnostic.
- A reset signal with a compatible enum domain must preserve that domain across
  the register boundary.
- `flop<Logic>` is the explicit packed, driveable normalization path.

### Cases

`cases<T>` must distinguish enum selector literals from enum result literals.

- An enum expression may use members of its mapping as case keys.
- Keys not present in the expression mapping must be rejected.
- A bare enum member cannot be a result value because it has no independent
  output mapping.
- Result values must be enum signals, or callers must supply an enum output
  generator.
- The default result prototype remains the first typed branch unless an output
  generator is supplied.
- Mixed packed and enum result branches require an explicit output schema.

### Selection and passthrough

`selectFrom`, `selectIndex`, and `Passthrough` must preserve concrete
`LogicEnum<T>` types and their mappings for homogeneous inputs. Explicit
`Logic` output requests intentionally erase the domain.

## Required test matrix

Add real `LogicEnum` coverage to `test/typed_operations_test.dart`; the
existing scalar-domain test double is not sufficient proof of enum behavior.

| Surface | Required coverage |
| --- | --- |
| Clone and naming | Static type, mapping, width, definition name, reserved definition name, and driveability survive `cloneTyped` and `namedTyped`. |
| Mux | Inferred type, `d0` schema, output generator, constant-control identity, generator materialization, sparse mappings, mapping mismatch rejection, and `<Logic>` erasure. |
| Flop | Inferred type, enable, synchronous/asynchronous reset, enum-member reset, legal packed reset, rejected unmapped reset, and `<Logic>` normalization. |
| Cases | Enum expression/member keys, typed result signals, rejected bare result members, default behavior, mixed packed/domain branches, and output generators. |
| Selection | `selectFrom` and `selectIndex` retain enum type and reject incompatible mappings. |
| Passthrough | Default schema preservation and explicit output generator behavior. |
| Arrays | `LogicArrayOf<LogicEnum<T>>` works through the relevant operations and preserves its element builder and dimensions. |
| Structures | Structures with enum leaves work through mux, flop, cases, selection, and module hierarchy. |
| Backends | ROHD functional simulation, SystemVerilog with enums enabled and disabled, Icarus, and Verilator agree. |

Every synthesized scenario should have a representative nested-composition
test, not only a root-module test.

## FSM coverage

`FiniteStateMachine<T extends Enum>` is a primary user of `LogicEnum`.

Add or retain tests for:

- reset to an enum state;
- legal transitions and default transitions;
- sparse and non-ordinal mappings;
- direct enum-member case labels;
- typed current and next state access;
- generated SystemVerilog enum typedefs and symbolic state members; and
- functional and external-simulator agreement.

Constraining FSM state identifiers to `Enum` is a breaking API change and
needs a release migration note.

## Structures and structured literals

`LogicEnum` should support enum leaves in a `LogicStructure`, but it should
not become a general structured-value abstraction.

A type such as `FloatingPoint` should remain a `LogicStructure` with a
separate literal/codec API, for example `FloatingPoint.one()` or
`FloatingPoint.fromDouble(1.0)`. Such a literal may use constant leaves, but
its `clone()` must construct driveable leaves so generic operations can create
a driveable output while retaining the `FloatingPoint` static type.

This follows the existing structured-constant operation contract and keeps
finite scalar enum domains distinct from arbitrary structured encodings.

## Acceptance criteria

The work is complete when:

1. No parallel typed operation API is introduced.
2. Enum type and mapping information is retained by every applicable generic
   operation unless the caller explicitly requests `Logic`.
3. Invalid mappings and unmapped literals fail explicitly.
4. The test matrix above passes in ROHD simulation and emitted-SystemVerilog
   simulation.
5. The migration and domain-erasure rules are documented for users.
