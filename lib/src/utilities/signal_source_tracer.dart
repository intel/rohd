// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// signal_source_tracer.dart
// Utility to capture stack traces showing where signals and instances are
// constructed during Module.build().
//
// 2026 April 21
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd/src/synthesizers/utilities/synth_logic.dart';
import 'package:rohd/src/synthesizers/utilities/synth_module_definition.dart';

/// Captures and stores stack traces for signal and submodule construction
/// sites, allowing later queries by hierarchical address.
///
/// Constructing an instance activates recording; all [Logic] and [Module]
/// constructors that follow will have their call-sites captured.
///
/// Example:
/// ```dart
/// SignalSourceTracer();          // activate tracing
/// final mod = MyModule(a, b);   // Logic constructors record stack traces
/// await mod.build();
///
/// // Query a specific signal by hierarchical address
/// final trace = SignalSourceTracer.traceOf(mod, 'myInternalSignal');
/// print(trace);
///
/// // Or get all traces for the module
/// final all = SignalSourceTracer.tracesForModule(mod);
/// for (final entry in all.entries) {
///   print('${entry.key}:\n${entry.value}\n');
/// }
/// ```
class SignalSourceTracer {
  /// Whether this tracer is actively recording.
  bool _recording = true;

  /// The currently active tracer instance (at most one at a time).
  static SignalSourceTracer? _current;

  /// Whether to embed `// ROHD:` source-trace comments in generated SV.
  ///
  /// When FLC data is written to a separate `.flc.json` file, the inline
  /// SV comments are redundant.  Set this to `false` before synthesis to
  /// suppress them while still recording traces for FLC generation.
  static bool embedInSv = true;

  /// Creates a tracer and starts recording stack traces for all
  /// subsequently constructed [Logic] signals and [Module]s.
  SignalSourceTracer() {
    _current = this;
  }

  /// Raw storage: maps a [Logic] (by identity) to the pre-stringified
  /// stack trace captured at its construction site.
  ///
  /// We call [StackTrace.toString] eagerly at capture time so that
  /// the expensive native-to-string conversion happens exactly once
  /// per trace.
  final Map<Logic, String> _signalTraces = Map<Logic, String>.identity();

  /// Raw storage: maps a [Module] (by identity) to the pre-stringified
  /// stack trace captured at its construction site.
  final Map<Module, String> _moduleTraces = Map<Module, String>.identity();

  /// Cache of regex-parsed raw frames, keyed by trace string.
  final Map<String, List<_RawFrame>> _rawFrameCache = {};

  /// Cache of resolved URIs: raw URI string to absolute file path.
  final Map<String, String> _resolvedUriCache = {};

  // ─── Recording (called from constructors / named()) ──────────────

  /// Records the current stack trace for [signal].
  ///
  /// This is a no-op when no tracer is actively recording.
  static void recordSignal(Logic signal) {
    final cur = _current;
    if (cur == null || !cur._recording) {
      return;
    }
    cur._signalTraces[signal] = StackTrace.current.toString();
  }

  /// Returns the stringified stack trace for [signal], or `null`.
  static String? signalTrace(Logic signal) => _current?._signalTraces[signal];

  /// Returns the stringified stack trace for [module], or `null`.
  static String? moduleTrace(Module module) => _current?._moduleTraces[module];

  /// Records the current stack trace for [module].
  ///
  /// This is a no-op when no tracer is actively recording.
  static void recordModule(Module module) {
    final cur = _current;
    if (cur == null || !cur._recording) {
      return;
    }
    cur._moduleTraces[module] = StackTrace.current.toString();
  }

  // ─── Querying ────────────────────────────────────────────────────

  /// Returns the [StackTrace] captured when the signal or submodule at
  /// [address] inside [module] was constructed, or `null` if no trace was
  /// recorded.
  ///
  /// The [address] is the *local* name of the signal or submodule instance
  /// within [module] — not the full hierarchical path.  For example, if the
  /// module has an internal signal named `nextVal`, pass `'nextVal'`.
  /// For a submodule instance, pass its [Module.uniqueInstanceName].
  static String? traceOf(Module module, String address) {
    final cur = _current;
    if (cur == null) {
      return null;
    }

    for (final sig in module.signals) {
      if (sig.name == address) {
        return cur._signalTraces[sig];
      }
    }

    for (final sub in module.subModules) {
      if (sub.uniqueInstanceName == address || sub.name == address) {
        return cur._moduleTraces[sub];
      }
    }

    return null;
  }

  /// Returns a map from name to [StackTrace] for every signal and submodule
  /// instance inside [module] that has a recorded trace.
  ///
  /// Signal names are taken from [Logic.name]; submodule names use
  /// [Module.uniqueInstanceName].
  static Map<String, String> tracesForModule(Module module) {
    final cur = _current;
    if (cur == null) {
      return const {};
    }
    final result = <String, String>{};

    for (final sig in module.signals) {
      final trace = cur._signalTraces[sig];
      if (trace != null) {
        result[sig.name] = trace;
      }
    }

    for (final sub in module.subModules) {
      final trace = cur._moduleTraces[sub];
      if (trace != null) {
        result[sub.uniqueInstanceName] = trace;
      }
    }

    return result;
  }

  /// Returns a map from full hierarchical address to [StackTrace] for every
  /// signal and submodule instance in the entire hierarchy rooted at [root].
  ///
  /// Addresses use dot-separated paths, e.g. `top.sub.signalName`.
  static Map<String, String> tracesForHierarchy(Module root) {
    final result = <String, String>{};
    _collectTracesRecursive(root, root.name, result);
    return result;
  }

