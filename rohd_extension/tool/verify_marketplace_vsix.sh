#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "Usage: $0 <marketplace-vsix-path>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

readonly VSIX="$1"
if [[ ! -f "$VSIX" ]]; then
  echo "error: VSIX not found: $VSIX" >&2
  exit 2
fi

for executable in node unzip; do
  if ! command -v "$executable" >/dev/null; then
    echo "error: Required command not found: $executable" >&2
    exit 2
  fi
done

node - "$ROOT/pubspec.yaml" "$ROOT/package.json" "$VSIX" <<'NODE'
const {execFileSync} = require('node:child_process');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');

const [pubspecPath, sourceManifestPath, vsixPath] = process.argv.slice(2);
const pubspec = readFileSync(resolve(pubspecPath), 'utf8');
const sourceManifest = JSON.parse(readFileSync(resolve(sourceManifestPath), 'utf8'));
const pubspecVersion = pubspec.match(/^version:\s*([^\s#]+)/m)?.[1];

function archiveFile(entry) {
  return execFileSync('unzip', ['-p', vsixPath, entry]);
}

const entries = new Set(
  execFileSync('unzip', ['-Z1', vsixPath], {encoding: 'utf8'})
    .trim()
    .split('\n')
    .filter(Boolean),
);
const packageManifest = JSON.parse(
  archiveFile('extension/package.json').toString('utf8'),
);

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function requireEntry(entry) {
  if (!entries.has(entry)) {
    fail(`VSIX is missing required entry: ${entry}`);
  }
}

function requireEqual(field, expected, actual) {
  if (expected !== actual) {
    fail(`${field} differs between package.json and the VSIX`);
  }
}

for (const entry of [
  '[Content_Types].xml',
  'extension.vsixmanifest',
  'extension/package.json',
  'extension/LICENSE.txt',
  'extension/readme.md',
  'extension/changelog.md',
  'extension/out/extension.js',
  'extension/resources/rohd_icon.png',
  'extension/snippets/rohd.json',
  'extension/node_modules/ws/index.js',
]) {
  requireEntry(entry);
}

for (const prefix of [
  'extension/.dart_tool/',
  'extension/src/',
  'extension/tool/',
  'extension/node_modules/@types/',
]) {
  if ([...entries].some((entry) => entry.startsWith(prefix))) {
    fail(`VSIX contains excluded development content: ${prefix}`);
  }
}
for (const entry of [
  'extension/package-lock.json',
  'extension/pubspec.yaml',
  'extension/pubspec.lock',
  'extension/tsconfig.json',
  'extension/.gitignore',
  'extension/.vscodeignore',
]) {
  if (entries.has(entry)) {
    fail(`VSIX contains excluded development metadata: ${entry}`);
  }
}
if ([...entries].some((entry) => entry.endsWith('.map'))) {
  fail('VSIX contains excluded source maps');
}

for (const field of [
  'name',
  'version',
  'publisher',
  'license',
  'displayName',
  'description',
  'main',
  'icon',
]) {
  requireEqual(field, sourceManifest[field], packageManifest[field]);
}
requireEqual(
  'engines.vscode',
  sourceManifest.engines?.vscode,
  packageManifest.engines?.vscode,
);

if (sourceManifest.publisher !== 'intel-corporation') {
  fail(`Marketplace publisher must be intel-corporation, got ${sourceManifest.publisher}`);
}
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(sourceManifest.version)) {
  fail(`Extension version is not SemVer compatible: ${sourceManifest.version}`);
}
if (!pubspecVersion) {
  fail('pubspec.yaml does not declare an extension version');
}
if (pubspecVersion !== sourceManifest.version) {
  fail(
    `pubspec.yaml version ${pubspecVersion} does not match package.json version ${sourceManifest.version}`,
  );
}
if (!sourceManifest.engines?.vscode || sourceManifest.engines.vscode === '*') {
  fail('Extension manifest must declare a bounded engines.vscode range');
}
if (sourceManifest.license !== 'SEE LICENSE IN LICENSE') {
  fail('Extension manifest must reference its packaged LICENSE file');
}
if (!sourceManifest.repository?.url?.startsWith('https://github.com/intel/rohd')) {
  fail('Extension manifest must reference the ROHD source repository');
}
if (!sourceManifest.bugs?.url?.startsWith('https://github.com/intel/rohd/issues')) {
  fail('Extension manifest must declare the ROHD issue tracker');
}
if (!sourceManifest.homepage?.startsWith('https://github.com/intel/rohd/')) {
  fail('Extension manifest must declare its ROHD homepage');
}
if (!Array.isArray(sourceManifest.extensionKind) ||
    !sourceManifest.extensionKind.includes('workspace')) {
  fail('Extension manifest must declare workspace extensionKind');
}
if (!Array.isArray(sourceManifest.categories) || sourceManifest.categories.length === 0) {
  fail('Extension manifest must declare at least one Marketplace category');
}
if (!Array.isArray(sourceManifest.keywords) || sourceManifest.keywords.length === 0 ||
    sourceManifest.keywords.length > 30) {
  fail('Extension manifest must declare between 1 and 30 Marketplace keywords');
}
const expectedExtensionPack = [
  'intel-corporation.rohd-schematic-viewer',
  'intel-corporation.rohd-wave-viewer',
];
if (JSON.stringify(sourceManifest.extensionPack) !== JSON.stringify(expectedExtensionPack)) {
  fail('Extension manifest must declare the ROHD viewer extension pack');
}
if (JSON.stringify(packageManifest.extensionPack) !== JSON.stringify(expectedExtensionPack)) {
  fail('VSIX package manifest must preserve the ROHD viewer extension pack');
}
if (sourceManifest.extensionDependencies?.length) {
  fail('ROHD viewer extensions must be an extensionPack, not hard dependencies');
}

const mainEntry = `extension/${sourceManifest.main.replace(/^\.\//, '')}`;
requireEntry(mainEntry);
const iconEntry = `extension/${sourceManifest.icon.replace(/^\.\//, '')}`;
requireEntry(iconEntry);
if (/\.svg$/i.test(sourceManifest.icon)) {
  fail('Marketplace icons may not be SVG files');
}
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
if (!archiveFile(iconEntry).subarray(0, pngSignature.length).equals(pngSignature)) {
  fail(`Marketplace icon is not a PNG: ${iconEntry}`);
}

for (const markdownEntry of ['extension/readme.md', 'extension/changelog.md']) {
  const markdown = archiveFile(markdownEntry).toString('utf8');
  for (const [, imageUrl] of markdown.matchAll(/!\[[^\]]*]\(([^)\s]+)/g)) {
    if (imageUrl.startsWith('http://') || /\.svg(?:[?#].*)?$/i.test(imageUrl)) {
      fail(`${markdownEntry} contains a Marketplace-ineligible image URL: ${imageUrl}`);
    }
  }
}

const vsixManifest = archiveFile('extension.vsixmanifest').toString('utf8');
for (const [name, value] of [
  ['Id', sourceManifest.name],
  ['Version', sourceManifest.version],
  ['Publisher', sourceManifest.publisher],
]) {
  if (!new RegExp(`<Identity\\b[^>]*\\b${name}="${value}"`).test(vsixManifest)) {
    fail(`VSIX manifest identity does not contain ${name}="${value}"`);
  }
}

console.log(
  `Verified Marketplace VSIX: ${sourceManifest.publisher}.${sourceManifest.name} ${sourceManifest.version}`,
);
NODE
