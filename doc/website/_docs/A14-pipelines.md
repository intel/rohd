---
title: "Pipelines"
permalink: /docs/pipelines/
excerpt: "Pipelines"
last_modified_at: 2022-12-06
toc: true
---

### Pipelines

ROHD has a built-in syntax for handling pipelines in a simple & refactorable way.  The below example shows a three-stage pipeline which adds 1 three times.  Note that [`Pipeline`]({{ site.baseurl }}api/rohd/Pipeline-class.html) consumes a clock and a list of stages, which are each a `List<Conditional> Function(PipelineStageInfo p)`, where `PipelineStageInfo` has information on the value of a given signal in that stage.  The `List<Conditional>` the same type of procedural code that can be placed in `Combinational`.

```dart
Logic a;
var pipeline = Pipeline(clk,
  stages: [
    (p) => [
      // the first time `get` is called, `a` is automatically pipelined
      p.get(a) < p.get(a) + 1
    ],
    (p) => [
      p.get(a) < p.get(a) + 1
    ],
    (p) => [
      p.get(a) < p.get(a) + 1
    ],
  ]
);
var b = pipeline.get(a); // the output of the pipeline
```

This pipeline is very easy to refactor.  If we wanted to merge the last two stages, we could simply rewrite it as:

```dart
Logic a;
var pipeline = Pipeline(clk,
  stages: [
    (p) => [
      p.get(a) < p.get(a) + 1
    ],
    (p) => [
      p.get(a) < p.get(a) + 1,
      p.get(a) < p.get(a) + 1
    ],
  ]
);
var b = pipeline.get(a);
```

You can also optionally add stalls and reset values for signals in the pipeline.  Any signal not accessed via the `PipelineStageInfo` object is just accessed as normal, so other logic can optionally sit outside of the pipeline object.

ROHD also includes a version of `Pipeline` that supports a ready/valid protocol called [`ReadyValidPipeline`]({{ site.baseurl }}api/rohd/ReadyValidPipeline-class.html).  The syntax looks the same, but has some additional parameters for readys and valids.
