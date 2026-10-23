#!/usr/bin/env python3
"""Auto-fix common Dart lint violations.

Parses `dart analyze --format machine` output and applies mechanical
fixes for the following lint rules:

  * ALWAYS_PUT_CONTROL_BODY_ON_NEW_LINE — move body to next line
  * CURLY_BRACES_IN_FLOW_CONTROL_STRUCTURES — wrap body in { }
  * NOOP_PRIMITIVE_OPERATIONS — remove redundant .toString()
  * AVOID_TYPES_ON_CLOSURE_PARAMETERS — strip type annotations

Usage:
    python3 scripts/fix_control_body_newline.py [--dry-run] [file ...]

When file paths are given on the command line, only violations inside
those files are fixed.  Otherwise the entire package is scanned.
"""

import re
import subprocess
import sys
from collections import defaultdict

SUPPORTED_LINTS = {
    "ALWAYS_PUT_CONTROL_BODY_ON_NEW_LINE",
    "CURLY_BRACES_IN_FLOW_CONTROL_STRUCTURES",
    "NOOP_PRIMITIVE_OPERATIONS",
    "AVOID_TYPES_ON_CLOSURE_PARAMETERS",
}

DRY_RUN = "--dry-run" in sys.argv


def run_dart_analyze(target_files=None):
    """Run `dart analyze` and collect violations for supported lint rules."""
    cmd = ["dart", "analyze", "--format", "machine"]
    if target_files:
        cmd.extend(target_files)
    result = subprocess.run(cmd, capture_output=True, text=True)
    # machine format: SEVERITY|TYPE|LINT_CODE|FILE|LINE|COL|LEN|MESSAGE
    violations = defaultdict(list)
    for line in result.stderr.splitlines() + result.stdout.splitlines():
        parts = line.split("|")
        if len(parts) >= 8 and parts[2] in SUPPORTED_LINTS:
            filepath = parts[3]
            lineno = int(parts[4])
            col = int(parts[5])
            length = int(parts[6])
            code = parts[2]
            violations[filepath].append((lineno, col, length, code))
    return violations


# ── Per-rule fixers ──────────────────────────────────────────────────

def _fix_control_body_newline(lines, idx, col, _length):
    """Move inline control body to the next line."""
    rstripped = lines[idx].rstrip("\n").rstrip("\r")
    body_start = col - 1
    if body_start <= 0 or body_start >= len(rstripped):
        return False
    control_part = rstripped[:body_start].rstrip()
    body_part = rstripped[body_start:].strip()
    if not body_part:
        return False
    indent = len(rstripped) - len(rstripped.lstrip())
    new_indent = " " * (indent + 2)
    lines[idx] = control_part + "\n" + new_indent + body_part + "\n"
    return True


def _fix_curly_braces(lines, idx, _col, _length):
    """Wrap a bare control-flow body in curly braces.

    The analyzer flags the *body* line (not the keyword line).  We look
    at the previous line for the control keyword, or at the current line
    for an inline form like ``if (cond) return foo;``.
    """
    _KW = r'if\s*\(.*\)|else\s+if\s*\(.*\)|else|for\s*\(.*\)|while\s*\(.*\)'

    rstripped = lines[idx].rstrip("\n").rstrip("\r")
    stripped = rstripped.lstrip()

    # ── Case 1: the flagged line IS the body; keyword is on prev line ──
    if idx > 0:
        prev = lines[idx - 1].rstrip("\n").rstrip("\r")
        m = re.match(rf'^(\s*)({_KW})\s*$', prev)
        if m and not stripped.startswith("{"):
            indent = m.group(1)
            keyword = m.group(2)
            body_stripped = stripped
            body_indent = " " * (len(indent) + 2)
            lines[idx - 1] = f"{indent}{keyword} {{\n"
            lines[idx] = f"{body_indent}{body_stripped}\n{indent}}}\n"
            return True

    # ── Case 2: inline form on one line ``if (cond) return foo;`` ──
    m2 = re.match(rf'^(\s*)({_KW})\s+(.+)$', rstripped)
    if m2:
        indent = m2.group(1)
        keyword = m2.group(2)
        body = m2.group(3).strip()
        if body.startswith("{"):
            return False
        body_indent = " " * (len(indent) + 2)
        lines[idx] = (
            f"{indent}{keyword} {{\n"
            f"{body_indent}{body}\n"
            f"{indent}}}\n"
        )
        return True

    return False


