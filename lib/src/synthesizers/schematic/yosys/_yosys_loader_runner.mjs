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
import { fileURLToPath } from 'url';

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error(JSON.stringify({success: false, error: 'missing json path'}));
    process.exit(2);
  }
  // Treat a single dash '-' as shorthand for stdin. Do not resolve it
  // into an absolute path because path.resolve('-') would produce a
  // filesystem path named '-' and break the stdin detection.
  const rawArg = args[0];
  const jsonPath = rawArg && rawArg !== '-' ? path.resolve(rawArg) : null;
  try {
    // Resolve paths relative to this file to allow a local `d3-yosys` directory
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);

    // Find repository root by searching upwards for pubspec.yaml, fallback to a parent heuristic.
    function findRepoRoot(startDir) {
      let dir = startDir;
      while (true) {
        if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) return dir;
        const parent = path.dirname(dir);
        if (parent === dir) return null;
        dir = parent;
      }
    }

    const repoRoot = findRepoRoot(__dirname) || path.resolve(__dirname, '../../../../..');

    // Prefer a local copy of d3-yosys located next to this loader (lib/.../yosys/d3-yosys).
    // This matches the repository layout where d3-yosys is nested under the loader folder.
    let yosysFn = null;
    try {
      const localRelative = path.join(__dirname, 'd3-yosys', 'src', 'yosys.js');
      if (fs.existsSync(localRelative)) {
        const mod = await import('file://' + localRelative);
        yosysFn = mod.yosys;
      }
    } catch (e) {
      // ignore and try other locations
    }

    // Next, try a d3-yosys directory at the repository root (legacy location).
    if (!yosysFn) {
      try {
        const localYosys = repoRoot ? path.join(repoRoot, 'd3-yosys', 'src', 'yosys.js') : null;
        if (localYosys && fs.existsSync(localYosys)) {
          const mod = await import('file://' + localYosys);
          yosysFn = mod.yosys;
        }
      } catch (e) {
        // ignore and fall back
      }
    }

    // Finally, try resolving from installed packages (node_modules) or package specifier.
    if (!yosysFn) {
      try {
        const yosysModulePath = path.resolve(new URL('d3-yosys/src/yosys.js', import.meta.url).pathname);
        const mod = await import('file://' + yosysModulePath);
        yosysFn = mod.yosys;
      } catch (e) {
        const mod = await import('d3-yosys/src/yosys.js');
        yosysFn = mod.yosys;
      }
    }

    let raw;
    if (!jsonPath || jsonPath === '-') {
      // Read JSON from stdin
      raw = await new Promise((resolve, reject) => {
        let data = '';
        process.stdin.setEncoding('utf8');
        process.stdin.on('data', chunk => data += chunk);
        process.stdin.on('end', () => resolve(data));
        process.stdin.on('error', err => reject(err));
      });
    } else {
      raw = fs.readFileSync(jsonPath, 'utf8');
    }
    const yosysJson = JSON.parse(raw);
    const out = yosysFn(yosysJson);
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