  static void _collectTracesRecursive(
    Module module,
    String prefix,
    Map<String, String> result,
  ) {
    final cur = _current;
    if (cur == null) {
      return;
    }

    for (final sig in module.signals) {
      final trace = cur._signalTraces[sig];
      if (trace != null) {
        result['$prefix.${sig.name}'] = trace;
      }
    }

    for (final sub in module.subModules) {
      final trace = cur._moduleTraces[sub];
      final subPrefix = '$prefix.${sub.uniqueInstanceName}';
      if (trace != null) {
        result[subPrefix] = trace;
      }
      _collectTracesRecursive(sub, subPrefix, result);
    }
  }

  // ─── Report generation ────────────────────────────────────────

  /// A regular expression that matches Dart stack-trace frames of the form:
  ///   `#N  description (URI:line:col)`
  /// or
  ///   `#N  description (URI:line)`
  static final frameRe = RegExp(
    r'#\d+\s+' // frame number
    r'(.+?)\s+' // description (function / constructor)
    r'\((.+?)' // opening paren + URI
    r':(\d+)(?::(\d+))?' // :line and optional :col
    r'\)', // closing paren
  );

  /// DDC (Dart Development Compiler) web stack trace format.
  ///
  /// Lines look like:
  /// ```text
  /// package:rohd/src/signals/logic.dart 305:24  __
  /// dart-sdk/lib/async/zone.dart 1849:54        runUnary
  /// ```
  ///
  /// Groups: 1=URI, 2=line, 3=col, 4=description.
  static final webFrameRe = RegExp(
    r'^\s*'
    r'(\S+)\s+' // URI
    r'(\d+):(\d+)' // line:col
    r'\s+'
    r'(.+?)\s*$', // description
  );

  /// Chrome V8 / DDC compiled-to-JS stack trace format.
  ///
  /// Lines look like:
  /// ```text
  ///     at Logic.Logic$_$4$name$naming$width$wire (logic.dart:305:24)
  ///     at Object.SignalSourceTracer_recordSignal
  ///                  (signal_source_tracer.dart:81:44)
  /// ```
  ///
  /// Groups: 1=description, 2=URI, 3=line, 4=col (optional).
  static final v8FrameRe = RegExp(
    r'^\s*at\s+'
    r'(.+?)\s+' // description
    r'\((.+?)' // opening paren + URI
    r':(\d+)(?::(\d+))?' // :line and optional :col
    r'\)\s*$', // closing paren
  );

  /// Patterns matched against the URI portion of each stack frame to decide
  /// which frames to skip.  A frame is skipped when its URI contains any of
  /// these substrings.
  ///
  /// The defaults remove [SignalSourceTracer] internals, the Dart SDK,
  /// and common test-framework frames.
  static const defaultSkipPatterns = [
    'signal_source_tracer.dart',
    'package:rohd/src/signals/',
    'package:rohd/src/module.dart',
    'package:rohd/src/utilities/',
    'package:test_api/',
    'package:test_core/',
    'dart:', // All Dart SDK internals (dart:core, dart:_internal, etc.)
    'dart-sdk/', // DDC web format for Dart SDK frames
  ];

  /// Generates a plain-text report of every traced signal and submodule
  /// in the hierarchy rooted at [root].
  ///
  /// Each entry is the dot-separated hierarchical address followed by
  /// indented source locations.
  ///
  /// When [useFileUris] is `false` (the default), locations are formatted
  /// as absolute `path:line:col` strings that VS Code's integrated
  /// **terminal** auto-links (Ctrl+Click / Cmd+Click).
  ///
  /// When [useFileUris] is `true`, each location is a `file:///` URI
  /// followed by `:line:col`.  The `file:///` part is auto-linked in
  /// VS Code's **editor** (Ctrl+Click opens the file).  The line number
  /// is visible but not part of the link.
  ///
  /// [packageRoot] is the absolute path to the Dart package root (the
  /// directory containing `pubspec.yaml`).  It is used to resolve
  /// `package:` URIs to absolute file paths.  For example, passing
  /// `'/home/user/rohd'` turns `package:rohd/src/foo.dart` into
  /// `'/home/user/rohd/lib/src/foo.dart'`.
  ///
  /// [skipPatterns] controls which stack frames are filtered out.
  /// The defaults remove `SignalSourceTracer` internals, the Dart SDK,
  /// and test-framework frames.  Pass an empty list to keep everything.
  static String hierarchyReport(
    Module root, {
    required String packageRoot,
    bool useFileUris = false,
    List<String> skipPatterns = defaultSkipPatterns,
  }) {
    final pkgMap = loadPackageMap(packageRoot);
    final traces = tracesForHierarchy(root);
    final sortedKeys = traces.keys.toList()..sort();
    final buf = StringBuffer()
      ..writeln('Signal Source Trace Report')
      ..writeln('Module: ${root.name} (${root.definitionName})')
      ..writeln('Total traced objects: ${traces.length}')
      ..writeln();

    for (final key in sortedKeys) {
      buf.writeln(key);

      final frames = _parseFrames(
        traces[key]!,
        packageRoot: packageRoot,
        skipPatterns: skipPatterns,
        rootModuleName: root.runtimeType.toString(),
        packageMap: pkgMap,
      );
      for (final frame in frames) {
        if (useFileUris) {
          final lineSuffix = frame.col != null
              ? ':${frame.line}:${frame.col}'
              : ':${frame.line}';
          buf.writeln(
            '  ${frame.description}  file://${frame.absPath} $lineSuffix',
          );
        } else {
          buf.writeln('  ${frame.description}  ${frame.location}');
        }
      }
      buf.writeln();
    }

    return buf.toString();
  }

  /// Parses a pre-stringified stack trace into a list of [_Frame] records
  /// with resolved absolute file paths.
  ///
  /// The expensive work (split + regex matching) is cached in
  /// [_rawFrameCache] so that identical trace strings (common when many
  /// signals are created at the same call site, or when the same trace is
  /// processed by both per-module and hierarchy walks) are parsed only
  /// once.
  ///
  /// When `rootModuleName` is provided, frames are truncated at the first
  /// frame whose description matches `new <rootModuleName>`.
  ///
  /// When `includeRootFrame` is `false` (default), that matching frame is
  /// excluded.  When `true`, it is included and then parsing stops.
  /// Cache of fully-resolved parse results, keyed by
  /// `(traceString, rootModuleName, includeRootFrame)`.
  ///
  /// Because the skip-patterns and packageRoot are constant within a
  /// session, this avoids re-filtering and re-resolving URIs for
  /// the same trace string seen across multiple signals or modules.
  final Map<(String, String?, bool), List<_Frame>> _parsedFrameCache = {};

