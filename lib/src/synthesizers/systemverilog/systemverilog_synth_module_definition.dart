// Copyright (C) 2021-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// systemverilog_synth_module_definition.dart
// Definition for SystemVerilogSynthModuleDefinition
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/systemverilog/systemverilog_synth_sub_module_instantiation.dart';
import 'package:rohd/src/synthesizers/utilities/utilities.dart';

/// A special [SynthModuleDefinition] for SystemVerilog modules.
class SystemVerilogSynthModuleDefinition extends SynthModuleDefinition {
  /// Creates a new [SystemVerilogSynthModuleDefinition] for the given [module].
  SystemVerilogSynthModuleDefinition(super.module);

  /// A shared mapping from [SynthLogic]s which are the result of an inlineable
  /// submodule to the instantiation that produces them.
  ///
  /// Populated by aggregate-collapse passes, then distributed alongside
  /// [_collapseMarkedChainableModules] so inline rendering (including
  /// recursive, multi-level chains) can resolve them.
  final Map<SynthLogic, SystemVerilogSynthSubModuleInstantiation>
      _inlineableSubmoduleMap = {};

  @override
  void process() {
    _collapseAggregateConnections();
    _collapseWholeNetBuses();
    _forwardPassthroughElementsIntoInlineables();
    _replaceNetConnections();
    _collapseMarkedChainableModules();
    _replaceInOutConnectionInlineableModules();
  }

  @override
  SynthSubModuleInstantiation createSubModuleInstantiation(Module m) =>
      SystemVerilogSynthSubModuleInstantiation(m);

  /// Creates a new [_NetConnect] module to synthesize assignment between two
  /// [LogicNet]s.
  SystemVerilogSynthSubModuleInstantiation _addNetConnect(
    SynthLogic dst,
    SynthLogic src,
  ) {
    // make an (unconnected) module representing the assignment
    final netConnect = _NetConnect(
      LogicNet(width: dst.width),
      LogicNet(width: src.width),
    );

    // instantiate the module within the definition
    final netConnectSynthSubModInst =
        (getSynthSubModuleInstantiation(netConnect)
            as SystemVerilogSynthSubModuleInstantiation)
          // map inouts to the appropriate `_SynthLogic`s
          ..setInOutMapping(_NetConnect.n0Name, dst)
          ..setInOutMapping(_NetConnect.n1Name, src);

    // notify the `SynthBuilder` that it needs declaration
    supportingModules.add(netConnect);

    netConnectSynthSubModInst.pickName(module);

    return netConnectSynthSubModInst;
  }

  /// Builds [_NetConnect] instances for [LogicNet] assignments.
  void _replaceNetConnections() {
    final reducedAssignments = <SynthAssignment>[];

    for (final assignment in assignments) {
      if (assignment.src.isNet && assignment.dst.isNet) {
        assert(
          assignment is! PartialSynthAssignment,
          'Net connections should not be partial assignments.',
        );

        _addNetConnect(assignment.dst, assignment.src);
      } else {
        reducedAssignments.add(assignment);
      }
    }

    // only swap them if we actually did anything
    if (assignments.length != reducedAssignments.length) {
      assignments
        ..clear()
        ..addAll(reducedAssignments);
    }
  }

