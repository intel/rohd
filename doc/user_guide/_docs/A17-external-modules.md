---
title: "External Modules"
permalink: /docs/external-modules/
excerpt: "External Modules"
last_modified_at: 2022-12-06
toc: true
---

ROHD can instantiate external SystemVerilog modules.  The [`ExternalSystemVerilogModule`]({{ site.baseurl }}api/rohd/ExternalSystemVerilogModule-class.html) constructor requires the top level SystemVerilog module name.  When ROHD generates SystemVerilog for a model containing an `ExternalSystemVerilogModule`, it will instantiate instances of the specified `definitionName`.  This is useful for integration related activities.

The [ROHD Cosim](https://github.com/intel/rohd-cosim) package enables SystemVerilog cosimulation with ROHD by adding cosimulation capabilities to an `ExternalSystemVerilogModule`.