  static List<_Frame> _parseFrames(
    String traceString, {
    required String packageRoot,
    required List<String> skipPatterns,
    String? rootModuleName,
    bool includeRootFrame = false,
    Map<String, String>? packageMap,
  }) {
    final cacheKey = (traceString, rootModuleName, includeRootFrame);
    final cached = _current!._parsedFrameCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    // Get or compute the raw (unfiltered, unresolved) frames.
    final rawFrames = _current!._rawFrameCache.putIfAbsent(traceString, () {
      final lines = traceString.split('\n');
      final parsed = <_RawFrame>[];
      for (final line in lines) {
        // Try VM format: #N description (URI:line:col)
        var match = frameRe.firstMatch(line);
        if (match != null) {
          parsed.add(
            _RawFrame(
              description: match.group(1)!,
              uri: match.group(2)!,
              line: match.group(3)!,
              col: match.group(4),
            ),
          );
          continue;
        }
        // Try DDC web format: URI line:col  description
        match = webFrameRe.firstMatch(line);
        if (match != null) {
          parsed.add(
            _RawFrame(
              description: match.group(4)!,
              uri: match.group(1)!,
              line: match.group(2)!,
              col: match.group(3),
            ),
          );
          continue;
        }
        // Try Chrome V8 format: at description (URI:line:col)
        match = v8FrameRe.firstMatch(line);
        if (match != null) {
          parsed.add(
            _RawFrame(
              description: match.group(1)!,
              uri: match.group(2)!,
              line: match.group(3)!,
              col: match.group(4),
            ),
          );
        }
      }
      return parsed;
    });

    // Filter and resolve URIs (cheap compared to the regex work above).
    final result = <_Frame>[];
    for (final raw in rawFrames) {
      // Filter on the URI, not the whole raw line.
      if (skipPatterns.any(raw.uri.contains)) {
        continue;
      }

      final absPath = _current!._resolvedUriCache.putIfAbsent(
        raw.uri,
        () => _resolveUri(raw.uri, packageRoot, packageMap: packageMap),
      );

      // Stop at the root module's constructor — everything above it
      // (parent constructors, test harness, main) is not useful.
      if (rootModuleName != null && raw.description == 'new $rootModuleName') {
        if (includeRootFrame) {
          result.add(
            _Frame(
              description: raw.description,
              absPath: absPath,
              line: raw.line,
              col: raw.col,
            ),
          );
        }
        break;
      }

      result.add(
        _Frame(
          description: raw.description,
          absPath: absPath,
          line: raw.line,
          col: raw.col,
        ),
      );
    }

    _current!._parsedFrameCache[cacheKey] = result;
    return result;
  }

  /// Converts a URI from a stack frame into an absolute file path.
  ///
  /// Handles:
  ///  - `package:rohd/src/foo.dart` → `<packageRoot>/lib/src/foo.dart`
  ///  - `package:other/foo.dart` → resolved via [packageMap] if provided
  ///  - `file:///absolute/path.dart` → `/absolute/path.dart`
  ///  - relative or absolute paths → returned as-is
  ///
  /// [packageMap] maps package names to their absolute lib directory paths,
  /// loaded via [loadPackageMap].
  static String _resolveUri(
    String uri,
    String packageRoot, {
    Map<String, String>? packageMap,
  }) {
    // Determine the package name from packageRoot (last path segment)
    final packageName = packageRoot.split('/').last;

    if (uri.startsWith('package:$packageName/')) {
      // package:rohd/src/foo.dart → <root>/lib/src/foo.dart
      final relPath = uri.substring('package:$packageName/'.length);
      return '$packageRoot/lib/$relPath';
    }

    if (uri.startsWith('package:') && packageMap != null) {
      // package:other/src/foo.dart → look up in packageMap
      final withoutScheme = uri.substring('package:'.length);
      final slashIdx = withoutScheme.indexOf('/');
      if (slashIdx > 0) {
        final pkgName = withoutScheme.substring(0, slashIdx);
        final relPath = withoutScheme.substring(slashIdx + 1);
        final libDir = packageMap[pkgName];
        if (libDir != null) {
          return '$libDir/$relPath';
        }
      }
    }

    if (uri.startsWith('file:///')) {
      return uri.substring('file://'.length);
    }

    // Other package: URIs or plain paths — return as-is
    return uri;
  }

  /// Cache for [loadPackageMap] results, keyed by `packageRoot`.
  final Map<String, Map<String, String>> _packageMapCache = {};

  /// Loads a map from package name to absolute lib directory path by reading
  /// `.dart_tool/package_config.json` from [packageRoot].
  ///
  /// Results are cached so that repeated calls with the same [packageRoot]
  /// (e.g. once per module) do not re-read and re-parse the file.
  ///
  /// Returns an empty map if the file does not exist.
  static Map<String, String> loadPackageMap(String packageRoot) {
    final cache = _current?._packageMapCache;
    if (cache != null) {
      final cached = cache[packageRoot];
      if (cached != null) {
        return cached;
      }
    }

    final configFile = File('$packageRoot/.dart_tool/package_config.json');
    if (!configFile.existsSync()) {
      _current?._packageMapCache[packageRoot] = const {};
      return const {};
    }

    final config =
        json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final packages = config['packages'] as List<dynamic>? ?? [];
    final result = <String, String>{};

    for (final pkg in packages) {
      final pkgMap = pkg as Map<String, dynamic>;
      final name = pkgMap['name'] as String;
      final rootUri = pkgMap['rootUri'] as String;
      final packageUri = pkgMap['packageUri'] as String? ?? 'lib/';

      // rootUri may be absolute (file:///...) or relative (../..)
      String rootPath;
      if (rootUri.startsWith('file:///')) {
        rootPath = rootUri.substring('file://'.length);
      } else if (rootUri.startsWith('../') || rootUri.startsWith('./')) {
        rootPath = '$packageRoot/.dart_tool/$rootUri';
      } else {
        rootPath = rootUri;
      }

      // packageUri is typically 'lib/' — combined with rootPath gives the
      // directory that package: URIs resolve relative to.
      result[name] = '$rootPath/$packageUri'.replaceAll('//', '/');
      // Remove trailing slash
      if (result[name]!.endsWith('/')) {
        result[name] = result[name]!.substring(0, result[name]!.length - 1);
      }
    }

    _current?._packageMapCache[packageRoot] = result;
    return result;
  }

