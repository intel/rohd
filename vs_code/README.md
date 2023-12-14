# Visual Studio Code ROHD Snippets

This Visual Studio Code extension provides commonly used ROHD framework snippets, facilitating usage of auto-complete features.

## What's ROHD

ROHD (pronounced as "road") is a framework for describing and verifying hardware using the Dart programming language. For more information about ROHD, please visit [https://intel.github.io/rohd-website/](https://intel.github.io/rohd-website).

## Features

Currently, this extension follows the conventions in ROHD [v0.5.1](https://github.com/intel/rohd/releases/tag/v0.5.1). It suggests auto-completions when you start typing the prefixes as shown in the table below:

|  Name  |  Prefix  |  Description  |
|  :---:  |  :---:  |  :--:  |
|  ROHD Counter Example | `example`  | Generates an ROHD Counter Example |
|  Module  |  `module` or `mod` or `Mod` or `Module`  | Creates an ROHD Module Class |
|  Sequential Logic  |  `seq` or `sequential` or `Seq`  | Builds an ROHD Sequential Logic |
|  Combinational Logic  |  `comb`  | Constructs an ROHD Combinational Logic |
| Simple Assign (<=)  | `assign` | Demonstrates an example of the Assignment Operator used outside combinational or sequential contexts |
| Conditional Assign (<) | `assign` | Demonstrates an example of the Assignment Operator used within combinational or sequential contexts |
| If | `if` or `If` | Constructs an 'IF' conditional block for use within sequential or combinational contexts |
| Case | `case` or `Case` | Creates a 'CASE' conditional block for use within sequential or combinational contexts |
| CaseZ | `caseZ` or `CaseZ` | Builds a 'CASEZ' conditional block for use within sequential or combinational contexts |
| Simulation | `sim` or `Simulator` or `simulation` | Templates a signal Simulation |
| Finite State Machine  | `fsm` or `FSM` | Creates a Finite State Machine template example for simplified FSM usage |
| ROHD-VF Testbench | `vf` | Creates a ROHD-VF template |

## Reporting Issues

Issues on either ROHD or VSCode snippets should be filed in [https://github.com/intel/rohd/issues](https://github.com/intel/rohd/issues).
