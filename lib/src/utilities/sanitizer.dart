/// Copyright (C) 2021-2022 Intel Corporation
/// SPDX-License-Identifier: BSD-3-Clause
///
/// sanitizer.dart
/// Sanitizes strings so they don't collide with generated code in other languages (e.g. SystemVerilog)
///
/// 2021 May 7
/// Author: Max Korbel <max.korbel@intel.com>
///

/***/

/// A utility for ensuring generated code is "sanitary".
///
/// "Sanitary" means it doesn't have any characters illegal in generated languages,
/// doesn't collide with keywords in generated languages, and has a valid variable
/// name in generated languages.
abstract class Sanitizer {
  /// Returns true iff [name] needs no renaming to be "sanitary".
  static bool isSanitary(String name) {
    return name == sanitizeSV(name);
  }

  /// Returns a modified version of [initialName] which is guaranteed to be "sanitary".
  static String sanitizeSV(String initialName) {
    var newName = initialName;

    // get rid of any weird characters, replace with `_`
    newName = newName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

    // can't start with a number
    if (newName.startsWith(RegExp(r'[0-9]'))) {
      newName = 's' + newName;
    }

    // add `_` to the end if the name is a SystemVerilog keyword
    while (_reservedSVKeywords.contains(newName)) {
      newName += '_';
    }

    return newName;
  }

  /// A set of all the reserved keywords in SystemVerilog.
  static const Set<String> _reservedSVKeywords = {
    'always',
    'end',
    'ifnone',
    'or',
    'rpmos',
    'tranif1',
    'and',
    'endcase',
    'initial',
    'output',
    'rtran',
    'tri',
    'assign',
    'endmodule',
    'inout',
    'parameter',
    'rtranif0',
    'tri0',
    'begin',
    'endfunction',
    'input',
    'pmos',
    'rtranif1',
    'tri1',
    'buf',
    'endprimitive',
    'integer',
    'posedge',
    'scalared',
    'triand',
    'bufif0',
    'endspecify',
    'join',
    'primitive',
    'small',
    'trior',
    'bufif1',
    'endtable',
    'large',
    'pull0',
    'specify',
    'trireg',
    'case',
    'endtask',
    'macromodule',
    'pull1',
    'specparam',
    'vectored',
    'casex',
    'event',
    'medium',
    'pullup',
    'strong0',
    'wait',
    'casez',
    'for',
    'module',
    'pulldown',
    'strong1',
    'wand',
    'cmos',
    'force',
    'nand',
    'rcmos',
    'supply0',
    'weak0',
    'deassign',
    'forever',
    'negedge',
    'real',
    'supply1',
    'weak1',
    'default',
    'nmos',
    'realtime',
    'table',
    'while',
    'defparam',
    'function',
    'nor',
    'reg',
    'task',
    'wire',
    'disable',
    'highz0',
    'not',
    'release',
    'time',
    'wor',
    'edge',
    'highz1',
    'notif0',
    'repeat',
    'tran',
    'xnor',
    'else',
    'if',
    'notif1',
    'rnmos',
    'tranif0',
    'xor',
  };
}
