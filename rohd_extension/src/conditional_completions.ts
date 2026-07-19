/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * conditional_completions.ts
 * Context-aware CompletionItemProvider for ROHD constructs.
 *
 * Four scopes:
 *
 * 1. FILE SCOPE — FSM (enum + class extends Module), Module scaffold
 *    only appear at file/top level, not inside a function like main().
 *
 * 2. MODULE BODY — Pipeline, Sequential, Combinational appear when the
 *    cursor is inside a class that extends Module.
 *
 * 3. INSIDE _ALWAYS — If, If.block, Iff, Else, Case, CaseZ,
 *    CaseItem, and conditional assignment (<) only appear when the
 *    cursor is inside a Combinational or Sequential block.
 *
 * 4. TEST DIRECTORY — test(), group(), tearDown(), and ROHD simulation
 *    test scaffolds only appear for Dart files under a test/ directory.
 *
 * Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>
 * --------------------------------------------------------------------------- */

import * as vscode from 'vscode';

// ---------------------------------------------------------------------------
// Context detection
// ---------------------------------------------------------------------------

/**
 * Determine the ROHD context at the cursor position.
 *
 * Returns a set of active scopes: 'file', 'module', 'always', 'test'.
 */
function detectContext(
  document: vscode.TextDocument,
  position: vscode.Position,
): Set<string> {
  const textBefore = document.getText(
    new vscode.Range(new vscode.Position(0, 0), position),
  );

  const scopes = new Set<string>();

  // --- Pass 1: find brace positions for classes and functions ---

  const classPattern = /class\s+\w+(?:\s+extends\s+[^\{]+)?[^\{]*\{/g;
  let m: RegExpExecArray | null;
  const classBraces = new Set<number>();
  while ((m = classPattern.exec(textBefore)) !== null) {
    classBraces.add(m.index + m[0].length - 1);
  }

  const funcPattern = /(?:void|Future|int|bool|String|dynamic|var|final|async|static)\s+\w+\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?:async\s*)?\{/g;
  const funcBraces = new Set<number>();
  while ((m = funcPattern.exec(textBefore)) !== null) {
    funcBraces.add(m.index + m[0].length - 1);
  }

  // Also catch constructors: `ClassName(...)  : super(...) {` or `ClassName(...) {`
  const ctorPattern = /\b\w+\s*\([^)]*\)\s*(?::\s*super\([^)]*\)\s*)?\{/g;
  while ((m = ctorPattern.exec(textBefore)) !== null) {
    const bracePos = m.index + m[0].length - 1;
    if (!classBraces.has(bracePos)) {
      funcBraces.add(bracePos);
    }
  }

  // --- Pass 2: walk through text tracking brace depth + always detection ---

  let inString = false;
  let stringChar = '';

  interface BraceFrame { type: 'module' | 'function' | 'other' }
  const braceStack: BraceFrame[] = [];

  let parenDepth = 0;
  let alwaysParenDepth = -1;

  for (let i = 0; i < textBefore.length; i++) {
    const ch = textBefore[i];

    // String literals.
    if (inString) {
      if (ch === '\\') { i++; continue; }
      if (ch === stringChar) { inString = false; }
      continue;
    }
    if (ch === "'" || ch === '"') {
      inString = true;
      stringChar = ch;
      continue;
    }

    // Line comments.
    if (ch === '/' && i + 1 < textBefore.length && textBefore[i + 1] === '/') {
      i += 2;
      while (i < textBefore.length && textBefore[i] !== '\n') { i++; }
      continue;
    }

    // Block comments.
    if (ch === '/' && i + 1 < textBefore.length && textBefore[i + 1] === '*') {
      i += 2;
      while (i + 1 < textBefore.length &&
             !(textBefore[i] === '*' && textBefore[i + 1] === '/')) { i++; }
      i++;
      continue;
    }

    // Braces.
    if (ch === '{') {
      let type: 'module' | 'function' | 'other' = 'other';
      if (classBraces.has(i)) {
        type = 'module';
      } else if (funcBraces.has(i)) {
        type = 'function';
      }
      braceStack.push({ type });
    } else if (ch === '}') {
      if (braceStack.length > 0) {
        braceStack.pop();
      }
    }

    // Parentheses — track Combinational/Sequential.
    if (ch === '(') {
      const lookback = textBefore.substring(Math.max(0, i - 30), i);
      if (/(?:Combinational|Sequential)\s*$/.test(lookback)) {
        alwaysParenDepth = parenDepth;
      }
      parenDepth++;
    } else if (ch === ')') {
      parenDepth--;
      if (alwaysParenDepth >= 0 && parenDepth <= alwaysParenDepth) {
        alwaysParenDepth = -1;
      }
    }
  }

  // --- Determine scopes ---

  const insideModule = braceStack.some(f => f.type === 'module');
  const insideFunction = braceStack.some(f => f.type === 'function');
  const insideAlways = alwaysParenDepth >= 0 && insideFunction;

  if (insideAlways) { scopes.add('always'); }
  if (insideModule) { scopes.add('module'); }
  if (!insideFunction && !insideModule) { scopes.add('file'); }
  if (/(^|[\\/])test[\\/]/.test(document.uri.fsPath)) { scopes.add('test'); }

  return scopes;
}

interface EnclosingClassInfo {
  className: string;
  enumInsertionPosition: vscode.Position;
}

function findEnclosingClassInfo(
  document: vscode.TextDocument,
  position: vscode.Position,
): EnclosingClassInfo | undefined {
  const textBefore = document.getText(
    new vscode.Range(new vscode.Position(0, 0), position),
  );

  const classPattern = /class\s+(\w+)(?:\s+extends\s+[^\{]+)?[^\{]*\{/g;
  let match: RegExpExecArray | null;
  const classBraces = new Map<number, { className: string; classStart: number }>();
  while ((match = classPattern.exec(textBefore)) !== null) {
    classBraces.set(match.index + match[0].length - 1, {
      className: match[1],
      classStart: match.index,
    });
  }

  const funcPattern = /(?:void|Future|int|bool|String|dynamic|var|final|async|static)\s+\w+\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?:async\s*)?\{/g;
  const funcBraces = new Set<number>();
  while ((match = funcPattern.exec(textBefore)) !== null) {
    funcBraces.add(match.index + match[0].length - 1);
  }

  const ctorPattern = /\b\w+\s*\([^)]*\)\s*(?::\s*super\([^)]*\)\s*)?\{/g;
  while ((match = ctorPattern.exec(textBefore)) !== null) {
    const bracePos = match.index + match[0].length - 1;
    if (!classBraces.has(bracePos)) {
      funcBraces.add(bracePos);
    }
  }

  interface BraceFrame {
    type: 'class' | 'function' | 'other';
    className?: string;
    classStart?: number;
  }

  const braceStack: BraceFrame[] = [];
  let inString = false;
  let stringChar = '';

  for (let i = 0; i < textBefore.length; i++) {
    const ch = textBefore[i];

    if (inString) {
      if (ch === '\\') { i++; continue; }
      if (ch === stringChar) { inString = false; }
      continue;
    }
    if (ch === "'" || ch === '"') {
      inString = true;
      stringChar = ch;
      continue;
    }

    if (ch === '/' && i + 1 < textBefore.length && textBefore[i + 1] === '/') {
      i += 2;
      while (i < textBefore.length && textBefore[i] !== '\n') { i++; }
      continue;
    }

    if (ch === '/' && i + 1 < textBefore.length && textBefore[i + 1] === '*') {
      i += 2;
      while (i + 1 < textBefore.length &&
             !(textBefore[i] === '*' && textBefore[i + 1] === '/')) { i++; }
      i++;
      continue;
    }

    if (ch === '{') {
      const classInfo = classBraces.get(i);
      if (classInfo !== undefined) {
        braceStack.push({ type: 'class', ...classInfo });
      } else if (funcBraces.has(i)) {
        braceStack.push({ type: 'function' });
      } else {
        braceStack.push({ type: 'other' });
      }
    } else if (ch === '}') {
      braceStack.pop();
    }
  }

  const enclosingClass = [...braceStack].reverse()
    .find(frame => frame.type === 'class' &&
      frame.className !== undefined && frame.classStart !== undefined);
  if (enclosingClass?.className === undefined || enclosingClass.classStart === undefined) {
    return undefined;
  }

  let insertionLine = document.positionAt(enclosingClass.classStart).line;
  while (insertionLine > 0 && document.lineAt(insertionLine - 1).text.trim().startsWith('@')) {
    insertionLine--;
  }
  while (insertionLine > 0 && document.lineAt(insertionLine - 1).text.trim().startsWith('///')) {
    insertionLine--;
  }

  if (insertionLine > 0 && document.lineAt(insertionLine - 1).text.trim().endsWith('*/')) {
    insertionLine--;
    while (insertionLine > 0 && !document.lineAt(insertionLine).text.trim().startsWith('/**')) {
      insertionLine--;
    }
  }

  return {
    className: enclosingClass.className,
    enumInsertionPosition: new vscode.Position(insertionLine, 0),
  };
}

// ---------------------------------------------------------------------------
// Snippet definitions
// ---------------------------------------------------------------------------

interface SnippetDef {
  label: string;
  prefixes: string[];
  body: string;
  detail: string;
  documentation: string;
  sortOrder: string;
}

// ---- ALWAYS scope -------------------------------------------------------

const ALWAYS_SNIPPETS: SnippetDef[] = [
  {
    label: 'If (then/orElse)',
    prefixes: ['If', 'if'],
    body: [
      'If(',
      '\t${1:a}.gt(Const(0, width: ${1:a}.width)),',
      '\tthen: [',
      '\t\t${2:out} < ${1:a},',
      '\t],',
      '\torElse: [',
      '\t\t${2:out} < ${3:b},',
      '\t],',
      '),',
    ].join('\n'),
    detail: 'If(cond, then: [...], orElse: [...])',
    documentation: 'Inline conditional. Maps to if/else in SystemVerilog.',
    sortOrder: '0a',
  },
  {
    label: 'If (then only)',
    prefixes: ['If', 'if', 'ifthen'],
    body: [
      'If(',
      '\t${1:a}.gt(Const(0, width: ${1:a}.width)),',
      '\tthen: [',
      '\t\t${2:out} < ${1:a},',
      '\t],',
      '),',
    ].join('\n'),
    detail: 'If(cond, then: [...])',
    documentation: 'Simple conditional guard — no else branch.',
    sortOrder: '0b',
  },
  {
    label: 'If nested (then/orElse chain)',
    prefixes: ['If', 'if', 'ifnested', 'iforelse'],
    body: [
      'If(',
      '\t${1:a}.gt(Const(0, width: ${1:a}.width)),',
      '\tthen: [',
      '\t\t${4:out} < ${1:a},',
      '\t],',
      '\torElse: [',
      '\t\tIf(',
      '\t\t\t${2:b}.gt(Const(0, width: ${2:b}.width)),',
      '\t\t\tthen: [',
      '\t\t\t\t${4:out} < ${2:b},',
      '\t\t\t],',
      '\t\t\torElse: [',
      '\t\t\t\t${4:out} < Const(0, width: ${1:a}.width),',
      '\t\t\t],',
      '\t\t),',
      '\t],',
      '),',
    ].join('\n'),
    detail: 'If(a, ..., orElse: [If(b, ...)])',
    documentation: 'Nested if / else-if / else chain using orElse nesting.',
    sortOrder: '0c',
  },
  {
    label: 'If.block (Iff/ElseIf/Else)',
    prefixes: ['If.block', 'ifblock', 'IfBlock'],
    body: [
      'If.block([',
      '\tIff(${1:a}.gt(Const(0, width: ${1:a}.width)), [',
      '\t\t${4:out} < ${1:a},',
      '\t]),',
      '\tElseIf(${2:b}.gt(Const(0, width: ${2:b}.width)), [',
      '\t\t${4:out} < ${2:b},',
      '\t]),',
      '\tElse([',
      '\t\t${4:out} < Const(0, width: ${1:a}.width),',
      '\t]),',
      ']),',
    ].join('\n'),
    detail: 'If.block([Iff(...), ElseIf(...), Else(...)])',
    documentation: 'Flat if/else-if/else chain. First entry must be Iff (two f\'s).',
    sortOrder: '0d',
  },
  {
    label: 'If.block (Iff/Else only)',
    prefixes: ['If.block', 'ifblock', 'IfBlock'],
    body: [
      'If.block([',
      '\tIff(${1:a}.gt(Const(0, width: ${1:a}.width)), [',
      '\t\t${2:out} < ${1:a},',
      '\t]),',
      '\tElse([',
      '\t\t${2:out} < Const(0, width: ${1:a}.width),',
      '\t]),',
      ']),',
    ].join('\n'),
    detail: 'If.block([Iff(...), Else(...)])',
    documentation: 'Simple if/else using block style.',
    sortOrder: '0e',
  },
  {
    label: 'If.block (from Iff)',
    prefixes: ['Iff', 'iff'],
    body: [
      'If.block([',
      '\tIff(${1:a}.gt(Const(0, width: ${1:a}.width)), [',
      '\t\t${4:out} < ${1:a},',
      '\t]),',
      '\tElseIf(${2:b}.gt(Const(0, width: ${2:b}.width)), [',
      '\t\t${4:out} < ${2:b},',
      '\t]),',
      '\tElse([',
      '\t\t${4:out} < Const(0, width: ${1:a}.width),',
      '\t]),',
      ']),',
    ].join('\n'),
    detail: 'If.block([Iff(...), ElseIf(...), Else(...)])',
    documentation: 'Complete if/elseif/else block. Bare Iff is only valid inside If.block, so this prefix expands to the full valid construct.',
    sortOrder: '1a',
  },
  {
    label: 'Else',
    prefixes: ['Else', 'else'],
    body: 'Else([\n\t${1:out} < Const(0, width: ${2:a}.width),\n]),',
    detail: 'Else([...])',
    documentation: 'Final clause in an If.block chain.',
    sortOrder: '1c',
  },
  {
    label: 'Case',
    prefixes: ['Case', 'case'],
    body: 'Case(${1:a}.gt(Const(0, width: ${1:a}.width)), [\n\tCaseItem(Const(0), [\n\t\t${5:out} < Const(0, width: ${1:a}.width),\n\t]),\n\tCaseItem(Const(1), [\n\t\t${5:out} < ${1:a},\n\t]),\n], defaultItem: [\n\t${5:out} < ${2:b},\n], conditionalType: ConditionalType.${4|none,unique,priority|}\n),',
    detail: 'Case(expr, [CaseItem(...)], ...)',
    documentation: 'Case statement — maps to case/unique case/priority case in SystemVerilog.',
    sortOrder: '2a',
  },
  {
    label: 'CaseZ',
    prefixes: ['CaseZ', 'caseZ', 'casez'],
    body: 'CaseZ(${1:a}, [\n\tCaseItem(Const(LogicValue.ofString(\'${2:z1}\')), [\n\t\t${4:out} < ${1:a},\n\t]),\n\tCaseItem(Const(LogicValue.ofString(\'${3:10}\')), [\n\t\t${4:out} < ${5:b},\n\t]),\n], defaultItem: [\n\t${4:out} < Const(0, width: ${1:a}.width),\n], conditionalType: ConditionalType.${8|none,unique,priority|}\n),',
    detail: 'CaseZ(expr, [CaseItem(...)])',
    documentation: 'Like Case but with \'z\' don\'t-care matching.',
    sortOrder: '2b',
  },
  {
    label: 'CaseItem',
    prefixes: ['CaseItem', 'caseitem'],
    body: 'CaseItem(${1:value}, [\n\t${2:out} < ${3:result},\n]),',
    detail: 'CaseItem(value, [...])',
    documentation: 'A single arm inside a Case or CaseZ.',
    sortOrder: '2c',
  },
  {
    label: 'Conditional assign (<)',
    prefixes: ['assign'],
    body: '${1:out} < ${2:value},',
    detail: 'out < value',
    documentation: 'Conditional assignment using < operator.',
    sortOrder: '3a',
  },
];

// ---- MODULE scope -------------------------------------------------------

const MODULE_SNIPPETS: SnippetDef[] = [
  {
    label: 'Finite State Machine fallback (inside Module)',
    prefixes: ['FSMCurrent', 'fsmCurrent'],
    body: [
      '// Put this enum at file scope, outside this Module class:',
      '// /// FSM states for this module.',
      '// enum ${1:MyState} {',
      '//   /// Waiting for work.',
      '//   ${2:idle},',
      '//',
      '//   /// Processing an active transaction.',
      '//   ${3:active},',
      '//',
      '//   /// Completing the transaction.',
      '//   ${4:done},',
      '// }',
      'final ${6:states} = [',
      '\t// IDLE',
      '\tState(',
      '\t\t${1:MyState}.${2:idle},',
      '\t\tevents: {',
      '\t\t\t${7:a}.gt(Const(0, width: ${7:a}.width)): ${1:MyState}.${3:active},',
      '\t\t},',
      '\t\tactions: [',
      '\t\t\t${8:out} < Const(0, width: ${7:a}.width),',
      '\t\t],',
      '\t),',
      '\t// ACTIVE',
      '\tState(',
      '\t\t${1:MyState}.${3:active},',
      '\t\tevents: {',
      '\t\t\t${9:b}.gt(Const(0, width: ${9:b}.width)): ${1:MyState}.${4:done},',
      '\t\t},',
      '\t\tactions: [',
      '\t\t\t${8:out} < ${7:a},',
      '\t\t],',
      '\t),',
      '\t// DONE',
      '\tState(',
      '\t\t${1:MyState}.${4:done},',
      '\t\tevents: {',
      '\t\tConst(1): ${1:MyState}.${2:idle},',
      '\t\t},',
      '\t\tactions: [',
      '\t\t\t${8:out} < ${9:b},',
      '\t\t],',
      '\t),',
      '];',
      'FiniteStateMachine(${10:clk}, ${11:reset}, ${1:MyState}.${2:idle}, ${6:states});',
    ].join('\n'),
    detail: 'states + FiniteStateMachine for an existing Module',
    documentation: 'Fallback FSM logic for use inside an existing Module. Prefer the context-aware fsm completion, which inserts the enum before the enclosing class.',
    sortOrder: '0a',
  },
  {
    label: 'Pipeline',
    prefixes: ['Pipeline', 'pipeline', 'PIpeline', 'Pipe', 'pipe'],
    body: [
      'final ${1:pipeline} = Pipeline(',
      '\t${2:clk},',
      '\tstages: [',
      '\t\t(p) => [p.get(${3:a}) < p.get(${3:a}) + Const(1, width: ${3:a}.width)],',
      '\t\t(p) => [p.get(${3:a}) < p.get(${3:a}) + Const(1, width: ${3:a}.width)],',
      '\t],',
      '\treset: ${4:reset},',
      ');',
      '${5:out} <= ${1:pipeline}.get(${3:a});',
    ].join('\n'),
    detail: 'Pipeline(clk, stages: [(p) => [...], ...])',
    documentation: 'Pipelined logic — each stage is a `List<Conditional> Function(PipelineStageInfo p)`. Use `p.get(signal)` to access pipelined values. Stages use the same conditional syntax as Combinational.',
    sortOrder: '0b',
  },
  {
    label: 'ReadyValidPipeline',
    prefixes: ['ReadyValidPipeline', 'readyvalidpipeline', 'rvpipe', 'rvpipeline'],
    body: [
      'final ${3:validIn} = Logic(name: \'${3:validIn}\');',
      'final ${4:readyOut} = Logic(name: \'${4:readyOut}\');',
      'final ${8:validOut} = Logic(name: \'${8:validOut}\');',
      'final ${9:readyIn} = Logic(name: \'${9:readyIn}\');',
      '',
      'final ${1:rvPipeline} = ReadyValidPipeline(',
      '\t${2:clk},',
      '\t${3:validIn},',
      '\t${4:readyOut},',
      '\tstages: [',
      '\t\t(p) => [p.get(${5:a}) < p.get(${5:a}) + Const(1, width: ${5:a}.width)],',
      '\t\t(p) => [p.get(${5:a}) < p.get(${5:a}) + Const(1, width: ${5:a}.width)],',
      '\t],',
      '\treset: ${6:reset},',
      ');',
      '${7:out} <= ${1:rvPipeline}.get(${5:a});',
      '${8:validOut} <= ${1:rvPipeline}.validPipeOut;',
      '${9:readyIn} <= ${1:rvPipeline}.readyPipeIn;',
    ].join('\n'),
    detail: 'ReadyValidPipeline(clk, stages: [...], valid, ready)',
    documentation: 'Pipeline with ready/valid flow control. Same stage syntax as Pipeline, plus validPipeIn and readyPipeOut for backpressure.',
    sortOrder: '0c',
  },
  {
    label: 'Sequential',
    prefixes: ['Sequential', 'sequential', 'Seq', 'seq'],
    body: 'Sequential(${1:clk}, [\n\tIf(${2:a}.gt(Const(0, width: ${2:a}.width)), then: [\n\t\t${4:out} < ${2:a},\n\t], orElse: [\n\t\t${4:out} < ${3:b},\n\t]),\n]);',
    detail: 'Sequential(clk, [...])',
    documentation: 'always_ff block triggered on clock edge.',
    sortOrder: '0d',
  },
  {
    label: 'Combinational',
    prefixes: ['Combinational', 'combinational', 'Comb', 'comb'],
    body: 'Combinational([\n\t${1:out} < ${2:expression},\n]);',
    detail: 'Combinational([...])',
    documentation: 'always_comb block.',
    sortOrder: '0e',
  },
  {
    label: 'Continuous assign (<=)',
    prefixes: ['assign'],
    body: '${1:out} <= ${2:a};',
    detail: 'out <= a',
    documentation: 'Continuous assignment outside Combinational/Sequential.',
    sortOrder: '0f',
  },
];

// ---- FILE scope ---------------------------------------------------------

const FILE_SNIPPETS: SnippetDef[] = [
  {
    label: 'Finite State Machine (FSM)',
    prefixes: ['FSM', 'fsm'],
    body: [
      '/// FSM states for ${5:MyFSMModule}.',
      'enum ${1:MyState} {',
      '\t/// Waiting for work.',
      '\t${2:idle},',
      '',
      '\t/// Processing an active transaction.',
      '\t${3:active},',
      '',
      '\t/// Completing the transaction.',
      '\t${4:done},',
      '}',
      '',
      'class ${5:MyFSMModule} extends Module {',
      '\t${5:MyFSMModule}(Logic clk, Logic reset, Logic ${6:input})',
      '\t\t\t: super(name: \'${7:fsm_module}\') {',
      '\t\tclk = addInput(\'clk\', clk);',
      '\t\treset = addInput(\'reset\', reset);',
      '\t\t${6:input} = addInput(\'${6:input}\', ${6:input});',
      '',
      '\t\tfinal ${8:output} = addOutput(\'${8:output}\');',
      '',
      '\t\tfinal states = [',
      '\t\t\tState(${1:MyState}.${2:idle}, events: {',
      '\t\t\t\t${6:input}: ${1:MyState}.${3:active},',
      '\t\t\t}, actions: [',
      '\t\t\t\t${8:output} < 0,',
      '\t\t\t]),',
      '\t\t\tState(${1:MyState}.${3:active}, events: {',
      '\t\t\t\t${6:input}: ${1:MyState}.${4:done},',
      '\t\t\t}, actions: [',
      '\t\t\t\t${8:output} < 1,',
      '\t\t\t]),',
      '\t\t\tState(${1:MyState}.${4:done}, events: {',
      '\t\t\t\tConst(1): ${1:MyState}.${2:idle},',
      '\t\t\t}, actions: [',
      '\t\t\t\t${8:output} < 0,',
      '\t\t\t]),',
      '\t\t];',
      '',
      '\t\tFiniteStateMachine(clk, reset, ${1:MyState}.${2:idle}, states);',
      '\t}',
      '}',
    ].join('\n'),
    detail: 'enum + class extends Module with FiniteStateMachine',
    documentation: 'FSM scaffold — generates the enum and Module class at file scope.',
    sortOrder: '0a',
  },
  {
    label: 'Module',
    prefixes: ['Module', 'module', 'mod'],
    body: [
      '/// A ROHD module with two data inputs and one output.',
      'class ${1:MyModule} extends Module {',
      '\t/// The output of this module.',
      '\tLogic get ${2:out} => output(\'${2:out}\');',
      '',
      '\t/// The clock input.',
      '\tLogic get clk => input(\'clk\');',
      '',
      '\t/// The reset input.',
      '\tLogic get reset => input(\'reset\');',
      '',
      '\t/// The configured data depth.',
      '\tfinal int depth;',
      '',
      '\t/// Whether data should be latched.',
      '\tfinal bool latchData;',
      '',
      '\t/// Constructs a ${1:MyModule}.',
      '\t${1:MyModule}(',
      '\t\tLogic ${3:clk},',
      '\t\tLogic ${4:reset},',
      '\t\tLogic ${5:a},',
      '\t\tLogic ${6:b}, {',
      '\t\tthis.depth = ${7:1},',
      '\t\tthis.latchData = ${8:false},',
      '\t\tString? definitionName,',
      '\t\tsuper.name = \'${9:my_module}\',',
      '\t\tsuper.reserveName,',
      '\t\tsuper.reserveDefinitionName,',
      '\t}) : super(definitionName: definitionName ?? \'${1:MyModule}\') {',
      '\t\t// Register inputs and outputs of the module.',
      '\t\t${3:clk} = addInput(\'clk\', ${3:clk});',
      '\t\t${4:reset} = addInput(\'reset\', ${4:reset});',
      '\t\t${5:a} = addInput(\'${5:a}\', ${5:a}, width: ${5:a}.width);',
      '\t\t${6:b} = addInput(\'${6:b}\', ${6:b}, width: ${5:a}.width);',
      '\t\tfinal ${2:out} = addOutput(\'${2:out}\', width: ${5:a}.width);',
      '',
      '\t\t${2:out} <= ${5:a};',
      '\t}',
      '}',
    ].join('\n'),
    detail: 'class MyModule extends Module { ... }',
    documentation: 'ROHD Module scaffold with clk, reset, depth, latchData, addInput/addOutput, definitionName, and instance naming parameters.',
    sortOrder: '0b',
  },
  {
    label: 'Interface (enum + setPorts + clone)',
    prefixes: ['Interface', 'interface', 'intf'],
    body: [
      '/// Port directions for ${4:MyInterface}.',
      'enum ${1:MyDirection} {',
      '\t/// Ports entering the interface owner.',
      '\t${2:inward},',
      '',
      '\t/// Ports leaving the interface owner.',
      '\t${3:outward},',
      '}',
      '',
      'class ${4:MyInterface} extends Interface<${1:MyDirection}> {',
      '\tLogic get ${5:dataIn} => port(\'${5:dataIn}\');',
      '\tLogic get ${6:dataOut} => port(\'${6:dataOut}\');',
      '\tLogic get ${7:clk} => port(\'${7:clk}\');',
      '',
      '\tfinal int ${8:width};',
      '\t${4:MyInterface}({this.${8:width} = 8}) {',
      '\t\tsetPorts([',
      '\t\t\tLogic.port(\'${5:dataIn}\', ${8:width}),',
      '\t\t\tLogic.port(\'${7:clk}\'),',
      '\t\t], [',
      '\t\t\t${1:MyDirection}.${2:inward},',
      '\t\t]);',
      '',
      '\t\tsetPorts([',
      '\t\t\tLogic.port(\'${6:dataOut}\', ${8:width}),',
      '\t\t], [',
      '\t\t\t${1:MyDirection}.${3:outward},',
      '\t\t]);',
      '\t}',
      '',
      '\t@override',
      '\t${4:MyInterface} clone() => ${4:MyInterface}(${8:width}: ${8:width});',
      '}',
    ].join('\n'),
    detail: 'enum + class extends Interface<Dir> with clone()',
    documentation: 'Classic ROHD Interface with direction enum, setPorts grouping, port getters, and clone(). Use with Module.addInterfacePorts(intf, inputTags: {...}, outputTags: {...}).',
    sortOrder: '0c',
  },
  {
    label: 'PairInterface (provider/consumer)',
    prefixes: ['PairInterface', 'pairinterface', 'pairintf'],
    body: [
      'class ${1:MyPairInterface} extends PairInterface {',
      '\tLogic get ${2:clk} => port(\'${2:clk}\');',
      '\tLogic get ${3:req} => port(\'${3:req}\');',
      '\tLogic get ${4:rsp} => port(\'${4:rsp}\');',
      '',
      '\t${1:MyPairInterface}()',
      '\t\t\t: super(',
      '\t\t\t\t\tportsFromProvider: [Logic.port(\'${3:req}\')],',
      '\t\t\t\t\tportsFromConsumer: [Logic.port(\'${4:rsp}\')],',
      '\t\t\t\t\tsharedInputPorts: [Logic.port(\'${2:clk}\')],',
      '\t\t\t\t);',
      '',
      '\t@override',
      '\t${1:MyPairInterface} clone() => ${1:MyPairInterface}();',
      '}',
    ].join('\n'),
    detail: 'class extends PairInterface { ... clone() }',
    documentation: 'PairInterface with provider/consumer roles and shared inputs. Use with Module.addPairInterfacePorts(intf, PairRole.provider) or PairRole.consumer.',
    sortOrder: '0d',
  },
];

// ---- TEST directory scope -----------------------------------------------

const TEST_SNIPPETS: SnippetDef[] = [
  {
    label: 'test',
    prefixes: ['test', 'Test'],
    body: [
      'test(\'${1:description}\', () async {',
      '\texpect(${2:actual}, equals(${3:expected}));',
      '});',
    ].join('\n'),
    detail: 'test(\'description\', () async { ... })',
    documentation: 'Async package:test test case, common in ROHD and ROHD-HCL tests.',
    sortOrder: '0a',
  },
  {
    label: 'group',
    prefixes: ['group', 'Group'],
    body: [
      'group(\'${1:description}\', () {',
      '\ttest(\'${2:case}\', () async {',
      '\t\texpect(${3:actual}, equals(${4:expected}));',
      '\t});',
      '});',
    ].join('\n'),
    detail: 'group(\'description\', () { test(...) })',
    documentation: 'Package:test group with an async test inside.',
    sortOrder: '0b',
  },
  {
    label: 'ROHD tearDown reset',
    prefixes: ['tearDown', 'teardown', 'resetTest'],
    body: [
      'tearDown(() async {',
      '\tawait Simulator.reset();',
      '});',
    ].join('\n'),
    detail: 'tearDown(() async { await Simulator.reset(); })',
    documentation: 'Reset the ROHD simulator between tests.',
    sortOrder: '0c',
  },
  {
    label: 'ROHD simulation test',
    prefixes: ['rohdtest', 'simtest', 'testsim'],
    body: [
      'test(\'${1:module behavior}\', () async {',
      '\tfinal ${2:clk} = SimpleClockGenerator(10).clk;',
      '\tfinal ${3:reset} = Logic()..put(0);',
      '',
      '\tfinal ${4:dut} = ${5:MyModule}(${2:clk}, ${3:reset});',
      '\tawait ${4:dut}.build();',
      '',
      '\tunawaited(Simulator.run());',
      '',
      '\t${3:reset}.put(1);',
      '\tawait ${2:clk}.nextNegedge;',
      '\tawait ${2:clk}.nextNegedge;',
      '\t${3:reset}.put(0);',
      '\tawait ${2:clk}.nextNegedge;',
      '',
      '\texpect(${4:dut}.${6:out}.value.toInt(), equals(${7:0}));',
      '',
      '\tawait Simulator.endSimulation();',
      '});',
    ].join('\n'),
    detail: 'test(...) with SimpleClockGenerator, reset, build, Simulator.run()',
    documentation: 'ROHD simulation test scaffold based on common ROHD-HCL tests. Requires dart:async, rohd, and package:test imports.',
    sortOrder: '0d',
  },
];

// ---------------------------------------------------------------------------
// Build completion items
// ---------------------------------------------------------------------------

function buildItems(
  snippets: SnippetDef[],
  range?: vscode.Range,
  includeSnippet?: (snippet: SnippetDef) => boolean,
): vscode.CompletionItem[] {
  const items: vscode.CompletionItem[] = [];
  for (const snippet of snippets) {
    if (includeSnippet !== undefined && !includeSnippet(snippet)) {
      continue;
    }

    for (const prefix of snippet.prefixes) {
      const item = new vscode.CompletionItem(
        `ROHD: ${snippet.label}`,
        vscode.CompletionItemKind.Snippet,
      );
      item.detail = `${snippet.label}  —  ${snippet.detail}`;
      item.documentation = new vscode.MarkdownString(snippet.documentation);
      item.filterText = prefix;
      item.insertText = new vscode.SnippetString(snippet.body);
      item.range = range;
      item.sortText = `!${snippet.sortOrder}${prefix}`;
      item.preselect = true;
      items.push(item);
    }
  }
  return items;
}

const alwaysItems = buildItems(ALWAYS_SNIPPETS);
const moduleItems = buildItems(MODULE_SNIPPETS);
const fileItems = buildItems(FILE_SNIPPETS);
const testItems = buildItems(TEST_SNIPPETS);

const COMPLETION_TRIGGER_CHARACTERS = Array.from(new Set([
  ...ALWAYS_SNIPPETS,
  ...MODULE_SNIPPETS,
  ...FILE_SNIPPETS,
  ...TEST_SNIPPETS,
].flatMap(snippet => snippet.prefixes.map(prefix => prefix[0])))).concat('.');

function buildPipelineTypedItems(
  range: vscode.Range,
  readyValid: boolean,
  typedPrefix: string,
): vscode.CompletionItem[] {
  const snippet = MODULE_SNIPPETS.find(candidate =>
    candidate.label === (readyValid ? 'ReadyValidPipeline' : 'Pipeline'),
  );
  if (snippet === undefined) {
    return [];
  }

  const item = new vscode.CompletionItem(
    readyValid ? 'ROHD ReadyValidPipeline' : 'ROHD Pipeline',
    vscode.CompletionItemKind.Snippet,
  );
  item.detail = `ROHD ${snippet.label}  —  ${snippet.detail}`;
  item.documentation = new vscode.MarkdownString(snippet.documentation);
  item.filterText = typedPrefix;
  item.insertText = new vscode.SnippetString(snippet.body);
  item.range = range;
  item.sortText = '0000_rohd_pipeline';
  item.preselect = true;
  return [item];
}

function buildFsmInModuleItems(
  enclosingClass: EnclosingClassInfo,
): vscode.CompletionItem[] {
  const enumName = `${enclosingClass.className}State`;
  const enumText = [
    `/// FSM states for ${enclosingClass.className}.`,
    `enum ${enumName} {`,
    '  /// Waiting for work.',
    '  idle,',
    '',
    '  /// Processing an active transaction.',
    '  active,',
    '',
    '  /// Completing the transaction.',
    '  done,',
    '}',
    '',
  ].join('\n');
  const body = [
    'final ${2:states} = [',
    '\t// IDLE',
    '\tState(',
    `\t\t${enumName}.idle,`,
    '\t\tevents: {',
    `\t\t\t${'${3:a}'}.gt(Const(0, width: ${'${3:a}'}.width)): ${enumName}.active,`,
    '\t\t},',
    '\t\tactions: [',
    `\t\t\t${'${4:out}'} < Const(0, width: ${'${3:a}'}.width),`,
    '\t\t],',
    '\t),',
    '\t// ACTIVE',
    '\tState(',
    `\t\t${enumName}.active,`,
    '\t\tevents: {',
    `\t\t\t${'${5:b}'}.gt(Const(0, width: ${'${5:b}'}.width)): ${enumName}.done,`,
    '\t\t},',
    '\t\tactions: [',
    `\t\t\t${'${4:out}'} < ${'${3:a}'},`,
    '\t\t],',
    '\t),',
    '\t// DONE',
    '\tState(',
    `\t\t${enumName}.done,`,
    '\t\tevents: {',
    `\t\t\tConst(1): ${enumName}.idle,`,
    '\t\t},',
    '\t\tactions: [',
    `\t\t\t${'${4:out}'} < ${'${5:b}'},`,
    '\t\t],',
    '\t),',
    '];',
    `FiniteStateMachine(${'${6:clk}'}, ${'${7:reset}'}, ${enumName}.idle, ${'${2:states}'});`,
  ].join('\n');

  return ['FSM', 'fsm'].map(prefix => {
    const item = new vscode.CompletionItem(
      'ROHD: Finite State Machine (inside Module)',
      vscode.CompletionItemKind.Snippet,
    );
    item.detail = 'Finite State Machine (inside Module)  —  states + FiniteStateMachine for an existing Module';
    item.documentation = new vscode.MarkdownString(
      'FSM logic for use inside an existing Module. The enum is inserted before the enclosing class declaration.',
    );
    item.filterText = prefix;
    item.insertText = new vscode.SnippetString(body);
    item.additionalTextEdits = [
      vscode.TextEdit.insert(enclosingClass.enumInsertionPosition, enumText),
    ];
    item.sortText = `!0a${prefix}`;
    item.preselect = true;
    return item;
  });
}

function ifBlockTypedPrefixRange(
  document: vscode.TextDocument,
  position: vscode.Position,
): vscode.Range | undefined {
  const linePrefix = document.lineAt(position.line).text.substring(0, position.character);
  const match = /(?:If|if)\.(?:block)?$/.exec(linePrefix);
  if (match === null) {
    return undefined;
  }

  return new vscode.Range(
    new vscode.Position(position.line, position.character - match[0].length),
    position,
  );
}

function iffTypedPrefixRange(
  document: vscode.TextDocument,
  position: vscode.Position,
): vscode.Range | undefined {
  const linePrefix = document.lineAt(position.line).text.substring(0, position.character);
  const match = /(?:Iff|iff)$/.exec(linePrefix);
  if (match === null) {
    return undefined;
  }

  return new vscode.Range(
    new vscode.Position(position.line, position.character - match[0].length),
    position,
  );
}

function pipelineTypedPrefix(
  document: vscode.TextDocument,
  position: vscode.Position,
): { range: vscode.Range; readyValid: boolean; typedPrefix: string } | undefined {
  const linePrefix = document.lineAt(position.line).text.substring(0, position.character);
  const match = /(?:ReadyValidPipeline|readyvalidpipeline|rvpipeline|rvpipe|PIpeline|Pipeline|pipeline|Pipe|pipe)$/.exec(linePrefix);
  if (match === null) {
    return undefined;
  }

  return {
    range: new vscode.Range(
      new vscode.Position(position.line, position.character - match[0].length),
      position,
    ),
    readyValid: /^(?:ReadyValidPipeline|readyvalidpipeline|rvpipeline|rvpipe)$/.test(match[0]),
    typedPrefix: match[0],
  };
}

// ---------------------------------------------------------------------------
// Completion provider
// ---------------------------------------------------------------------------

class RohdContextCompletionProvider
  implements vscode.CompletionItemProvider
{
  provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position,
    _token: vscode.CancellationToken,
    _context: vscode.CompletionContext,
  ): vscode.CompletionItem[] | undefined {
    const scopes = detectContext(document, position);
    const items: vscode.CompletionItem[] = [];

    const ifBlockRange = ifBlockTypedPrefixRange(document, position);
    if (ifBlockRange !== undefined && scopes.has('always')) {
      return buildItems(
        ALWAYS_SNIPPETS,
        ifBlockRange,
        snippet => snippet.prefixes.some(prefix =>
          prefix === 'If.block' || prefix === 'ifblock' || prefix === 'IfBlock',
        ),
      );
    }

    const iffRange = iffTypedPrefixRange(document, position);
    if (iffRange !== undefined && scopes.has('always')) {
      return buildItems(
        ALWAYS_SNIPPETS,
        iffRange,
        snippet => snippet.label === 'If.block (from Iff)',
      );
    }

    const pipelinePrefix = pipelineTypedPrefix(document, position);
    if (pipelinePrefix !== undefined && scopes.has('module')) {
      return buildPipelineTypedItems(
        pipelinePrefix.range,
        pipelinePrefix.readyValid,
        pipelinePrefix.typedPrefix,
      );
    }

    if (scopes.has('always')) { items.push(...alwaysItems); }
    if (scopes.has('module')) {
      const enclosingClass = findEnclosingClassInfo(document, position);
      if (enclosingClass !== undefined) {
        items.push(...buildFsmInModuleItems(enclosingClass));
      }
      items.push(...moduleItems.filter(item => item.label !== 'ROHD: Finite State Machine (inside Module)'));
    }
    if (scopes.has('file'))   { items.push(...fileItems); }
    if (scopes.has('test'))   { items.push(...testItems); }

    return items.length > 0 ? items : undefined;
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function activate(_context: vscode.ExtensionContext): vscode.Disposable {
  const provider = new RohdContextCompletionProvider();

  return vscode.languages.registerCompletionItemProvider(
    { language: 'dart', scheme: 'file' },
    provider,
    ...COMPLETION_TRIGGER_CHARACTERS,
  );
}
