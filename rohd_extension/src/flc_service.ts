/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * flc_service.ts
 * Centralised FLC (File-Location Cache) service for rohd_extension.
 *
 * Owns:
 *  - Resolving the .flc.json sidecar path from any document path
 *  - Querying available source formats (rohd, sv, …) for a module
 *  - Looking up signal/instance source frames from v5/v6 FLC JSON
 *
 * All FLC parsing logic that was previously duplicated across
 * rohd-schematic-viewer/extension.js and rohd-wave-viewer/extension.ts
 * now lives here.  Those extensions delegate via VS Code commands:
 *   rohd.queryModule  – returns ModuleInfo
 *   rohd.lookupSignal – returns SourceFrame[]
 *
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 * --------------------------------------------------------------------------- */

import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

const output = vscode.window.createOutputChannel('ROHD FLC');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface FormatInfo {
  available: boolean;
  fileFound: boolean;
  path: string | null;
}

export interface ModuleFormats {
  rohd?: FormatInfo;
  sv?: FormatInfo;
  [key: string]: FormatInfo | undefined;
}

export interface ModuleInfo {
  extensionAvailable: boolean;
  module: string | null;
  formats: ModuleFormats;
  error?: string;
  fstLoading: boolean;
}

export interface SourceFrame {
  file: string;
  line: number;
  col: number;
  desc?: string;
  type: string;
}

interface FlcOutputPos {
  type: string;
  line: number;
  col: number;
}

interface FlcSymbolInfo {
  name: string;
  isInstance: boolean;
  outputPositions: FlcOutputPos[];
  origName: string | null;
}

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

let _extensionPath: string | undefined;

/** Must be called from extension activate() before any other API. */
export function initialize(extensionPath: string): void {
  _extensionPath = extensionPath;
  output.appendLine('[FlcService] Initialised. extensionPath=' + extensionPath);
}

// ---------------------------------------------------------------------------
// Sidecar resolution
// ---------------------------------------------------------------------------

/**
 * Resolve the .flc.json sidecar for any document path.
 *
 * Conventions supported:
 *   Foo.rohd.json  →  Foo.flc.json  (schematic viewer)
 *   Foo.vcd        →  Foo.flc.json  (wave viewer)
 *   Foo.fst        →  Foo.flc.json
 *   Foo.ghw        →  Foo.flc.json
 *
 * Returns the absolute path if the sidecar exists, otherwise null.
 */
export function resolveFlcPath(documentFsPath: string): string | null {
  const dir = path.dirname(documentFsPath);
  const base = path.basename(documentFsPath);

  // .rohd.json → .flc.json
  const fromRohdJson = base.replace(/\.rohd\.json$/i, '.flc.json');
  if (fromRohdJson !== base) {
    const p = path.join(dir, fromRohdJson);
    return fs.existsSync(p) ? p : null;
  }

  // .vcd / .fst / .ghw → .flc.json
  const fromWave = base.replace(/\.(vcd|fst|ghw)$/i, '.flc.json');
  if (fromWave !== base) {
    const p = path.join(dir, fromWave);
    return fs.existsSync(p) ? p : null;
  }

  return null;
}

// ---------------------------------------------------------------------------
// Module format query
// ---------------------------------------------------------------------------

/**
 * Return which source formats are available for [moduleName] in [flcPath].
 *
 * Reads and parses the FLC JSON directly (no subprocess needed for metadata).
 * Performs case-insensitive module name matching.
 */
