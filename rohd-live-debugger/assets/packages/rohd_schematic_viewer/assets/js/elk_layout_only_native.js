/**
 * Copyright (C) 2026 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * elk_layout_only_native.js
 * Minimal ELK layout wrapper for the Dart-first FlutterSchematicViewer
 * (QuickJS-compatible: no async/await, no window/document).
 *
 * This is the ONLY JavaScript the Dart-first path needs (besides elk.bundled.js).
 * It invokes ELK's layout engine and returns the raw hierarchical result.
 * All pre-processing (Yosys → ELK graph) and post-processing (coordinate
 * conversion, flattening) happens in Dart.
 *
 * 2026 February
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 */

var ElkLayoutOnly = (function () {
  'use strict';

  /**
   * Run ELK layout on a pre-built ELK graph and return the raw result.
   *
   * @param {string|object} elkGraphJson - ELK graph (JSON string or object)
   * @returns {Promise<object>} Raw ELK layout result (hierarchical, relative coords)
   */
  function elkLayoutOnly(elkGraphJson) {
    return new Promise(function (resolve) {
      try {
        var graph = (typeof elkGraphJson === 'string')
            ? JSON.parse(elkGraphJson)
            : elkGraphJson;

        // Ensure minimal ELK-required properties
        if (!graph.id) graph.id = 'root';
        if (!graph.properties) graph.properties = {};
        if (!graph.width) graph.width = 1;
        if (!graph.height) graph.height = 1;

        var layoutOptions = {
          'edgeRouting': 'ORTHOGONAL',
          'org.eclipse.elk.padding': '[top=30,left=60,bottom=10,right=60]',
          'org.eclipse.elk.spacing.edgeNode': '15',
        };

        var elk = new ELK();
        elk.layout(graph, { layoutOptions: layoutOptions }).then(function (result) {
          resolve(result);
        })['catch'](function (e) {
          console.error('[ElkLayoutOnly] error:', e);
          resolve({ error: (e && e.message) ? e.message : String(e) });
        });
      } catch (e) {
        console.error('[ElkLayoutOnly] parse error:', e);
        resolve({ error: (e && e.message) ? e.message : String(e) });
      }
    });
  }

  return elkLayoutOnly;
})();