  /// Collapses an internal aggregate signal (e.g. a [LogicArray]) whose
  /// individual elements are each connected one-to-one to some other signal,
  /// and which is itself used as a whole in exactly one place, by replacing
  /// that single aggregate use with an inlined concatenation ([Swizzle]) of the
  /// per-element sources.
  ///
  /// For example, a parent with individual nets `sig0..sigN` each connected to
  /// an element of an internal array `arr` that feeds a single child array port
  /// would otherwise emit one `net_connect` (or `assign`) per element plus a
  /// declaration of `arr`.  This collapses all of that into a single
  /// `.port({sigN, ..., sig0})` connection and drops `arr`.
  ///
  /// This works for both nets (bidirectional `inout` connections, where the
  /// concatenation is a legal net lvalue) and non-nets (a driven
  /// concatenation).
  void _collapseAggregateConnections() {
    // Loop until no further collapses occur: collapsing one aggregate can make
    // another eligible (e.g. chains of aggregates).  Each collapse strictly
    // removes work (clears an aggregate and its element assignments) and an
    // already-collapsed aggregate is no longer a candidate, so this terminates.
    var changed = true;
    while (changed) {
      changed = false;

      // Resolved view of every net [BusSubset], used to discover element
      // sources that are tied through a pass-through net bus rather than via a
      // direct assignment (see [_traceNetSubsetSource]).
      final netSubsets = _netSubsetLookups();

      // Count how many times each array [SynthLogic] is used "as a whole",
      // along with where (a submodule port mapping is the only use we can
      // currently inline into).
      final aggregateUseCount = <SynthLogic, int>{};
      final aggregatePortUse = <SynthLogic,
          ({
        SystemVerilogSynthSubModuleInstantiation instantiation,
        String portName,
      })>{};

      void noteWholeUse(SynthLogic? synthLogic) {
        if (synthLogic != null && synthLogic.isArray) {
          aggregateUseCount.update(synthLogic.resolved, (v) => v + 1,
              ifAbsent: () => 1);
        }
      }

      for (final instantiation in subModuleInstantiations) {
        instantiation as SystemVerilogSynthSubModuleInstantiation;
        for (final entry in instantiation.inputMapping.entries) {
          noteWholeUse(entry.value);
          if (entry.value.isArray) {
            aggregatePortUse[entry.value.resolved] =
                (instantiation: instantiation, portName: entry.key);
          }
        }
        for (final entry in instantiation.inOutMapping.entries) {
          noteWholeUse(entry.value);
          if (entry.value.isArray) {
            aggregatePortUse[entry.value.resolved] =
                (instantiation: instantiation, portName: entry.key);
          }
        }
        // outputs of submodules can't be replaced by an inline concatenation
        instantiation.outputMapping.values.forEach(noteWholeUse);
      }

      // Assignments and this-module ports also count as whole-aggregate uses
      // (and we cannot inline into those today, so they just disqualify).
      [...inputs, ...outputs, ...inOuts].forEach(noteWholeUse);
      for (final assignment in assignments) {
        noteWholeUse(assignment.src);
        noteWholeUse(assignment.dst);
      }

      // Map from each array element to the assignment(s) connecting it, and a
      // count of every place each array element is used (submodule port
      // mappings and assignments).  An element is only safe to inline if its
      // sole appearance is its single connecting assignment; if it is read
      // anywhere else (e.g. by a reduction), the aggregate must stay intact.
      final elementAssignments = <SynthLogic, List<SynthAssignment>>{};
      final elementUseCount = <SynthLogic, int>{};
      void noteElementUse(SynthLogic? synthLogic) {
        if (synthLogic is SynthLogicArrayElement) {
          elementUseCount.update(synthLogic.resolved, (v) => v + 1,
              ifAbsent: () => 1);
        }
      }

      for (final instantiation in subModuleInstantiations) {
        instantiation as SystemVerilogSynthSubModuleInstantiation;
        instantiation.inputMapping.values.forEach(noteElementUse);
        instantiation.outputMapping.values.forEach(noteElementUse);
        instantiation.inOutMapping.values.forEach(noteElementUse);
      }
      for (final assignment in assignments) {
        noteElementUse(assignment.src);
        noteElementUse(assignment.dst);
        for (final end in [assignment.src, assignment.dst]) {
          if (end is SynthLogicArrayElement) {
            elementAssignments
                .putIfAbsent(end.resolved, () => [])
                .add(assignment);
          }
        }
      }

      for (final aggEntry in aggregatePortUse.entries) {
        final agg = aggEntry.key;
        final use = aggEntry.value;

        // Restriction: exactly one whole-aggregate use, which is the port use
        // we found.  This single-use restriction mirrors the other collapsing
        // mechanisms; it could be relaxed later (e.g. duplicating the
        // concatenation into multiple consumers).
        if ((aggregateUseCount[agg] ?? 0) != 1) {
          continue;
        }

        // The aggregate must be a clearable internal signal: mergeable (so its
        // name carries no meaning to preserve) and not a port.  This mirrors
        // the conservatism of the other collapsing mechanisms: renameable or
        // reserved aggregates are left intact so their declared names survive.
        if (agg.declarationCleared ||
            !agg.isClearable ||
            agg.isPort(module) ||
            !internalSignals.contains(agg)) {
          continue;
        }

        // The consuming port must accept expressions.
        final consumer = use.instantiation.module;
        if (consumer is SystemVerilog &&
            consumer.expressionlessInputs.contains(use.portName)) {
          continue;
        }

        // Gather each element's single source (the other end of its single
        // connecting assignment), in element order (index 0 = LSB).
        final elementLogics = agg.logics
            .whereType<LogicArray>()
            .first
            .elements
            .map(getSynthLogic)
            .map((e) => e?.resolved)
            .toList();

        final elementSources = <SynthLogic>[];
        var allElementsSingleSourced = true;

        // Net [BusSubset]s consumed while tracing element sources through
        // pass-through buses; their instantiations are cleared and the buses
        // dropped only if the whole collapse succeeds.
        final tracedSubsets = <SystemVerilogSynthSubModuleInstantiation>{};
        final tracedBuses = <SynthLogic>{};

        for (final element in elementLogics) {
          if (element == null) {
            allElementsSingleSourced = false;
            break;
          }

          // Preferred path: the element is connected by exactly one assignment
          // and used nowhere else.
          final connectingAssignments = elementAssignments[element];
          if (connectingAssignments != null &&
              connectingAssignments.length == 1 &&
              (elementUseCount[element] ?? 0) == 1) {
            final assignment = connectingAssignments.single;
            final source = assignment.src.resolved == element
                ? assignment.dst.resolved
                : assignment.src.resolved;
            if (source == element) {
              allElementsSingleSourced = false;
              break;
            }
            elementSources.add(source);
            continue;
          }

          // Fallback (net) path: the element is the [subset] of a [BusSubset]
          // whose [original] is a pass-through bus, and the same bit of that
          // bus is tied to exactly one other net.  Trace through to that net so
          // the bus and its [BusSubset]s can be eliminated.
          final traced = _traceNetSubsetSource(
            element,
            netSubsets,
            elementUseCount,
            elementAssignments,
            tracedSubsets,
            tracedBuses,
          );
          if (traced == null) {
            allElementsSingleSourced = false;
            break;
          }
          elementSources.add(traced);
        }

        if (!allElementsSingleSourced || elementSources.isEmpty) {
          continue;
        }

        // A traced pass-through bus may only be dropped if it is fully consumed
        // by this collapse: every net [BusSubset] referencing it must have been
        // traced, and it must be a clearable/renameable internal non-port.
        if (!_tracedBusesFullyConsumed(
            tracedBuses, tracedSubsets, netSubsets)) {
          continue;
        }

        // Net aggregates can only collapse if their sources are also nets (the
        // concatenation is a net lvalue), and non-net likewise.
        if (elementSources.any((e) => e.isNet != agg.isNet)) {
          continue;
        }

        // If every source is an element of one common parent array (in any
        // order), the aggregate is just a re-arrangement of an existing array
        // and there is nothing to consolidate; passing that array (or letting
        // the other collapsing mechanisms merge it) yields cleaner output, so
        // leave it alone.  The value of this optimization is consolidating
        // otherwise-separate signals into a single concatenation.
        if (elementSources.every((e) => e is SynthLogicArrayElement)) {
          final parents = elementSources
              .map((e) => (e as SynthLogicArrayElement).parentArray.resolved)
              .toSet();
          if (parents.length == 1) {
            continue;
          }
        }

        // Fabricate a swizzle (post-build instrumentation, not connected to the
        // real hardware) whose concatenation reproduces the aggregate, and
        // register it so the single aggregate use renders as the inline
        // concatenation.
        _addSwizzleConnect(agg, elementSources);

        // Remove the now-inlined element assignments and clear the aggregate
        // declaration.
        final elementSet = elementLogics.nonNulls.toSet();
        assignments.removeWhere((assignment) =>
            elementSet.contains(assignment.src.resolved) ||
            elementSet.contains(assignment.dst.resolved));
        agg.clearDeclaration();
        internalSignals.remove(agg);

        // Drop any pass-through buses and clear the [BusSubset]s traced through
        // them.
        for (final subsetInst in tracedSubsets) {
          subsetInst.clearInstantiation();
        }
        for (final bus in tracedBuses) {
          bus.clearDeclaration();
          internalSignals.remove(bus);
        }

        changed = true;
      }
    }
  }