export function queryModule(flcPath: string, moduleName: string | null): ModuleInfo {
  if (!fs.existsSync(flcPath)) {
    return {
      extensionAvailable: true,
      module: moduleName,
      formats: {},
      error: 'FLC file not found: ' + flcPath,
      fstLoading: false,
    };
  }

  try {
    const raw = fs.readFileSync(flcPath, 'utf8');
    const flcJson = JSON.parse(raw) as Record<string, unknown>;
    const modules = (flcJson['modules'] ?? {}) as Record<string, unknown>;
    const docDir = path.dirname(flcPath);

    // `files` entries (ROHD Dart sources) are stored relative to the package
    // root (e.g. `.dart_tool/../lib/src/...`), NOT relative to the directory
    // that holds the `.flc.json` (which is typically a `build/` output dir).
    // Resolve against `packageRoot` when present, then fall back to `docDir`.
    const packageRoot =
      typeof flcJson['packageRoot'] === 'string'
        ? (flcJson['packageRoot'] as string)
        : null;
    const resolveSourcePath = (relPath: string): string => {
      const bases = packageRoot ? [packageRoot, docDir] : [docDir];
      for (const base of bases) {
        const candidate = path.resolve(base, relPath);
        if (fs.existsSync(candidate)) {
          return candidate;
        }
      }
      // None existed — return the best-guess canonical path (packageRoot-based
      // when available) so the reported path is meaningful.
      return path.resolve(bases[0], relPath);
    };

    // Accept exact match or case-insensitive prefix match.
    let modData: Record<string, unknown> | null = null;
    if (moduleName && modules[moduleName]) {
      modData = modules[moduleName] as Record<string, unknown>;
    } else if (moduleName) {
      const lc = moduleName.toLowerCase();
      for (const [k, v] of Object.entries(modules)) {
        if (k.toLowerCase() === lc || k.toLowerCase().startsWith(lc + '_')) {
          modData = v as Record<string, unknown>;
          break;
        }
      }
    }

    const formats: ModuleFormats = {};

    if (modData) {
      // ROHD Dart source: trie tree non-empty + at least one global .dart file.
      const tree = modData['tree'];
      const hasRohdTree = Array.isArray(tree) && tree.length > 0;
      const globalFiles = (flcJson['files'] ?? []) as string[];
      const hasRohd = hasRohdTree && globalFiles.length > 0;

      if (hasRohd) {
        const rohdFile = globalFiles.find(f => f.endsWith('.dart'));
        const rohdPath = rohdFile ? resolveSourcePath(rohdFile) : null;
        formats['rohd'] = {
          available: true,
          fileFound: rohdPath ? fs.existsSync(rohdPath) : false,
          path: rohdPath,
        };
      }

      // Output-language files (sv, sc, …) from outputFiles map.
      // v6: Record<string, string[]> (list per language).
      // v5 legacy: Record<string, string>.
      const rawOutputFiles =
        (modData['outputFiles'] ?? {}) as Record<string, unknown>;
      const outputFiles: Record<string, string> = {};
      for (const [lang, val] of Object.entries(rawOutputFiles)) {
        if (Array.isArray(val)) {
          if (val.length > 0 && typeof val[0] === 'string') {
            outputFiles[lang] = val[0] as string;
          }
        } else if (typeof val === 'string') {
          outputFiles[lang] = val;
        }
      }
      // Legacy single svFile field.
      if (!outputFiles['sv'] && modData['svFile']) {
        outputFiles['sv'] = modData['svFile'] as string;
      }
      for (const [lang, relPath] of Object.entries(outputFiles)) {
        const absPath = path.resolve(docDir, relPath);
        formats[lang] = {
          available: true,
          fileFound: fs.existsSync(absPath),
          path: absPath,
        };
      }
    } else {
      output.appendLine(
        '[FlcService] queryModule: "' + moduleName +
        '" not found. Available: ' + Object.keys(modules).slice(0, 10).join(', '),
      );
    }

    return {
      extensionAvailable: true,
      module: moduleName,
      formats,
      fstLoading: false,
    };
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    output.appendLine('[FlcService] queryModule error: ' + msg);
    return {
      extensionAvailable: true,
      module: moduleName,
      formats: {},
      error: 'Error reading FLC: ' + msg,
      fstLoading: false,
    };
  }
}

// ---------------------------------------------------------------------------
// Signal lookup
// ---------------------------------------------------------------------------

/**
 * Look up source frames for [signalName] in [moduleName].
 *
 * When [format] is provided, only frames of that type ('rohd', 'sv', 'sc', ...)
 * are returned. Pass null/undefined to return all formats.
 */