  /// Generates an HTML report that can be opened in VS Code's Simple Browser
  /// (or any browser) with clickable `vscode://file/` links.
  ///
  /// Each hierarchical signal/instance name is shown as a heading, followed
  /// by a list of source-location links.  Clicking a link opens the file
  /// at the exact line in VS Code.
  ///
  /// To open the result inside VS Code's Simple Browser panel, write the
  /// returned string to a `.html` file and use:
  ///
  /// ```dart
  /// // From a test or script:
  /// File('build/traces.html').writeAsStringSync(
  ///   SignalSourceTracer.htmlReport(mod, packageRoot: '/path/to/pkg'));
  /// ```
  ///
  /// Then open `build/traces.html` with **Simple Browser: Show** from the
  /// command palette, or programmatically with the VS Code
  /// `simpleBrowser.show` command.
  static String htmlReport(
    Module root, {
    required String packageRoot,
    List<String> skipPatterns = defaultSkipPatterns,
  }) {
    final pkgMap = loadPackageMap(packageRoot);
    final traces = tracesForHierarchy(root);
    final sortedKeys = traces.keys.toList()..sort();
    final buf = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="en"><head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln('<title>Signal Source Traces — ${_esc(root.name)}</title>')
      ..writeln('<style>')
      ..writeln(
        'body{font-family:monospace;font-size:13px;'
        'background:#1e1e1e;color:#d4d4d4;padding:16px}',
      )
      ..writeln('h1{font-size:18px;color:#569cd6}')
      ..writeln('.header{font-size:11px;color:#808080;margin-bottom:16px}')
      ..writeln(
        '.sig{margin-top:12px;margin-bottom:2px;'
        ' color:#dcdcaa;font-weight:bold}',
      )
      ..writeln('ul{margin:2px 0 0 20px;padding:0;list-style:none}')
      ..writeln('li{margin:1px 0}')
      ..writeln('a{color:#4ec9b0;text-decoration:none}')
      ..writeln('a:hover{text-decoration:underline}')
      ..writeln('.desc{color:#9cdcfe}')
      ..writeln('.loc{color:#ce9178}')
      ..writeln('</style>')
      ..writeln('</head><body>')
      ..writeln('<h1>Signal Source Trace Report</h1>')
      ..writeln(
        '<div class="header">'
        ' Module: ${_esc(root.name)} (${_esc(root.definitionName)})<br>'
        ' Total traced objects: ${traces.length}</div>',
      );

    for (final key in sortedKeys) {
      buf
        ..writeln('<div class="sig">${_esc(key)}</div>')
        ..writeln('<ul>');

      final frames = _parseFrames(
        traces[key]!,
        packageRoot: packageRoot,
        skipPatterns: skipPatterns,
        rootModuleName: root.runtimeType.toString(),
        packageMap: pkgMap,
      );
      for (final frame in frames) {
        final vscodeUri = 'vscode://file${frame.location}';
        final fileName = frame.absPath.split('/').last;
        final displayLoc = '$fileName:${frame.line}';

        buf.writeln(
          '<li>'
          ' <span class="desc">${_esc(frame.description)}</span> \u2014'
          ' <a href="${_esc(vscodeUri)}">'
          ' <span class="loc">${_esc(displayLoc)}</span></a></li>',
        );
      }

      buf.writeln('</ul>');
    }

    buf.writeln('</body></html>');

    return buf.toString();
  }

  /// HTML-escape helper.
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Removes all recorded traces and deactivates the tracer.
  static void clear() {
    final cur = _current;
    if (cur != null) {
      cur._signalTraces.clear();
      cur._moduleTraces.clear();
      cur._rawFrameCache.clear();
      cur._resolvedUriCache.clear();
      cur._parsedFrameCache.clear();
      cur._traceAttrCache.clear();
      cur._packageMapCache.clear();
      cur._recording = false;
      _current = null;
    }
  }

  // ─── JSON attribute injection ─────────────────────────────────

  /// Returns `true` if any traces have been recorded.
  ///
  /// The netlister can check this cheaply to skip trace injection
  /// when tracing was never enabled.
  static bool get hasTraces {
    final cur = _current;
    return cur != null &&
        (cur._signalTraces.isNotEmpty || cur._moduleTraces.isNotEmpty);
  }

