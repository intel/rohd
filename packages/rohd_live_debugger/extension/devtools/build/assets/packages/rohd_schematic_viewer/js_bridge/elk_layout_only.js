/**
 * Copyright (C) 2026 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * elk_layout_only.js
 * Minimal ELK layout wrapper for the Dart-first FlutterSchematicViewer.
 *
 * This is the ONLY JavaScript the Dart-first path needs (besides elk.bundled.js).
 * It invokes ELK's layout engine and returns the raw hierarchical result.
 * All pre-processing (Yosys → ELK graph) and post-processing (coordinate
 * conversion, flattening) happens in Dart.
 *
 * 2026 February
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 */

(function () {
  'use strict';

  /**
   * Run ELK layout on a pre-built ELK graph and return the raw result.
   *
   * @param {string|object} elkGraphJson - ELK graph (JSON string or object)
   * @returns {Promise<object>} Raw ELK layout result (hierarchical, relative coords)
   */
  async function elkLayoutOnly(elkGraphJson) {
    try {
      var graph = (typeof elkGraphJson === 'string')
          ? JSON.parse(elkGraphJson)
          : elkGraphJson;

      // Ensure minimal ELK-required properties
      if (!graph.id) graph.id = 'root';
      if (!graph.properties) graph.properties = {};
      if (!graph.width) graph.width = 1;
      if (!graph.height) graph.height = 1;

      // ELK drops unknown fields (_children, _edges, isPartiallyExpanded).
      // Save them before layout and restore afterwards.
      var hiddenData = {};
      function saveHidden(node, path) {
        var entry = {};
        if (node._children) entry._children = node._children;
        if (node._edges)    entry._edges    = node._edges;
        if (node.isPartiallyExpanded) entry.isPartiallyExpanded = true;
        if (Object.keys(entry).length > 0) hiddenData[path] = entry;
        if (node.children) {
          for (var i = 0; i < node.children.length; i++) {
            saveHidden(node.children[i], path + '/' + (node.children[i].id || i));
          }
        }
      }
      saveHidden(graph, graph.id || 'root');

      var layoutOptions = {
        'edgeRouting': 'ORTHOGONAL',
        'org.eclipse.elk.padding': '[top=30,left=60,bottom=10,right=60]',
        'org.eclipse.elk.spacing.edgeNode': '15',
      };

      var elk = new ELK();
      try {
        var result = await elk.layout(graph, { layoutOptions: layoutOptions });

        // Restore hidden data that ELK dropped.
        function restoreHidden(node, path) {
          var entry = hiddenData[path];
          if (entry) {
            if (entry._children) node._children = entry._children;
            if (entry._edges)    node._edges    = entry._edges;
            if (entry.isPartiallyExpanded) node.isPartiallyExpanded = true;
          }
          if (node.children) {
            for (var i = 0; i < node.children.length; i++) {
              restoreHidden(node.children[i], path + '/' + (node.children[i].id || i));
            }
          }
        }
        restoreHidden(result, result.id || 'root');

        return result;
      } finally {
        if (typeof elk.terminate === 'function') elk.terminate();
      }
    } catch (e) {
      var msg = (e && e.message) ? e.message : String(e);
      console.error('[ElkLayoutOnly] error:', msg);
      return { error: msg };
    }
  }

  // Export for web (Dart interop reads window.ElkLayoutOnly)
  if (typeof window !== 'undefined') {
    window.ElkLayoutOnly = elkLayoutOnly;
  }
})();