export function lookupSignal(
  flcPath: string,
  moduleName: string | null,
  signalName: string,
  format?: string,
): SourceFrame[] {
  if (!fs.existsSync(flcPath)) {
    output.appendLine('[FlcService] lookupSignal: FLC not found: ' + flcPath);
    return [];
  }

  output.appendLine(
    '[FlcService] lookupSignal: ' + flcPath +
    ' module=' + (moduleName ?? '(any)') +
    ' signal=' + signalName +
    ' format=' + (format ?? 'all'),
  );

  try {
    const raw = fs.readFileSync(flcPath, 'utf8');
    const flcJson = JSON.parse(raw) as Record<string, unknown>;
    const frames = lookupSignalInJson(flcJson, path.dirname(flcPath), moduleName, signalName);
    const filtered = format ? frames.filter(f => f.type === format) : frames;
    output.appendLine(
      '[FlcService] lookupSignal: ' + filtered.length + ' frame(s)' +
      (format ? ' after ' + format + ' filter' : ''),
    );
    if (filtered.length === 0 && frames.length > 0 && format) {
      output.appendLine(
        '[FlcService] lookupSignal: available frame types=' +
        Array.from(new Set(frames.map(f => f.type))).join(', '),
      );
    }
    return filtered;
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    output.appendLine('[FlcService] lookupSignal failed: ' + msg);
    return [];
  }
}

function lookupSignalInJson(
  flcJson: Record<string, unknown>,
  flcDir: string,
  moduleName: string | null,
  signalName: string,
): SourceFrame[] {
  const modules = asRecord(flcJson['modules']);
  if (!modules) { return []; }

  const moduleNames = moduleName ? matchingModuleNames(modules, moduleName) : Object.keys(modules);
  for (const modName of moduleNames) {
    const modData = asRecord(modules[modName]);
    if (!modData) { continue; }
    const frames = lookupSignalInModule(flcJson, flcDir, modData, signalName);
    if (frames.length > 0) {
      return frames;
    }
  }

  if (moduleName) {
    output.appendLine(
      '[FlcService] lookupSignal: no match for ' + moduleName + '/' + signalName +
      '. Available modules: ' + Object.keys(modules).slice(0, 10).join(', '),
    );
  }
  return [];
}

function lookupSignalInModule(
  flcJson: Record<string, unknown>,
  flcDir: string,
  modData: Record<string, unknown>,
  signalName: string,
): SourceFrame[] {
  const tree = modData['tree'];
  if (!Array.isArray(tree)) { return []; }

  const files = Array.isArray(flcJson['files'])
    ? (flcJson['files'] as unknown[]).filter((f): f is string => typeof f === 'string')
    : [];
  const outputFiles = getOutputFiles(modData);

  let origNameMatch: SourceFrame[] = [];

  const walkNode = (node: unknown[], pathFrames: string[]): SourceFrame[] => {
    if (node.length === 0 || typeof node[0] !== 'string') { return []; }
    const currentPath = [...pathFrames, node[0] as string];

    for (let i = 1; i < node.length; i++) {
      const elem = node[i];
      if (Array.isArray(elem)) {
        const found = walkNode(elem, currentPath);
        if (found.length > 0) { return found; }
      } else if (typeof elem === 'string') {
        const parsed = parseSymbolString(elem);
        const frames = entryToFrames(parsed, currentPath, files, outputFiles, flcDir, signalName);
        if (parsed.name === signalName) {
          return frames;
        }
        if (parsed.origName === signalName && origNameMatch.length === 0) {
          origNameMatch = frames;
        }
      }
    }

    return [];
  };

  for (const rootNode of tree) {
    if (!Array.isArray(rootNode)) { continue; }
    const found = walkNode(rootNode, []);
    if (found.length > 0) { return found; }
  }
  return origNameMatch;
}