  /// Produces a compact JSON-serialisable map of source-location traces
  /// for the signals and submodule instances directly inside `module`.
  ///
  /// Returns `null` if no traces were recorded for any element in
  /// `module`, allowing the caller to skip injection entirely.
  ///
  /// The returned structure is designed to be stored under an
  /// `"rohd.src_trace"` key in the module's `attributes` map in the
  /// Yosys-compatible JSON netlist.  Viewers that don't recognise the
  /// key will silently ignore it.
  ///
  /// **Format:**
  /// ```json
  /// {
  ///   "files": ["lib/src/examples/foo.dart", "lib/src/modules/bar.dart"],
  ///   "signals": {
  ///     "mySignal": ["0:42:5"]
  ///   },
  ///   "instances": {
  ///     "sub0": ["1:99:3", "0:200:7"]
  ///   }
  /// }
  /// ```
  ///
  /// - `"files"` — deduplicated array of file paths relative to
  ///   `packageRoot`.  Each trace frame references a file by its index.
  ///
  /// Each frame is a colon-separated string: `fileIndex:line[:column]`.
  ///
  /// - **file index** — integer index into the `"files"` array.
  /// - **line** — 1-based source line number.
  /// - **column** — 1-based column number (omitted if unavailable).
  ///
  /// Example: `"0:42:5"` means file `files[0]`, line 42, column 5.
  ///
  /// `packageRoot` is the absolute path to the Dart package root.
  ///
  /// `skipPatterns` controls which stack frames are filtered out;
  /// see `defaultSkipPatterns`.
  ///
  /// Results are cached by module identity so that repeated calls (e.g.
  /// from `collectModuleEntries` and then `traceJsonForModule`) reuse
  /// the already-parsed trace data.
  final Map<Module, Map<String, Object>?> _traceAttrCache =
      Map<Module, Map<String, Object>?>.identity();

  /// Returns `true` if [module] can be wrapped in a [SynthModuleDefinition].
  ///
  /// Inline SystemVerilog helpers (e.g. `BusSubset`, `Swizzle`) set
  /// [DefinitionGenerationType.none] and must not be passed to the
  /// [SynthModuleDefinition] constructor.
  static bool _canBuildSynthDef(Module module) => !(module is SystemVerilog &&
      module.generatedDefinitionType == DefinitionGenerationType.none);

  /// Returns a compact JSON-serialisable map of source-location traces for
  /// the signals and submodule instances directly inside `module`, or `null` if
  /// no traces were recorded for any element in `module`.
  static Map<String, Object>? traceAttributesForModule(
    Module module, {
    required String packageRoot,
    List<String> skipPatterns = defaultSkipPatterns,
  }) {
    if (_current!._traceAttrCache.containsKey(module)) {
      return _current!._traceAttrCache[module];
    }
    final pkgMap = loadPackageMap(packageRoot);
    final fileIndex = <String, int>{};
    final files = <String>[];

    int fileIdx(String absPath) {
      // Store relative to packageRoot for portability.
      final rel = absPath.startsWith('$packageRoot/')
          ? absPath.substring(packageRoot.length + 1)
          : absPath;
      return fileIndex.putIfAbsent(rel, () {
        files.add(rel);
        return files.length - 1;
      });
    }

    List<String>? encodeTrace(String? trace) {
      if (trace == null) {
        return null;
      }
      // For per-module JSON attributes, include the module's own
      // constructor frame (it shows the allocation site) but stop
      // after it — parent constructors are irrelevant since the
      // viewer already knows the module hierarchy.
      final frames = _parseFrames(
        trace,
        packageRoot: packageRoot,
        skipPatterns: skipPatterns,
        rootModuleName: module.runtimeType.toString(),
        includeRootFrame: true,
        packageMap: pkgMap,
      );
      if (frames.isEmpty) {
        return null;
      }
      return [
        for (final f in frames)
          '${fileIdx(f.absPath)}:${f.line}${f.col != null ? ':${f.col}' : ''}',
      ];
    }

    final signals = <String, Object>{};

    // Use SynthModuleDefinition for canonical signal names — same as
    // the SV and netlist synthesizers.  Some modules (inline SV helpers
    // like BusSubset) have DefinitionGenerationType.none and cannot be
    // wrapped in a SynthModuleDefinition; fall back to module.signals.
    if (_canBuildSynthDef(module)) {
      final synthDef = SynthModuleDefinition(module);
      final allSynthLogics = [
        ...synthDef.inputs,
        ...synthDef.outputs,
        ...synthDef.inOuts,
        ...synthDef.internalSignals,
      ];
      for (final sl in allSynthLogics) {
        List<String>? encoded;
        for (final logic in sl.logics) {
          encoded = encodeTrace(_current!._signalTraces[logic]);
          if (encoded != null) {
            break;
          }
        }
        if (encoded == null) {
          continue;
        }
        final canonicalName = sl.name;
        if (!signals.containsKey(canonicalName)) {
          signals[canonicalName] = encoded;
        }
      }
    } else {
      for (final sig in module.signals) {
        final encoded = encodeTrace(_current!._signalTraces[sig]);
        if (encoded != null) {
          signals[sig.name] = encoded;
        }
      }
    }

    final instances = <String, Object>{};
    for (final sub in module.subModules) {
      final encoded = encodeTrace(_current!._moduleTraces[sub]);
      if (encoded != null) {
        instances[sub.uniqueInstanceName] = encoded;
      }
    }

    if (signals.isEmpty && instances.isEmpty) {
      _current!._traceAttrCache[module] = null;
      return null;
    }

    final result = <String, Object>{
      'files': files,
      if (signals.isNotEmpty) 'signals': signals,
      if (instances.isNotEmpty) 'instances': instances,
    };
    _current!._traceAttrCache[module] = result;
    return result;
  }

  // ─── FLC (File-Line-Column) JSON output ───────────────────────

