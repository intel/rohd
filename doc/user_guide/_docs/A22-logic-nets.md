---
title: "Logic Nets, In/Outs, and Tri-state Buffers"
permalink: /docs/logic-nets/
last_modified_at: 2024-6-3
toc: true
---

## Logic Nets

The `LogicNet` class is a type of `Logic` which supports multiple drivers and bidirectional signal propagation. If multiple drivers disagree on the signal value, then an `x` (contention) value will be generated on that signal. Therefore, typically only one driver on a set of connected `LogicNet`s should be non-floating. One should use [tri-state buffers](#tri-state-buffers) to control which driver is actively driving on a net. In general, usage of `LogicNet` can be used for places where external IO and analog driver behavior needs to be modelled.  For example, an external IO may support one data bus for both read and write directions, so the IOs on either side would use tristate drivers to control whether each is reading from or writing to that bus.

Assignments between `LogicNet`s use the same `<=` or `gets` API as normal `Logic`s, but it applies automatically in both directions.  Assignments from `LogicNet` to `Logic` will only apply in the direction of driving the `Logic`, and conversely, assignments from `Logic` to `LogicNet` will only apply in the direction of driving the `LogicNet`.

`LogicArray`s can also be nets by using the `LogicArray.net` constructor.  The `isNet` accessor provides information on any `Logic` (including `LogicArray`s) about whether the signal will behave like a net (supporting multiple drivers).

## In/Out Ports

`Module`s support `inOut` ports via `addInOut`, which return objects of type `LogicNet`.  There are also equivalent versions for `LogicArray`s.  The API for `inOut` is similar to that of `input` -- there's an internal version to be used within a module, and the external version used for outside of the module.

## Tri-state Buffers

A tri-state buffer allows a driver to consider driving one of three states: driving 1, driving 0, and not driving (Z).  This is useful for when you may want multiple things to drive the same net at different times.  The `TriStateBuffer` module provides this capability in ROHD.

## Example

The below example shows a `Module` with an `inOut` port that is conditionally driven using a `TriStateBuffer`.

```dart
class ModWithInout extends Module {
  /// A module which drives [toDrive] if [isDriver] is high onto [io], or
  /// else leaves [io] floating (undriven) for others to drive it.
  ModWithInout(Logic isDriver, Logic toDrive, LogicNet io)
      : super(name: 'modwithinout') {
    isDriver = addInput('isDriver', isDriver);
    toDrive = addInput('toDrive', toDrive, width: toDrive.width);
    io = addInOut('io', io, width: toDrive.width);

    io <= TriStateBuffer(toDrive, enable: isDriver).out;
  }
}
```