function entryToFrames(
  symbol: FlcSymbolInfo,
  pathFrames: string[],
  files: string[],
  outputFiles: Record<string, string>,
  flcDir: string,
  signalName: string,
): SourceFrame[] {
  const frames: SourceFrame[] = [];

  for (const frame of [...pathFrames].reverse()) {
    const parts = frame.split(':');
    if (parts.length < 2) { continue; }
    const fileIndex = Number.parseInt(parts[0], 10);
    if (!Number.isInteger(fileIndex) || fileIndex < 0 || fileIndex >= files.length) { continue; }
    frames.push({
      file: files[fileIndex],
      line: Number.parseInt(parts[1], 10) || 1,
      col: parts.length > 2 ? (Number.parseInt(parts[2], 10) || 1) : 1,
      desc: signalName + ' [ROHD]',
      type: 'rohd',
    });
  }

  for (const pos of symbol.outputPositions) {
    const outputFile = outputFiles[pos.type];
    if (!outputFile) { continue; }
    frames.push({
      file: path.resolve(flcDir, outputFile),
      line: pos.line,
      col: pos.col,
      desc: signalName + ' [' + pos.type.toUpperCase() + ']',
      type: pos.type,
    });
  }

  return frames;
}

function getOutputFiles(modData: Record<string, unknown>): Record<string, string> {
  const outputFiles: Record<string, string> = {};
  const svFile = modData['svFile'];
  if (typeof svFile === 'string') {
    outputFiles['sv'] = svFile;
  }

  const rawOutputFiles = asRecord(modData['outputFiles']);
  if (!rawOutputFiles) { return outputFiles; }

  for (const [lang, val] of Object.entries(rawOutputFiles)) {
    if (typeof val === 'string') {
      outputFiles[lang] = val;
    } else if (Array.isArray(val)) {
      const first = val.find((item): item is string => typeof item === 'string');
      if (first) {
        outputFiles[lang] = first;
      }
    }
  }
  return outputFiles;
}

function parseSymbolString(symbol: string): FlcSymbolInfo {
  const isInstance = symbol.startsWith('*');
  let rest = isInstance ? symbol.substring(1) : symbol;

  let origName: string | null = null;
  const tildeIdx = rest.indexOf('~');
  if (tildeIdx >= 0) {
    origName = rest.substring(tildeIdx + 1);
    rest = rest.substring(0, tildeIdx);
  }

  const outputPositions: FlcOutputPos[] = [];
  const atIdx = rest.indexOf('@');
  if (atIdx >= 0) {
    const positions = rest.substring(atIdx + 1);
    rest = rest.substring(0, atIdx);
    outputPositions.push(...parseOutputPositions(positions));
  }

  return { name: rest, isInstance, outputPositions, origName };
}

function parseOutputPositions(positions: string): FlcOutputPos[] {
  const result: FlcOutputPos[] = [];
  for (const group of positions.split(';')) {
    if (!group) { continue; }
    const entries = group.split(',');
    let groupLang: string | null = null;
    for (let i = 0; i < entries.length; i++) {
      let part = entries[i];
      if (!part) { continue; }
      if (i === 0) {
        const segments = part.split(':');
        const firstIsTag = segments.length >= 3 && Number.isNaN(Number.parseInt(segments[0], 10));
        if (firstIsTag) {
          groupLang = segments[0];
          part = segments.slice(1).join(':');
        }
      }
      const type = groupLang ?? 'sv';
      const segments = part.split(':');
      const lineText = segments.length >= 2 ? segments[segments.length - 2] : segments[0];
      const colText = segments.length >= 2 ? segments[segments.length - 1] : undefined;
      result.push({
        type,
        line: Number.parseInt(lineText, 10) || 1,
        col: colText ? (Number.parseInt(colText, 10) || 1) : 1,
      });
    }
  }
  return result;
}

function matchingModuleNames(modules: Record<string, unknown>, moduleName: string): string[] {
  if (Object.prototype.hasOwnProperty.call(modules, moduleName)) {
    return [moduleName];
  }

  const lower = moduleName.toLowerCase();
  const matches = Object.keys(modules).filter((name) => {
    const candidate = name.toLowerCase();
    return candidate === lower || candidate.startsWith(lower + '_');
  });
  return matches;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}
