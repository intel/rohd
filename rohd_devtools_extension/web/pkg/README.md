# Wellen web runtime

These files provide the WebAssembly runtime used by `dart_wellen` in the ROHD
DevTools web builds. They are checked in because `dart_wellen 0.1.0` contains
the generated Dart bindings but does not publish its required `web/pkg`
runtime.

The JavaScript and WebAssembly files were generated from
`intel/rohd-wave-viewer` commit
`5ae4b3a684b4f2c4c62288402e05f0aa68027991` using that repository's pinned
Rust 1.92.0, Flutter Rust Bridge 2.7.0, wasm-pack 0.13.1, and wasm-bindgen
0.2.121 build scripts. The upstream webview compatibility patches were then
applied.

SHA-256:

```text
91fb0079cdb70f23012079b572e68535e9aec0b8dac742d7a3c59c86d0749984  wellen_bridge.js
6bf93af619bce16e0bc729b0ddce4e47b50aea1b240021f9aa29b2b5b60191ca  wellen_bridge_bg.wasm
```

The runtime is distributed under the BSD 3-Clause license in `LICENSE`.