  /// Produces a compact JSON-serialisable map containing trace data for the
  /// entire module hierarchy rooted at [root], using the trie-based v6
  /// format.
  ///
  /// Each module's traces are encoded as a compact trie (nested JSON arrays)
  /// where shared call-site prefixes are stored once.  Leaf symbols are
  /// encoded as strings of the form:
  ///
  /// ```text
  /// [*]name[@positions][~origName]
  /// positions  := lang_group ( ; lang_group )*
  /// lang_group := lang : entry ( , entry )*
  /// entry      := [F:]L:C            // F = index into outputFiles[lang]
  /// ```
  ///
  /// - `*` prefix marks a submodule instance (vs. a signal).
  /// - Within a language group, entries are textual-order positions in the
  ///   generated output. The last entry per language is the declaration;
  ///   earlier entries are assignment LHS lines.
  /// - The `F:` file-index prefix is omitted when the language has a
  ///   single output file (the common case).
  /// - `~origName` is included only when the generated symbol name differs
  ///   from a friendlier original Dart name.
  ///
  /// A trie node is `[frame, ...children_and_symbols]` where children are
  /// nested arrays and symbols are strings.
  ///
  /// **Format (version 6):**
  /// ```json
  /// {
  ///   "version": 6,
  ///   "files": ["lib/src/foo.dart", "lib/src/bar.dart"],
  ///   "modules": {
  ///     "ModuleName": {
  ///       "outputFiles": {"sv": ["ModuleName.sv"], "sc": ["ModuleName.h"]},
  ///       "tree": [
  ///         ["1:10:3", ["0:42:5", "sig@sv:120:5,142:1;sc:33:10"]]
  ///       ]
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// [outputLineMaps] is keyed as
  /// `lang -> defName -> symbolName -> List<"L:C"|"F:L:C">`.
  /// [outputFiles] is keyed as `defName -> lang -> List<filename>`.
  ///
  /// Returns `null` if no traces were recorded at all.
  static Map<String, Object>? traceJsonForHierarchy(
    Module root, {
    required String packageRoot,
    List<String> skipPatterns = defaultSkipPatterns,
    Map<String, Map<String, Map<String, List<String>>>>? outputLineMaps,
    Map<String, Map<String, List<String>>>? outputFiles,
    Map<String, String>? packageMap,
  }) {
    if (!hasTraces) {
      return null;
    }

    final pkgMap = packageMap ?? loadPackageMap(packageRoot);

    // Shared file table across all modules.
    final fileIndex = <String, int>{};
    final files = <String>[];

    int fileIdx(String absPath) {
      final rel = absPath.startsWith('$packageRoot/')
          ? absPath.substring(packageRoot.length + 1)
          : absPath;
      return fileIndex.putIfAbsent(rel, () {
        files.add(rel);
        return files.length - 1;
      });
    }

    /// Encode a raw trace into a list of frame strings (innermost first).
    /// Returns `null` if [trace] is null or yields no frames.
    List<String>? encodeFrames(String? trace, Module module) {
      if (trace == null) {
        return null;
      }
      final frames = _parseFrames(
        trace,
        packageRoot: packageRoot,
        skipPatterns: skipPatterns,
        rootModuleName: module.runtimeType.toString(),
        includeRootFrame: true,
        packageMap: pkgMap,
      );
      if (frames.isEmpty) {
        return null;
      }
      return [
        for (final f in frames)
          '${fileIdx(f.absPath)}:${f.line}${f.col != null ? ':${f.col}' : ''}',
      ];
    }

    /// Encode a symbol name + metadata as a compact v6 string.
    ///
    /// [langPositions] is `lang -> List<"L:C">` (or `"F:L:C"` when the
    /// language has multiple output files). Each language becomes one
    /// semicolon-separated group; entries within a language are
    /// comma-separated in textual order.
    String encodeSymbol(
      String name, {
      bool isInstance = false,
      Map<String, List<String>>? langPositions,
      String? origName,
    }) {
      final buf = StringBuffer();
      if (isInstance) {
        buf.write('*');
      }
      buf.write(name);

      if (langPositions != null && langPositions.isNotEmpty) {
        final groups = <String>[];
        for (final e in langPositions.entries) {
          if (e.value.isEmpty) {
            continue;
          }
          groups.add('${e.key}:${e.value.join(',')}');
        }
        if (groups.isNotEmpty) {
          buf
            ..write('@')
            ..write(groups.join(';'));
        }
      }

      if (origName != null) {
        buf
          ..write('~')
          ..write(origName);
      }
      return buf.toString();
    }

    final modules = <String, Object>{};

    /// Collect per-language positions for [name] from [outputLineMaps] for
    /// [defName]. Returns null if no language has any entry for [name].
    Map<String, List<String>>? collectPositions(String defName, String name) {
      if (outputLineMaps == null) {
        return null;
      }
      Map<String, List<String>>? result;
      for (final entry in outputLineMaps.entries) {
        final m = entry.value[defName];
        if (m == null) {
          continue;
        }
        final list = m[name];
        if (list == null || list.isEmpty) {
          continue;
        }
        (result ??= {})[entry.key] = list;
      }
      return result;
    }

    void walk(Module module) {
      final defName = module.definitionName;

      if (!modules.containsKey(defName)) {
        // Per-module trie: children keyed by frame string.
        final trieChildren = <String, _TrieNode>{};

        /// Insert frames (reversed to outermost-first) with a leaf symbol.
        void insertIntoTrie(List<String> frames, String symbol) {
          final reversed = frames.reversed.toList();
          var children = trieChildren;
          for (var i = 0; i < reversed.length; i++) {
            final frame = reversed[i];
            final node = children.putIfAbsent(frame, () => _TrieNode(frame));
            if (i == reversed.length - 1) {
              node.symbols.add(symbol);
            } else {
              children = node.children;
            }
          }
        }

        // --- Signals ---
        final useSynthDef = _canBuildSynthDef(module);
        final synthDef = useSynthDef ? SynthModuleDefinition(module) : null;
        final allSynthLogics = useSynthDef
            ? [
                ...synthDef!.inputs,
                ...synthDef.outputs,
                ...synthDef.inOuts,
                ...synthDef.internalSignals,
              ]
            : <SynthLogic>[];

        if (useSynthDef) {
          for (final sl in allSynthLogics) {
            List<String>? frames;
            final logicNames = <String>{};
            for (final logic in sl.logics) {
              logicNames.add(logic.name);
              final f = encodeFrames(_current!._signalTraces[logic], module);
              if (f != null && frames == null) {
                frames = f;
              }
            }
            if (frames == null) {
              continue;
            }

            final canonicalName = sl.name;

            // Deduplicate: skip if already inserted for this definition.
            // (Use a set to track — cheaper than searching the trie.)
            String? origName;
            if (!logicNames.contains(canonicalName)) {
              final base = canonicalName.replaceFirst(RegExp(r'_\d+$'), '');
              if (base != canonicalName && logicNames.contains(base)) {
                origName = base;
              } else {
                origName = logicNames
                    .where((n) => !n.startsWith('_'))
                    .followedBy(logicNames)
                    .first;
                if (origName == canonicalName) {
                  origName = null;
                }
              }
            }
            final needsOrig = origName != null && origName != canonicalName;

            insertIntoTrie(
              frames,
              encodeSymbol(
                canonicalName,
                langPositions: collectPositions(defName, canonicalName),
                origName: needsOrig ? origName : null,
              ),
            );
          }
        } else {
          for (final sig in module.signals) {
            final frames = encodeFrames(_current!._signalTraces[sig], module);
            if (frames != null) {
              insertIntoTrie(frames, encodeSymbol(sig.name));
            }
          }
        }

        // --- Instances ---
        for (final sub in module.subModules) {
          final frames = encodeFrames(_current!._moduleTraces[sub], module);
          if (frames == null) {
            continue;
          }
          final instName = sub.uniqueInstanceName;
          insertIntoTrie(
            frames,
            encodeSymbol(
              instName,
              isInstance: true,
              langPositions: collectPositions(defName, instName),
            ),
          );
        }

        // Serialize trie.
        if (trieChildren.isNotEmpty) {
          final tree = [
            for (final node in trieChildren.values) node.serialize(),
          ];
          final moduleFiles = outputFiles?[defName];
          modules[defName] = <String, Object>{
            if (moduleFiles != null && moduleFiles.isNotEmpty)
              'outputFiles': moduleFiles,
            'tree': tree,
          };
        }
      }

      module.subModules.forEach(walk);
    }

    walk(root);

    if (modules.isEmpty) {
      return null;
    }

    return <String, Object>{
      'version': 6,
      'files': files,
      'modules': modules,
      if (packageRoot.isNotEmpty) 'packageRoot': packageRoot,
    };
  }

