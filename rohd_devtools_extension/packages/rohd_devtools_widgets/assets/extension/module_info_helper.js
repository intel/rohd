// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_info_helper.js
// Shared helper for querying FLC module info via the rohd_extension commands.
//
// Used by both rohd-schematic-viewer (plain JS) and rohd-wave-viewer
// (TypeScript) VS Code extensions to resolve format availability for a module.
//
// 2026 May
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

const vscode = require('vscode');
const path = require('path');
const fs = require('fs');

/**
 * Resolve the `.flc.json` sidecar path for a given document URI.
 * Delegates to the `rohd.resolveFlcPath` command in rohd_extension.
 * Falls back to local convention if the command is unavailable.
 *
 * @param {import('vscode').Uri} documentUri
 * @param {import('vscode').OutputChannel} [output]
 * @returns {Promise<string|null>}
 */
async function resolveFlcPath(documentUri, output) {
  try {
    const result = await vscode.commands.executeCommand('rohd.resolveFlcPath', {
      documentFsPath: documentUri.fsPath,
    });
    return result ?? null;
  } catch (_) {
    // rohd_extension not installed - fall back to local convention.
    const fsPath = documentUri.fsPath;
    const dir = path.dirname(fsPath);
    const base = path.basename(fsPath);
    // .vcd/.fst/.ghw/.rohd.json -> .flc.json
    const flcName = base.replace(/\.(vcd|fst|ghw|rohd\.json)$/i, '.flc.json');
    if (flcName === base) return null;
    const flcPath = path.join(dir, flcName);
    return fs.existsSync(flcPath) ? flcPath : null;
  }
}

/**
 * Build a RohdModuleInfo-compatible JSON object for [moduleName].
 *
 * Delegates to the `rohd.queryModule` VS Code command provided by
 * rohd_extension, which owns all FLC parsing logic.
 *
 * @param {import('vscode').Uri} documentUri
 * @param {string|null} moduleName
 * @param {string[]|undefined} instancePath
 * @param {import('vscode').OutputChannel} [output]
 * @returns {Promise<object>} matching RohdModuleInfo.toJson() schema
 */
async function buildModuleInfo(documentUri, moduleName, instancePath, output) {
  const flcPath = await resolveFlcPath(documentUri, output);
  if (!flcPath) {
    return {
      extensionAvailable: true,
      module: moduleName,
      formats: {},
      error: 'No .flc.json sidecar found. Generate with TraceService.writeFlcFiles().',
      fstLoading: false,
    };
  }

  const queryModule = async module => {
    const payload = {
      flcPath,
      module,
    };
    if (instancePath && instancePath.length > 0) {
      payload.instancePath = instancePath;
    }
    return vscode.commands.executeCommand('rohd.queryModule', payload);
  };

  try {
    let info = await queryModule(moduleName);

    const hasFormats =
      info && typeof info === 'object' && Object.keys(info.formats ?? {}).length > 0;
    if (!hasFormats && instancePath && instancePath.length > 0) {
      const instanceName = [...instancePath]
        .reverse()
        .find(segment => typeof segment === 'string' && segment.length > 0);
      if (instanceName && instanceName !== moduleName) {
        if (output) {
          output.appendLine(
            '[moduleInfo] no formats for ' +
              String(moduleName ?? '') +
              '; retrying with instance name ' +
              instanceName,
          );
        }
        const fallbackInfo = await queryModule(instanceName);
        const fallbackHasFormats =
          fallbackInfo &&
          typeof fallbackInfo === 'object' &&
          Object.keys(fallbackInfo.formats ?? {}).length > 0;
        if (fallbackHasFormats) {
          info = fallbackInfo;
        }
      }
    }

    return info ?? {
      extensionAvailable: true,
      module: moduleName,
      formats: {},
      error: 'rohd.queryModule returned no result.',
      fstLoading: false,
    };
  } catch (e) {
    if (output) output.appendLine('[moduleInfo] rohd.queryModule failed: ' + e.message);
    return {
      extensionAvailable: true,
      module: moduleName,
      formats: {},
      error: 'Install the ROHD extension for source format detection.',
      fstLoading: false,
    };
  }
}

/**
 * Look up signal source frames via rohd_extension's `rohd.lookupSignal` command.
 *
 * @param {string} flcPath
 * @param {string|null} moduleName
 * @param {string} signalName
 * @param {string|undefined} format
 * @param {import('vscode').OutputChannel} [output]
 * @returns {Promise<Array>}
 */
async function lookupSignalFrames(flcPath, moduleName, signalName, format, output) {
  try {
    const frames = await vscode.commands.executeCommand('rohd.lookupSignal', {
      flcPath,
      module: moduleName,
      signal: signalName,
      format,
    });
    const typedFrames = frames ?? [];
    const filteredFrames = format
      ? typedFrames.filter(frame => (frame?.type ?? 'rohd') === format)
      : typedFrames;
    // Reverse to outermost-first order (the ROHD extension returns
    // innermost-first, matching raw stack-trace order).
    return filteredFrames.reverse();
  } catch (e) {
    if (output) output.appendLine('[crossProbe] rohd.lookupSignal failed: ' + e.message);
    return [];
  }
}

module.exports = { resolveFlcPath, buildModuleInfo, lookupSignalFrames };
