# assets/js/

This directory is bundled wholesale as a Flutter asset (see `pubspec.yaml`).
Everything placed here ships in every build output: the Linux app, the
standalone web build, and the VS Code extension package.

## Files

- `elk.bundled.js` — the third-party [elkjs](https://github.com/kieler/elkjs)
  0.8.2 layout engine, vendored unmodified. See "Where to get elk.bundled.js"
  below.
- `elk_layout_only_native.js` — Intel's own QuickJS-compatible wrapper around
  ELK's layout engine (BSD-3-Clause, see repository root `LICENSE`). This is
  original code, not third-party.
- `LICENSE` — the upstream license text that applies to `elk.bundled.js`
  (Eclipse Public License 2.0, plus the Apache License 2.0 notice for its
  bundled web-worker shim). Identical to
  `assets/licenses/elkjs_LICENSES.txt`.

## Where to get elk.bundled.js

`elk.bundled.js` is distributed unmodified from upstream elkjs 0.8.2. If you
need to re-download or verify this file, obtain it from one of:

- <https://github.com/kieler/elkjs/tree/0.8.2> (source tag; build
  `lib/elk.bundled.js`)
- <https://registry.npmjs.org/elkjs/-/elkjs-0.8.2.tgz> (npm package tarball;
  contains `lib/elk.bundled.js`)

The shipped file's SHA-256 checksum is:

```text
cd56bf0ddb7ad2587583461d523fdd974dc56b59efd20cdfee954e1112ff1a49
```

See [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) at the
repository root for the full source-availability statement, and
`scripts/verify_elk_distribution.sh` for the automated check that keeps this
asset, its license, and all build outputs in sync.