  /// Produces a compact JSON-serialisable map containing trace data for
  /// a single [module], in the same FLC v6 trie format as
  /// [traceJsonForHierarchy] but with only one module entry.
  ///
  /// This is used when writing one `.flc.json` file per `.sv` file.
  ///
  /// [outputLineMap] is `lang -> symbolName -> List<"L:C"|"F:L:C">` for
  /// the single module. [outputFile] is `lang -> List<filename>`.
  ///
  /// Returns `null` if no traces were recorded for this module.
  static Map<String, Object>? traceJsonForModule(
    Module module, {
    required String packageRoot,
    List<String> skipPatterns = defaultSkipPatterns,
    Map<String, List<String>>? outputFile,
    Map<String, Map<String, List<String>>>? outputLineMap,
  }) =>
      // Delegate to the trie-based hierarchy generator with just this module.
      traceJsonForHierarchy(
        module,
        packageRoot: packageRoot,
        skipPatterns: skipPatterns,
        outputLineMaps: outputLineMap != null
            ? {
                for (final e in outputLineMap.entries)
                  e.key: {module.definitionName: e.value},
              }
            : null,
        outputFiles:
            outputFile != null ? {module.definitionName: outputFile} : null,
      );

  /// Generates a self-contained HTML viewer that loads FLC JSON data
  /// and renders it as a searchable, clickable table.
  ///
  /// The [flcJson] is the JSON string from [traceJsonForHierarchy].
  /// The viewer is a single HTML file with embedded JavaScript — no
  /// external dependencies.
  static String flcHtmlViewer(
    String flcJson, {
    String title = 'FLC Viewer',
    String packageRoot = '',
  }) {
    // Escape only the `</` sequence to prevent closing the script tag early.
    // This is the standard safe embedding for JSON inside <script>.
    final safeJson = flcJson.replaceAll('</', r'<\/');
    // Escape packageRoot for safe embedding in JS.
    final safeRoot = packageRoot.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    return '''
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>$title</title>
<style>
body{font-family:monospace;font-size:13px;background:#1e1e1e;color:#d4d4d4;padding:16px;margin:0}
h1{font-size:18px;color:#569cd6;margin:0 0 8px}
.stats{font-size:11px;color:#808080;margin-bottom:12px}
input{width:100%;box-sizing:border-box;padding:6px 8px;margin-bottom:12px;
  background:#2d2d2d;color:#d4d4d4;border:1px solid #3c3c3c;font-family:monospace}
table{border-collapse:collapse;width:100%}
th{text-align:left;color:#569cd6;border-bottom:1px solid #3c3c3c;padding:4px 8px;position:sticky;top:0;background:#1e1e1e}
td{padding:3px 8px;border-bottom:1px solid #2d2d2d;vertical-align:top}
.mod{color:#dcdcaa;font-weight:bold}
.sym{color:#9cdcfe}
.kind{color:#808080;font-size:11px}
a{color:#4ec9b0;text-decoration:none}
a:hover{text-decoration:underline}
tr.hidden{display:none}
</style>
</head><body>
<h1>Signal Source Trace Report</h1>
<div class="stats" id="stats"></div>
<input type="text" id="filter" placeholder="Filter by module or symbol name...">
<table>
<thead><tr><th>Module</th><th>Symbol</th><th>Kind</th><th>Output</th><th>Source Locations</th></tr></thead>
<tbody id="tbody"></tbody>
</table>
<script id="flc-data" type="application/json">
$safeJson
</script>
<script>
const data = JSON.parse(document.getElementById('flc-data').textContent);
const files = data.files;
const root = '$safeRoot' ? '$safeRoot/' : '';
const tbody = document.getElementById('tbody');
const stats = document.getElementById('stats');
let totalSymbols = 0;

function makeLinks(frames) {
  return frames.map(f => {
    const parts = f.split(':');
    const fi = parseInt(parts[0]);
    const line = parts[1];
    const col = parts.length > 2 ? parts[2] : null;
    const file = files[fi];
    const display = file.split('/').pop() + ':' + line;
    const abs = root + file;
    const loc = col ? abs + ':' + line + ':' + col : abs + ':' + line;
    return '<a href="vscode://file/' + loc + '">' + display + '</a>';
  }).join(', ');
}

function makeOutputLink(pos, outputFiles) {
  if (!pos) return '';
  const files = outputFiles && outputFiles[pos.lang];
  if (!files || files.length === 0) return '';
  const file = files[pos.fileIdx] || files[0];
  const abs = root + file;
  const label = file.split('/').pop() + ':' + pos.line;
  return '<a href="vscode://file/' + abs + ':' + pos.line + ">'
    + '[' + pos.lang.toUpperCase() + '] ' + label + '</a>';
}

// Parse a v6 symbol string: [*]name[@positions][~origName]
// positions  := lang_group ( ; lang_group )*
// lang_group := lang : entry ( , entry )*
// entry      := [F:]L:C
function parseSymbol(s) {
  let isInstance = s.startsWith('*');
  let rest = isInstance ? s.substring(1) : s;
  let origName = null;
  const tildeIdx = rest.indexOf('~');
  if (tildeIdx >= 0) { origName = rest.substring(tildeIdx + 1); rest = rest.substring(0, tildeIdx); }
  let positions = [];
  const atIdx = rest.indexOf('@');
  if (atIdx >= 0) {
    const groupsStr = rest.substring(atIdx + 1);
    rest = rest.substring(0, atIdx);
    for (const group of groupsStr.split(';')) {
      if (!group) continue;
      const firstColon = group.indexOf(':');
      if (firstColon < 0) continue;
      const lang = group.substring(0, firstColon);
      const entriesStr = group.substring(firstColon + 1);
      for (const entry of entriesStr.split(',')) {
        const parts = entry.split(':');
        let fileIdx = 0, line, col;
        if (parts.length === 3) {
          fileIdx = parseInt(parts[0]);
          line = parts[1];
          col = parts[2];
        } else if (parts.length === 2) {
          line = parts[0];
          col = parts[1];
        } else {
          continue;
        }
        positions.push({ lang, fileIdx, line, col });
      }
    }
  }
  return { name: rest, isInstance, positions, origName };
}

// Walk a v6 trie node, collecting frames along the path.
function walkTrie(node, path, modName, outputFiles) {
  if (!Array.isArray(node) || node.length === 0) return;
  const frame = node[0];
  const currentPath = [...path, frame];
  for (let i = 1; i < node.length; i++) {
    const elem = node[i];
    if (Array.isArray(elem)) {
      walkTrie(elem, currentPath, modName, outputFiles);
    } else if (typeof elem === 'string') {
      const sym = parseSymbol(elem);
      addRow(modName, sym.name, sym.isInstance ? 'instance' : 'signal',
             currentPath, sym.positions, outputFiles);
    }
  }
}

function addRow(modName, sym, kind, frames, positions, outputFiles) {
  const tr = document.createElement('tr');
  tr.dataset.search = (modName + ' ' + sym).toLowerCase();
  const posLinks = positions.map(p => makeOutputLink(p, outputFiles)).filter(x => x).join(', ');
  tr.innerHTML = '<td class="mod">' + modName + '</td>'
    + '<td class="sym">' + sym + '</td>'
    + '<td class="kind">' + kind + '</td>'
    + '<td>' + posLinks + '</td>'
    + '<td>' + makeLinks(frames) + '</td>';
  tbody.appendChild(tr);
  totalSymbols++;
}

for (const [modName, modData] of Object.entries(data.modules)) {
  // v6: outputFiles is { lang: [file, ...] }.
  const outputFiles = modData.outputFiles || {};
  if (modData.tree) {
    for (const rootNode of modData.tree) {
      walkTrie(rootNode, [], modName, outputFiles);
    }
  }
}

stats.textContent = Object.keys(data.modules).length + ' modules, '
  + totalSymbols + ' symbols, '
  + files.length + ' source files';

document.getElementById('filter').addEventListener('input', function() {
  const q = this.value.toLowerCase();
  for (const tr of tbody.children) {
    tr.classList.toggle('hidden', q && !tr.dataset.search.includes(q));
  }
});
</script>
</body></html>''';
  }
}