  /// Builds resolved lookups over every net [BusSubset] instantiation: a list
  /// of all views, plus maps keyed by the resolved `original` bus and the
  /// resolved `subset`.  Reversed slices (`start > end`) are skipped because
  /// they cannot be safely re-expressed as a simple concatenation here.
  ({
    Map<SynthLogic, List<_NetSubsetView>> byOriginal,
    Map<SynthLogic, List<_NetSubsetView>> bySubset,
  }) _netSubsetLookups() {
    final byOriginal = <SynthLogic, List<_NetSubsetView>>{};
    final bySubset = <SynthLogic, List<_NetSubsetView>>{};

    for (final instantiation in subModuleInstantiations) {
      instantiation as SystemVerilogSynthSubModuleInstantiation;
      final m = instantiation.module;
      if (m is! BusSubset || !m.original.isNet) {
        continue;
      }
      if (m.startIndex > m.endIndex) {
        // Reversed slice: skip conservatively.
        continue;
      }
      final original = instantiation.inOutMapping[m.original.name]?.resolved;
      final subset = instantiation.inOutMapping[m.subset.name]?.resolved;
      if (original == null || subset == null) {
        continue;
      }
      final view = (
        inst: instantiation,
        original: original,
        subset: subset,
        start: m.startIndex,
        end: m.endIndex,
      );
      byOriginal.putIfAbsent(original, () => []).add(view);
      bySubset.putIfAbsent(subset, () => []).add(view);
    }

    return (byOriginal: byOriginal, bySubset: bySubset);
  }

