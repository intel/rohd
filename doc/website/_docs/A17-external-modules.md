---
title: "External Modules"
permalink: /docs/external-modules/
excerpt: "External Modules"
last_modified_at: 2022-12-06T08:48:05-04:00
toc: true
---

ROHD can instantiate external SystemVerilog modules.  The [`ExternalSystemVerilogModule`](https://intel.github.io/rohd/rohd/ExternalSystemVerilogModule-class.html) constructor requires the top level SystemVerilog module name.  When ROHD generates SystemVerilog for a model containing an `ExternalSystemVerilogModule`, it will instantiate instances of the specified `definitionName`.  This is useful for integration related activities.

There is an upcoming package for SystemVerilog cosimulation with ROHD which adds cosimulation capabilities to an `ExternalSystemVerilogModule` planned for release soon.