/// Trie node for v5 FLC format.
///
/// Each node represents a single stack frame.  Children are further frames
/// deeper in the call stack; [symbols] are leaf entries (signals/instances)
/// encoded as compact strings.
class _TrieNode {
  final String frame;
  final Map<String, _TrieNode> children = {};
  final List<String> symbols = [];

  _TrieNode(this.frame);

  /// Serialize to a JSON-compatible nested list.
  List<Object> serialize() {
    final result = <Object>[frame];
    for (final child in children.values) {
      result.add(child.serialize());
    }
    result.addAll(symbols);
    return result;
  }
}

/// A parsed stack-trace frame with resolved absolute path.
class _Frame {
  final String description;
  final String absPath;
  final String line;
  final String? col;

  const _Frame({
    required this.description,
    required this.absPath,
    required this.line,
    this.col,
  });

  /// `absPath:line:col` (or `absPath:line` when col is null).
  String get location => col != null ? '$absPath:$line:$col' : '$absPath:$line';
}

/// A raw (unresolved) stack-trace frame cached after regex parsing.
///
/// Unlike [_Frame], the URI is not yet resolved to an absolute path and no
/// filtering has been applied.  This is the cached intermediate
/// representation used by [SignalSourceTracer._rawFrameCache].
class _RawFrame {
  final String description;
  final String uri;
  final String line;
  final String? col;

  const _RawFrame({
    required this.description,
    required this.uri,
    required this.line,
    this.col,
  });
}