  /// Attempts to find the real source for array `element` when it is the
  /// `subset` of a single-bit net [BusSubset] off a pass-through bus.
  ///
  /// The shape handled (the "bit-wise" case) is: the bus bit `i` is sliced once
  /// to feed `element` (`bus[i] -> element`) and once more to tie to some other
  /// net (`bus[i] -> net`).  This traces `element` to that net, recording the
  /// consumed [BusSubset]s and bus so they can be dropped once the whole
  /// aggregate collapse is committed.
  ///
  /// Returns the resolved source net, or `null` if `element` does not match
  /// this shape.
  SynthLogic? _traceNetSubsetSource(
    SynthLogic element,
    ({
      Map<SynthLogic, List<_NetSubsetView>> byOriginal,
      Map<SynthLogic, List<_NetSubsetView>> bySubset,
    }) netSubsets,
    Map<SynthLogic, int> elementUseCount,
    Map<SynthLogic, List<SynthAssignment>> elementAssignments,
    Set<SystemVerilogSynthSubModuleInstantiation> tracedSubsets,
    Set<SynthLogic> tracedBuses,
  ) {
    // [element] must only be used as the subset side of a single BusSubset.
    final asSubset = netSubsets.bySubset[element];
    if (asSubset == null || asSubset.length != 1) {
      return null;
    }
    final elementView = asSubset.single;

    // Only single-bit slices are handled (one element per bus bit).
    if (elementView.start != elementView.end) {
      return null;
    }
    final bit = elementView.start;
    final bus = elementView.original;

    // The bus must be a clearable/renameable internal non-port pass-through.
    if (bus.declarationCleared ||
        !bus.isClearableOrRenameable ||
        bus.isPort(module) ||
        !internalSignals.contains(bus)) {
      return null;
    }

    // Find the sibling slice of the same bus bit that ties to another net.
    final siblings = (netSubsets.byOriginal[bus] ?? [])
        .where((v) => v.start == bit && v.end == bit && v.subset != element)
        .toList();
    if (siblings.length != 1) {
      return null;
    }
    final siblingView = siblings.single;
    final sourceNet = siblingView.subset;

    if (sourceNet == element) {
      return null;
    }

    tracedSubsets
      ..add(elementView.inst)
      ..add(siblingView.inst);
    tracedBuses.add(bus);

    return sourceNet;
  }

