// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// _yosys_loader_runner.mjs
// Javascript program for loading yosys JSON files in D3 ELK format.
//
// Usage: node _yosys_loader_runner.mjs path/to/yosys.json
//
// 2025 December 12
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import fs from 'fs';
import path from 'path';

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error(JSON.stringify({success: false, error: 'missing json path'}));
    process.exit(2);
  }
  const jsonPath = path.resolve(args[0]);
  try {
    const yosysModulePath = path.resolve(new URL('d3-yosys/src/yosys.js', import.meta.url).pathname);
    const { yosys } = await import('file://' + yosysModulePath);
    const raw = fs.readFileSync(jsonPath, 'utf8');
    const yosysJson = JSON.parse(raw);
    const out = yosys(yosysJson);
    const topChild = out.children && out.children[0] ? out.children[0] : null;
    const res = {
      success: true,
      rootChildren: out.children ? out.children.length : 0,
      topNodeId: topChild ? topChild.id : null,
      topNodePorts: topChild ? (topChild.ports ? topChild.ports.length : 0) : null
    };
    console.log(JSON.stringify(res));
    process.exit(0);
  } catch (e) {
    const err = {success: false, error: String(e), stack: e && e.stack ? e.stack : null};
    console.error(JSON.stringify(err));
    process.exit(2);
  }
}

main();
