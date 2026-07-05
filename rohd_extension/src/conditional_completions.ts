/* ---------------------------------------------------------------------------
 * Copyright (C) 2026 Intel Corporation.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * conditional_completions.ts
 * Context-aware CompletionItemProvider for ROHD constructs.
 *
 * Three scopes:
 *
 * 1. FILE SCOPE — FSM (enum + class extends Module), Module scaffold
 *    only appear at file/top level, not inside a function like main().
 *
 * 2. MODULE BODY — Pipeline, Sequential, Combinational appear when the
 *    cursor is inside a class that extends Module.
 *
 * 3. INSIDE _ALWAYS — If, If.block, Iff, ElseIf, Else, Case, CaseZ,
 *    CaseItem, and conditional assignment (<) only appear when the
 *    cursor is inside a Combinational or Sequential block.
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
 * Returns a set of active scopes: 'file', 'module', 'always'.
 */
function detectContext(
  document: vscode.TextDocument,
  position: vscode.Position,
): Set<string> {
  const textBefore = document.getText(
    new vscode.Range(new vscode.Position(0, 0), position),
  );

  const scopes = new Set<string>();

  // --- Pass 1: find brace positions for class-extends-Module and functions ---

  const classModulePattern = /class\s+\w+\s+extends\s+\w*Module\w*[^{]*\{/g;
  let m: RegExpExecArray | null;
  const classModuleBraces = new Set<number>();
  while ((m = classModulePattern.exec(textBefore)) !== null) {
    classModuleBraces.add(m.index + m[0].length - 1);
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
    if (!classModuleBraces.has(bracePos)) {
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
      if (classModuleBraces.has(i)) {
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

  const insideAlways = alwaysParenDepth >= 0;
  const insideModule = braceStack.some(f => f.type === 'module');
  const insideFunction = braceStack.some(f => f.type === 'function');

  if (insideAlways) { scopes.add('always'); }
  if (insideModule) { scopes.add('module'); }
  if (!insideFunction && !insideModule) { scopes.add('file'); }

  return scopes;
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
    body: 'If(${1:condition}, then: [\n\t${2:out} < ${3:value},\n], orElse: [\n\t${2:out} < ${4:defaultValue},\n]),',
    detail: 'If(cond, then: [...], orElse: [...])',
    documentation: 'Inline conditional. Maps to if/else in SystemVerilog.',
    sortOrder: '0a',
  },
  {
    label: 'If (then only)',
    prefixes: ['If', 'if', 'ifthen'],
    body: 'If(${1:condition}, then: [\n\t${2:out} < ${3:value},\n]),',
    detail: 'If(cond, then: [...])',
    documentation: 'Simple conditional guard — no else branch.',
    sortOrder: '0b',
  },
  {
    label: 'If nested (then/orElse chain)',
    prefixes: ['If', 'if', 'ifnested', 'iforelse'],
    body: 'If(${1:condA}, then: [\n\t${4:out} < ${5:valueA},\n], orElse: [If(${2:condB}, then: [\n\t${4:out} < ${6:valueB},\n], orElse: [\n\t${4:out} < ${7:defaultValue},\n])]),',
    detail: 'If(a, ..., orElse: [If(b, ...)])',
    documentation: 'Nested if / else-if / else chain using orElse nesting.',
    sortOrder: '0c',
  },
  {
    label: 'If.block (Iff/ElseIf/Else)',
    prefixes: ['If.block', 'ifblock', 'IfBlock'],
    body: 'If.block([\n\tIff(${1:condition}, [\n\t\t${4:out} < ${5:valueA},\n\t]),\n\tElseIf(${2:condition}, [\n\t\t${4:out} < ${6:valueB},\n\t]),\n\tElse([\n\t\t${4:out} < ${7:defaultValue},\n\t]),\n]),',
    detail: 'If.block([Iff(...), ElseIf(...), Else(...)])',
    documentation: 'Flat if/else-if/else chain. First entry must be Iff (two f\'s).',
    sortOrder: '0d',
  },
  {
    label: 'If.block (Iff/Else only)',
    prefixes: ['If.block', 'ifblock', 'IfBlock'],
    body: 'If.block([\n\tIff(${1:condition}, [\n\t\t${2:out} < ${3:value},\n\t]),\n\tElse([\n\t\t${2:out} < ${4:defaultValue},\n\t]),\n]),',
    detail: 'If.block([Iff(...), Else(...)])',
    documentation: 'Simple if/else using block style.',
    sortOrder: '0e',
  },
  {
    label: 'Iff (first clause in If.block)',
    prefixes: ['Iff', 'iff'],
    body: 'Iff(${1:condition}, [\n\t${2:out} < ${3:value},\n]),',
    detail: 'Iff(cond, [...])',
    documentation: 'First clause in an If.block chain. Note: two f\'s.',
    sortOrder: '1a',
  },
  {
    label: 'ElseIf',
    prefixes: ['ElseIf', 'elseif', 'elif'],
    body: 'ElseIf(${1:condition}, [\n\t${2:out} < ${3:value},\n]),',
    detail: 'ElseIf(cond, [...])',
    documentation: 'Middle clause in an If.block chain.',
    sortOrder: '1b',
  },
  {
    label: 'Else',
    prefixes: ['Else', 'else'],
    body: 'Else([\n\t${1:out} < ${2:value},\n]),',
    detail: 'Else([...])',
    documentation: 'Final clause in an If.block chain.',
    sortOrder: '1c',
  },
  {
    label: 'Case',
    prefixes: ['Case', 'case'],
    body: 'Case(${1:expression}, [\n\tCaseItem(${2:value1}, [\n\t\t${5:out} < ${6:result1},\n\t]),\n\tCaseItem(${3:value2}, [\n\t\t${5:out} < ${7:result2},\n\t]),\n], defaultItem: [\n\t${5:out} < ${8:defaultResult},\n], conditionalType: ConditionalType.${4|none,unique,priority|}\n),',
    detail: 'Case(expr, [CaseItem(...)], ...)',
    documentation: 'Case statement — maps to case/unique case/priority case in SystemVerilog.',
    sortOrder: '2a',
  },
  {
    label: 'CaseZ',
    prefixes: ['CaseZ', 'caseZ', 'casez'],
    body: 'CaseZ(${1:expression}, [\n\tCaseItem(Const(LogicValue.ofString(\'${2:z1}\')), [\n\t\t${4:out} < ${5:result1},\n\t]),\n\tCaseItem(Const(LogicValue.ofString(\'${3:10}\')), [\n\t\t${4:out} < ${6:result2},\n\t]),\n], defaultItem: [\n\t${4:out} < ${7:defaultResult},\n], conditionalType: ConditionalType.${8|none,unique,priority|}\n),',
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
    label: 'Pipeline',
    prefixes: ['Pipeline', 'pipeline', 'pipe'],
    body: 'final ${1:pipeline} = Pipeline(${2:clk},\n\tstages: [\n\t\t(p) => [p.get(${3:a}) < p.get(${3:a}) + 1],\n\t\t(p) => [p.get(${3:a}) < p.get(${3:a}) + 1],\n\t],\n\t${4:reset: reset,}\n);\n${5:out} <= ${1:pipeline}.get(${3:a});',
    detail: 'Pipeline(clk, stages: [(p) => [...], ...])',
    documentation: 'Pipelined logic — each stage is a `List<Conditional> Function(PipelineStageInfo p)`. Use `p.get(signal)` to access pipelined values. Stages use the same conditional syntax as Combinational.',
    sortOrder: '0a',
  },
  {
    label: 'ReadyValidPipeline',
    prefixes: ['ReadyValidPipeline', 'rvpipe', 'rvpipeline'],
    body: 'final ${1:pipeline} = ReadyValidPipeline(${2:clk},\n\tstages: [\n\t\t(p) => [p.get(${3:a}) < p.get(${3:a}) + 1],\n\t\t(p) => [p.get(${3:a}) < p.get(${3:a}) + 1],\n\t],\n\tvalidPipeIn: ${4:validIn},\n\treadyPipeOut: ${5:readyOut},\n);\n${6:out} <= ${1:pipeline}.get(${3:a});',
    detail: 'ReadyValidPipeline(clk, stages: [...], valid, ready)',
    documentation: 'Pipeline with ready/valid flow control. Same stage syntax as Pipeline, plus validPipeIn and readyPipeOut for backpressure.',
    sortOrder: '0b',
  },
  {
    label: 'Sequential',
    prefixes: ['Sequential', 'sequential', 'seq'],
    body: 'Sequential(${1:clk}, [\n\tIf(${2:reset}, then: [\n\t\t${3:out} < 0,\n\t], orElse: [\n\t\t${3:out} < ${4:nextVal},\n\t]),\n]);',
    detail: 'Sequential(clk, [...])',
    documentation: 'always_ff block triggered on clock edge.',
    sortOrder: '0c',
  },
  {
    label: 'Combinational',
    prefixes: ['Combinational', 'combinational', 'comb'],
    body: 'Combinational([\n\t${1:out} < ${2:expression},\n]);',
    detail: 'Combinational([...])',
    documentation: 'always_comb block.',
    sortOrder: '0d',
  },
];

// ---- FILE scope ---------------------------------------------------------

const FILE_SNIPPETS: SnippetDef[] = [
  {
    label: 'Finite State Machine (FSM)',
    prefixes: ['FSM', 'fsm'],
    body: [
      'enum ${1:MyState} { ${2:idle}, ${3:active}, ${4:done} }',
      '',
      'class ${5:MyFSMModule} extends Module {',
      '\tlate FiniteStateMachine<${1:MyState}> _fsm;',
      '',
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
      '\t\t_fsm = FiniteStateMachine(clk, reset, ${1:MyState}.${2:idle}, states);',
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
      'class ${1:MyModule} extends Module {',
      '\tLogic get ${2:out} => output(\'${2:out}\');',
      '',
      '\t${1:MyModule}(Logic ${3:a}, {super.name = \'${4:my_module}\'}) {',
      '\t\t${3:a} = addInput(\'${3:a}\', ${3:a}, width: ${3:a}.width);',
      '\t\tfinal ${2:out} = addOutput(\'${2:out}\', width: ${3:a}.width);',
      '',
      '\t\t${2:out} <= ${3:a};',
      '\t}',
      '}',
    ].join('\n'),
    detail: 'class MyModule extends Module { ... }',
    documentation: 'ROHD Module scaffold with addInput/addOutput.',
    sortOrder: '0b',
  },
  {
    label: 'Interface (enum + setPorts + clone)',
    prefixes: ['Interface', 'interface', 'intf'],
    body: [
      'enum ${1:MyDirection} { ${2:inward}, ${3:outward} }',
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
      '\t${1:MyPairInterface}.clone(${1:MyPairInterface} super.otherInterface)',
      '\t\t\t: super.clone();',
      '}',
    ].join('\n'),
    detail: 'class extends PairInterface { ... clone() }',
    documentation: 'PairInterface with provider/consumer roles and shared inputs. Use with Module.addPairInterfacePorts(intf, PairRole.provider) or PairRole.consumer.',
    sortOrder: '0d',
  },
];

// ---------------------------------------------------------------------------
// Build completion items
// ---------------------------------------------------------------------------

function buildItems(snippets: SnippetDef[]): vscode.CompletionItem[] {
  const items: vscode.CompletionItem[] = [];
  for (const snippet of snippets) {
    for (const prefix of snippet.prefixes) {
      const item = new vscode.CompletionItem(
        prefix,
        vscode.CompletionItemKind.Snippet,
      );
      item.detail = `${snippet.label}  —  ${snippet.detail}`;
      item.documentation = new vscode.MarkdownString(snippet.documentation);
      item.insertText = new vscode.SnippetString(snippet.body);
      item.sortText = snippet.sortOrder + prefix;
      items.push(item);
    }
  }
  return items;
}

const alwaysItems = buildItems(ALWAYS_SNIPPETS);
const moduleItems = buildItems(MODULE_SNIPPETS);
const fileItems = buildItems(FILE_SNIPPETS);

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

    if (scopes.has('always')) { items.push(...alwaysItems); }
    if (scopes.has('module')) { items.push(...moduleItems); }
    if (scopes.has('file'))   { items.push(...fileItems); }

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
    'I', 'i', 'E', 'e', 'C', 'c', 'S', 's',
    'P', 'p', 'R', 'r', 'F', 'f', 'M', 'm', 'a',
  );
}