  /// Verifies that every pass-through bus in `tracedBuses` is fully consumed:
  /// every net [BusSubset] referencing it (as its `original`) was traced into
  /// `tracedSubsets`.  This ensures dropping the bus leaves no dangling
  /// references.
  bool _tracedBusesFullyConsumed(
    Set<SynthLogic> tracedBuses,
    Set<SystemVerilogSynthSubModuleInstantiation> tracedSubsets,
    ({
      Map<SynthLogic, List<_NetSubsetView>> byOriginal,
      Map<SynthLogic, List<_NetSubsetView>> bySubset,
    }) netSubsets,
  ) {
    for (final bus in tracedBuses) {
      final allViews = netSubsets.byOriginal[bus] ?? const [];
      for (final view in allViews) {
        if (!tracedSubsets.contains(view.inst)) {
          return false;
        }
      }
      // The bus must not be referenced as a *subset* of some other slice
      // (i.e. it must be a true root pass-through, not itself sliced into).
      if ((netSubsets.bySubset[bus] ?? const []).isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  /// Collapses a flat (non-array) internal net bus that is used as a whole in
  /// exactly one submodule port, and whose every bit is tied 1:1 to some other
  /// net via single-bit net [BusSubset]s, into an inline concatenation of those
  /// nets.
  ///
  /// This is the flat analogue of [_collapseAggregateConnections]: where that
  /// method handles arrays whose *elements* are individually connected, this
  /// handles a plain bus whose *bits* are individually tied (e.g. each bit
  /// driven to/from a separate net), and which is then passed whole to a child.
  /// It turns
  /// ```systemverilog
  ///   wire [7:0] bus;
  ///   net_connect (bus[0], a0); ... net_connect (bus[7], a7);
  ///   child c (.data(bus));
  /// ```
  /// into `child c (.data({a7, ..., a0}));`, dropping `bus` and all the
  /// `net_connect`s.
  void _collapseWholeNetBuses() {
    var changed = true;
    while (changed) {
      changed = false;

      final netSubsets = _netSubsetLookups();

      // Count whole uses of each candidate bus and remember the single
      // submodule port use we can inline into.  Uses as the [original] of a
      // [BusSubset] are definers, not whole uses, so they are excluded here.
      final wholeUseCount = <SynthLogic, int>{};
      final portUse = <SynthLogic,
          ({
        SystemVerilogSynthSubModuleInstantiation instantiation,
        String portName,
      })>{};

      final busOriginals = netSubsets.byOriginal.keys.toSet();

      void noteWholeUse(SynthLogic? synthLogic) {
        if (synthLogic == null) {
          return;
        }
        final resolved = synthLogic.resolved;
        if (busOriginals.contains(resolved)) {
          wholeUseCount.update(resolved, (v) => v + 1, ifAbsent: () => 1);
        }
      }

      for (final instantiation in subModuleInstantiations) {
        instantiation as SystemVerilogSynthSubModuleInstantiation;

        // A BusSubset reading this bus as `original` is a definer, not a
        // whole use; skip those mappings entirely.
        final isDefiner = instantiation.module is BusSubset;

        for (final entry in instantiation.inOutMapping.entries) {
          if (isDefiner) {
            continue;
          }
          noteWholeUse(entry.value);
          final resolved = entry.value.resolved;
          if (busOriginals.contains(resolved)) {
            portUse[resolved] =
                (instantiation: instantiation, portName: entry.key);
          }
        }
        // Nets only connect via inouts, but reads on input/output ports (or
        // outputs) would still count as disqualifying whole uses.
        if (!isDefiner) {
          instantiation.inputMapping.values.forEach(noteWholeUse);
          instantiation.outputMapping.values.forEach(noteWholeUse);
        }
      }

      // This-module ports and assignments are whole uses we cannot inline
      // into, so they disqualify the bus.
      [...inputs, ...outputs, ...inOuts].forEach(noteWholeUse);
      for (final assignment in assignments) {
        noteWholeUse(assignment.src);
        noteWholeUse(assignment.dst);
      }

      for (final busEntry in portUse.entries) {
        final bus = busEntry.key;
        final use = busEntry.value;

        // Exactly one whole use: the port use we found.
        if ((wholeUseCount[bus] ?? 0) != 1) {
          continue;
        }

        // The bus must be a clearable/renameable internal non-port net.
        if (bus.declarationCleared ||
            !bus.isNet ||
            bus.isArray ||
            !bus.isClearableOrRenameable ||
            bus.isPort(module) ||
            !internalSignals.contains(bus)) {
          continue;
        }

        // The bus must not itself be a subset of another bus.
        if ((netSubsets.bySubset[bus] ?? const []).isNotEmpty) {
          continue;
        }

        // The consuming port must accept expressions.
        final consumer = use.instantiation.module;
        if (consumer is SystemVerilog &&
            consumer.expressionlessInputs.contains(use.portName)) {
          continue;
        }

        // A whole-width use of a [Swizzle] is its concatenation *result*, which
        // already drives this bus; the per-bit subsets are then reads of the
        // bus (e.g. bit-blasting it onto an array port) rather than its
        // definers, so collapsing here would double-drive the bus and orphan
        // its real consumer.  Skip these.
        if (consumer is Swizzle) {
          continue;
        }

        // Every bit of the bus must be tiled exactly once by a single-bit
        // [BusSubset] definer, covering [0, width).
        final definers = netSubsets.byOriginal[bus]!;
        if (definers.any((v) => v.start != v.end)) {
          continue;
        }
        if (definers.length != bus.width) {
          continue;
        }
        final byBit = <int, _NetSubsetView>{};
        var tiledExactly = true;
        for (final view in definers) {
          if (byBit.containsKey(view.start)) {
            tiledExactly = false;
            break;
          }
          byBit[view.start] = view;
        }
        if (!tiledExactly) {
          continue;
        }
        for (var bit = 0; bit < bus.width; bit++) {
          if (!byBit.containsKey(bit)) {
            tiledExactly = false;
            break;
          }
        }
        if (!tiledExactly) {
          continue;
        }

        // Build the per-bit source nets, LSB-first.
        final elementSources = <SynthLogic>[
          for (var bit = 0; bit < bus.width; bit++) byBit[bit]!.subset,
        ];

        // The sources must all be nets (the concatenation is a net lvalue).
        if (elementSources.any((e) => !e.isNet)) {
          continue;
        }

        // Inline the bus as a concatenation of its per-bit nets and drop the
        // bus plus its definer [BusSubset]s.
        _addSwizzleConnect(bus, elementSources);

        for (final view in definers) {
          view.inst.clearInstantiation();
        }
        bus.clearDeclaration();
        internalSignals.remove(bus);

        changed = true;
      }
    }
  }

  /// Forwards the per-element sources of a pass-through [LogicArray] directly
  /// into the single inlineable submodule (e.g. a [Swizzle]) that consumes
  /// those elements, then drops the now-dead array.
  ///
  /// `assignSubset` (e.g. via `connectPorts`/`Logic.assignSubset`) introduces
  /// an intermediate net [LogicArray] (`*_subset`) whose elements are each tied
  /// by a single assignment to one external signal and then read
  /// element-by-element by an inlineable submodule.  Array elements never merge
  /// away (they carry positional `x`/`z` semantics), so without this pass each
  /// such element would materialize as its own `net_connect`.  When *every*
  /// element of the array is a pure pass-through, we rewire the consuming
  /// submodule's ports straight to the per-element sources and drop the
  /// intermediate array entirely, leaving a single inline concatenation.
  void _forwardPassthroughElementsIntoInlineables() {
    // Loop until no further forwarding occurs: forwarding one array can make
    // another eligible.  Each forward strictly removes work (an array and its
    // element assignments), so this terminates.
    var changed = true;
    while (changed) {
      changed = false;

      // Only instantiations that will actually render count as real uses: a
      // module that still needs instantiation, or a fabricated inlineable (e.g.
      // a [_SwizzleConnect] from an earlier collapse) registered in
      // [_inlineableSubmoduleMap].  Dead/consumed definers (e.g. a [BusSubset]
      // already cleared by [_collapseWholeNetBuses]) carry stale port mappings
      // that must NOT be mistaken for live uses.
      final activeInlineables = _inlineableSubmoduleMap.values.toSet();
      bool isActive(SystemVerilogSynthSubModuleInstantiation inst) =>
          inst.needsInstantiation || activeInlineables.contains(inst);

      final activeInstantiations = [
        for (final inst in subModuleInstantiations)
          if (isActive(inst as SystemVerilogSynthSubModuleInstantiation)) inst
      ];

      // Arrays used "as a whole" anywhere must keep their elements intact, so
      // their elements are not eligible for forwarding.
      final aggregateUsedArrays = <SynthLogic>{};
      void markIfAggregateArray(SynthLogic? synthLogic) {
        if (synthLogic != null && synthLogic.isArray) {
          aggregateUsedArrays.add(synthLogic.resolved);
        }
      }

      [...inputs, ...outputs, ...inOuts].forEach(markIfAggregateArray);
      for (final inst in activeInstantiations) {
        inst.inputMapping.values.forEach(markIfAggregateArray);
        inst.outputMapping.values.forEach(markIfAggregateArray);
        inst.inOutMapping.values.forEach(markIfAggregateArray);
      }
      for (final assignment in assignments) {
        markIfAggregateArray(assignment.src);
        markIfAggregateArray(assignment.dst);
      }

      // For each array element: the inlineable-submodule input/inout ports that
      // read it, the assignments connecting it, and whether it has any other
      // (disqualifying) use.
      final inlineablePortReads = <SynthLogic,
          List<
              ({
                SystemVerilogSynthSubModuleInstantiation instantiation,
                String portName,
                bool isInOut,
              })>>{};
      final elementAssignments = <SynthLogic, List<SynthAssignment>>{};
      final disqualified = <SynthLogic>{};

      void noteOtherUse(SynthLogic? s) {
        if (s is SynthLogicArrayElement) {
          disqualified.add(s.resolved);
        }
      }

      for (final inst in activeInstantiations) {
        final isInlineable = inst.module is InlineSystemVerilog;
        final resultLogic =
            isInlineable ? inst.inlineResultLogic?.resolved : null;

        void handleRead(String name, SynthLogic value,
            {required bool isInOut}) {
          if (value is! SynthLogicArrayElement) {
            return;
          }
          final resolved = value.resolved;
          // A read by an inlineable submodule input/inout port (but not its own
          // result) is the only "use" we can forward into; anything else
          // disqualifies the element.
          if (isInlineable && resolved != resultLogic) {
            inlineablePortReads
                .putIfAbsent(resolved, () => [])
                .add((instantiation: inst, portName: name, isInOut: isInOut));
          } else {
            noteOtherUse(value);
          }
        }

        inst.inputMapping.forEach((n, v) => handleRead(n, v, isInOut: false));
        inst.inOutMapping.forEach((n, v) => handleRead(n, v, isInOut: true));
        inst.outputMapping.values.forEach(noteOtherUse);
      }

      for (final assignment in assignments) {
        for (final end in [assignment.src, assignment.dst]) {
          if (end is SynthLogicArrayElement) {
            elementAssignments
                .putIfAbsent(end.resolved, () => [])
                .add(assignment);
          }
        }
      }

      // An element is a pure pass-through if it is read by exactly one
      // inlineable submodule port, connected by exactly one assignment to some
      // other signal, used nowhere else, and lives in a clearable internal
      // array that is not used as a whole.
      bool isPassThrough(SynthLogic element) {
        if (disqualified.contains(element)) {
          return false;
        }
        final reads = inlineablePortReads[element];
        final assigns = elementAssignments[element];
        if (reads == null || reads.length != 1) {
          return false;
        }
        if (assigns == null || assigns.length != 1) {
          return false;
        }
        final assignment = assigns.single;
        final partner = assignment.src.resolved == element
            ? assignment.dst
            : assignment.src;
        if (partner.resolved == element) {
          return false;
        }
        if (!element.isClearable) {
          return false;
        }
        final parentArray =
            (element as SynthLogicArrayElement).parentArray.resolved;
        if (aggregateUsedArrays.contains(parentArray)) {
          return false;
        }
        return true;
      }

      // Group candidate pass-through elements by parent array.
      final candidatesByArray = <SynthLogic, Set<SynthLogic>>{};
      for (final element in inlineablePortReads.keys) {
        if (isPassThrough(element)) {
          candidatesByArray
              .putIfAbsent(
                  (element as SynthLogicArrayElement).parentArray.resolved,
                  () => {})
              .add(element);
        }
      }

      // Only forward when EVERY element of an array is a pass-through, so the
      // whole array can be dropped.  Partial forwarding is unsafe: the array
      // would stay declared and its remaining (e.g. differently-driven or
      // undriven `x`/`z`) elements could change behavior.
      final droppedArrays = <SynthLogic>[];
      candidatesByArray.forEach((parentArray, arrayCandidates) {
        if (parentArray.declarationCleared ||
            !parentArray.isClearable ||
            parentArray.isPort(module) ||
            !internalSignals.contains(parentArray)) {
          return;
        }

        final allElements = parentArray.logics
            .whereType<LogicArray>()
            .expand((logicArray) => logicArray.elements)
            .map(getSynthLogic)
            .nonNulls
            .map((e) => e.resolved)
            .toSet();

        if (allElements.isEmpty ||
            !allElements.every(arrayCandidates.contains)) {
          return;
        }

        // Rewire each element's consuming port straight to the element's
        // source, and remove the now-redundant element assignment.
        final removedAssignments = <SynthAssignment>{};
        for (final element in arrayCandidates) {
          final read = inlineablePortReads[element]!.single;
          final assignment = elementAssignments[element]!.single;
          final partner = assignment.src.resolved == element
              ? assignment.dst
              : assignment.src;

          if (read.isInOut) {
            read.instantiation
                .setInOutMapping(read.portName, partner, replace: true);
          } else {
            read.instantiation
                .setInputMapping(read.portName, partner, replace: true);
          }

          removedAssignments.add(assignment);
          (element as SynthLogicArrayElement).clearDeclaration();
        }

        assignments.removeWhere(removedAssignments.contains);
        droppedArrays.add(parentArray);
        changed = true;
      });

      _dropEmptiedArrays(droppedArrays);
    }
  }

  /// Fabricates a [_SwizzleConnect] that represents [agg] as the inline
  /// concatenation of [elementSources] (ordered with index 0 as the LSB), and
  /// registers it in [_inlineableSubmoduleMap].
  void _addSwizzleConnect(SynthLogic agg, List<SynthLogic> elementSources) {
    final isNet = agg.isNet;

    // The [Swizzle] concatenates its `signals` with `signals[0]` as the MSB,
    // i.e. `out = {signals[0], signals[1], ..., signals[last]}`.  Our
    // [elementSources] are LSB-first (index 0 is the LSB), so we reverse them
    // to build the swizzle's MSB-first signal list.  Only the widths and order
    // of these dummy signals matter; they are throwaway placeholders since the
    // real sources are mapped onto the ports below.
    final dummySignals = <Logic>[
      for (final source in elementSources.reversed)
        isNet ? LogicNet(width: source.width) : Logic(width: source.width),
    ];

    final swizzle = _SwizzleConnect(dummySignals);

    final swizzleInst = getSynthSubModuleInstantiation(swizzle)
        as SystemVerilogSynthSubModuleInstantiation;

    // [orderedInputPortNames] are in creation order (`in0`, `in1`, ...), which
    // the [Swizzle] assigns to `signals.reversed`; i.e. `in0` is the LSB.  So
    // port `in${i}` corresponds to element `i` (LSB-first).
    for (var i = 0; i < elementSources.length; i++) {
      final portName = swizzle.orderedInputPortNames[i];
      final source = elementSources[i];
      if (isNet) {
        swizzleInst.setInOutMapping(portName, source);
      } else {
        swizzleInst.setInputMapping(portName, source);
      }
    }

    if (isNet) {
      swizzleInst.setInOutMapping(swizzle.resultSignalName, agg);
    } else {
      swizzleInst.setOutputMapping(swizzle.resultSignalName, agg);
    }

    swizzleInst.clearInstantiation();

    supportingModules.add(swizzle);

    _inlineableSubmoduleMap[agg] = swizzleInst;
  }

  /// Collapses chainable, inlineable modules after naming.
  void _collapseMarkedChainableModules() {
    // collapse multiple lines of in-line assignments into one where they are
    // unnamed one-liners
    //  for example, be capable of creating lines like:
    //      assign x = a & b & c & _d_and_e
    //      assign _d_and_e = d & e
    //      assign y = _d_and_e

    final synthLogicToInlineableSynthSubmoduleMap = {
      ..._inlineableSubmoduleMap,
    };
    final inlinedParentArrays = <SynthLogic>{};
    for (final subModuleInstantiation in chainableModulesToCollapse
        .cast<SystemVerilogSynthSubModuleInstantiation>()) {
      // inlineable modules have only 1 result signal
      final resultSynthLogic = subModuleInstantiation.inlineResultLogic!;

      // clear declaration of intermediate signal replaced by inline
      internalSignals.remove(resultSynthLogic);

      // when inlining an array element, its declaration comes from the parent
      // array, so clear it explicitly and remember the parent array so we can
      // (potentially) drop the whole array if all its elements are inlined
      if (resultSynthLogic is SynthLogicArrayElement) {
        resultSynthLogic.clearDeclaration();
        inlinedParentArrays.add(resultSynthLogic.parentArray.resolved);
      }

      // clear declaration of instantiation for inline module
      subModuleInstantiation.clearInstantiation();

      synthLogicToInlineableSynthSubmoduleMap[resultSynthLogic] =
          subModuleInstantiation;
    }

    // Drop any parent array whose elements have all been inlined away, so the
    // now-unused array declaration is not emitted.
    _dropEmptiedArrays(inlinedParentArrays);

    for (final subModuleInstantiation in subModuleInstantiations) {
      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      subModuleInstantiation.synthLogicToInlineableSynthSubmoduleMap = {
        ...?subModuleInstantiation.synthLogicToInlineableSynthSubmoduleMap,
        ...synthLogicToInlineableSynthSubmoduleMap,
      };
    }
  }

  /// Drops the declarations of any [LogicArray] (seeded from [emptiedArrays])
  /// whose elements have all been inlined or forwarded away.
  ///
  /// This considers the whole array hierarchy (collecting ancestors) so that,
  /// for multi-dimensional arrays, a parent array whose sub-arrays were all
  /// dropped is itself dropped.  A fixed-point loop is used since dropping one
  /// sub-array can make its parent droppable regardless of visitation order.
  void _dropEmptiedArrays(Iterable<SynthLogic> emptiedArrays) {
    final candidateParentArrays = <SynthLogic>{};
    final ancestorsToCollect = [...emptiedArrays];
    while (ancestorsToCollect.isNotEmpty) {
      final parentArray = ancestorsToCollect.removeLast().resolved;
      if (candidateParentArrays.add(parentArray) &&
          parentArray is SynthLogicArrayElement) {
        ancestorsToCollect.add(parentArray.parentArray);
      }
    }

    bool elementsAllAbsent(SynthLogic parentArray) =>
        parentArray.logics.every((logic) =>
            !(logic as LogicArray).elements.any(logicHasPresentSynthLogic));

    var droppedAny = true;
    while (droppedAny) {
      droppedAny = false;
      for (final parentArray in candidateParentArrays) {
        if (parentArray.declarationCleared ||
            !parentArray.isClearable ||
            parentArray.isPort(module) ||
            parentArray.isStructPortElement(module)) {
          continue;
        }

        if (elementsAllAbsent(parentArray)) {
          parentArray.clearDeclaration();
          internalSignals.remove(parentArray);
          droppedAny = true;
        }
      }
    }
  }

  /// Finds all [InlineSystemVerilog] modules where all ports are [LogicNet]s
  /// and which have not had their declarations cleared and replaces them with a
  /// [_NetConnect] assignment instead of a normal assignment.
  void _replaceInOutConnectionInlineableModules() {
    for (final subModuleInstantiation in subModuleInstantiations.toList().where(
          (e) =>
              e.module is InlineSystemVerilog &&
              e.needsInstantiation &&
              e.outputMapping.isEmpty &&
              e.inOutMapping.isNotEmpty,
        )) {
      // algorithm:
      // - mark module as not needing declaration
      // - add a net_connect
      // - update the net_connect's inlineablesynthsubmodulemap

      subModuleInstantiation as SystemVerilogSynthSubModuleInstantiation;

      subModuleInstantiation.clearInstantiation();

      final resultName = (subModuleInstantiation.module as InlineSystemVerilog)
          .resultSignalName;

      final subModResult = subModuleInstantiation.inOutMapping[resultName]!;

      // use a dummy as a placeholder, it will not really be used since we are
      // updating the inlineable map
      final dummy = SynthLogic(
        LogicNet(name: 'DUMMY', width: subModResult.width),
        parentSynthModuleDefinition: this,
      );

      final netConnectSynthSubmod = _addNetConnect(
        subModResult,
        dummy,
      )..synthLogicToInlineableSynthSubmoduleMap ??= {};

      netConnectSynthSubmod.synthLogicToInlineableSynthSubmoduleMap![dummy] =
          subModuleInstantiation;
    }
  }
}

/// A resolved view of a net [BusSubset] instantiation: the resolved `original`
/// and `subset` signals and the (non-reversed) `[start, end]` inclusive bit
/// range of the slice on the original bus.
typedef _NetSubsetView = ({
  SystemVerilogSynthSubModuleInstantiation inst,
  SynthLogic original,
  SynthLogic subset,
  int start,
  int end,
});

/// A special [Module] for connecting or assigning two SystemVerilog nets
/// together bidirectionally.
///
/// The `alias` keyword in SystemVerilog could alternatively work, but many
/// tools do not support it, so this `module` definition is a convenient trick
/// to accomplish the same thing in a tool-compatible way.
class _NetConnect extends Module with SystemVerilog {
  static const String _definitionName = 'net_connect';

  /// The width of the nets on this instance.
  final int width;

  @override
  bool get hasBuilt =>
      // we force it to say it has built since it is being generated post-build
      true;

  /// The name of net 0.
  static final String n0Name = Naming.unpreferredName('n0');

  /// The name of net 1.
  static final String n1Name = Naming.unpreferredName('n1');

  _NetConnect(LogicNet n0, LogicNet n1)
      : assert(n0.width == n1.width, 'Widths must be equal.'),
        width = n0.width,
        super(definitionName: _definitionName, name: _definitionName) {
    n0 = addInOut(n0Name, n0, width: width);
    n1 = addInOut(n1Name, n1, width: width);
  }

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    assert(
      instanceType == _definitionName,
      'Instance type selected should match the definition name.',
    );
    return '$instanceType'
        ' #(.WIDTH($width))'
        ' $instanceName'
        ' (${ports[n0Name]}, ${ports[n1Name]});';
  }

  @override
  String? definitionVerilog(String definitionType) => '''
// A special module for connecting two nets bidirectionally
module $definitionType #(parameter int WIDTH=1) (w, w);
inout wire[WIDTH-1:0] w;
endmodule''';
}

/// A [Swizzle] fabricated post-build purely as instrumentation for
/// SystemVerilog generation; it is never connected to the real hardware
/// hierarchy or used in simulation.
///
/// Used by [SystemVerilogSynthModuleDefinition._collapseAggregateConnections]
/// to render an aggregate's single use as an inline concatenation of its
/// per-element sources.
class _SwizzleConnect extends Swizzle {
  /// The names of the input ports, in the same order as the `signals` passed to
  /// the constructor.
  late final List<String> orderedInputPortNames;

  @override
  // forced since it is generated post-build
  bool get hasBuilt => true;

  _SwizzleConnect(super.signals) {
    orderedInputPortNames = (isNet ? inOuts.keys : inputs.keys)
        .where((name) => name != resultSignalName)
        .toList();
  }
}