def _fix_noop_primitive(lines, idx, col, length):
    """Remove redundant `.toString()` calls flagged by the analyzer."""
    line = lines[idx]
    # The analyzer points at the `.toString` portion (col is 1-based).
    start = col - 1
    end = start + length
    # Match `.toString()` right at the flagged position.
    snippet = line[start:]
    if snippet.startswith("toString"):
        # Walk backwards to find the dot.
        dot_pos = start - 1
        if dot_pos >= 0 and line[dot_pos] == ".":
            # Find the closing paren.
            paren_end = start + len("toString")
            rest = line[paren_end:]
            if rest.startswith("()"):
                # Remove `.toString()`
                before = line[:dot_pos]
                after = line[paren_end + 2 :]
                lines[idx] = before + after
                return True
    return False


def _fix_avoid_types_on_closure(lines, idx, col, length):
    """Remove type annotations from closure parameters.

    The analyzer flags the type keyword at (line, col, length).
    We remove the type and the trailing space(s).
    """
    line = lines[idx]
    start = col - 1
    end = start + length
    # Remove the type annotation and any trailing whitespace.
    before = line[:start]
    after = line[end:].lstrip(" ")
    lines[idx] = before + after
    return True


FIXERS = {
    "ALWAYS_PUT_CONTROL_BODY_ON_NEW_LINE": _fix_control_body_newline,
    "CURLY_BRACES_IN_FLOW_CONTROL_STRUCTURES": _fix_curly_braces,
    "NOOP_PRIMITIVE_OPERATIONS": _fix_noop_primitive,
    "AVOID_TYPES_ON_CLOSURE_PARAMETERS": _fix_avoid_types_on_closure,
}


# ── Main logic ───────────────────────────────────────────────────────

def fix_file(filepath, line_infos):
    """Fix all violations in a single file.

    Works bottom-up (highest line numbers first) so earlier edits
    don't shift line numbers for later edits.
    """
    with open(filepath, "r") as f:
        lines = f.readlines()

    # Sort by line number descending so inserts don't shift indices.
    line_infos.sort(key=lambda x: x[0], reverse=True)

    fixed = 0
    for lineno, col, length, code in line_infos:
        idx = lineno - 1  # 0-based
        if idx < 0 or idx >= len(lines):
            continue
        fixer = FIXERS.get(code)
        if fixer and fixer(lines, idx, col, length):
            fixed += 1

    if fixed > 0:
        if DRY_RUN:
            print(f"  [dry-run] Would fix {fixed} violation(s) in {filepath}")
        else:
            with open(filepath, "w") as f:
                f.writelines(lines)
            print(f"  Fixed {fixed} violation(s) in {filepath}")
    return fixed


def main():
    if DRY_RUN:
        print("=== DRY RUN (no files will be modified) ===\n")

    # Collect explicit file paths (skip flags).
    target_files = [a for a in sys.argv[1:] if not a.startswith("--")]

    print("Running dart analyze...")
    violations = run_dart_analyze(target_files or None)

    if not violations:
        print("No supported lint violations found.")
        return

    total_violations = sum(len(v) for v in violations.values())
    print(f"Found {total_violations} violation(s) in {len(violations)} file(s).\n")

    total_fixed = 0
    for filepath, line_infos in sorted(violations.items()):
        total_fixed += fix_file(filepath, line_infos)

    print(f"\n{'Would fix' if DRY_RUN else 'Fixed'} {total_fixed} total violation(s).")

    if not DRY_RUN and total_fixed > 0:
        print("\nRe-running dart analyze to verify...")
        violations2 = run_dart_analyze(target_files or None)
        remaining = sum(len(v) for v in violations2.values())
        if remaining == 0:
            print("All supported lint violations resolved!")
        else:
            print(f"{remaining} violation(s) remain — may need manual review.")


if __name__ == "__main__":
    main()
