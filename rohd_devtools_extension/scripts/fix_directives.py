#!/usr/bin/env python3
"""Fix directive ordering in Dart files."""

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

def get_dart_files():
    """Get all Dart files in the lib and test dirs."""
    result = subprocess.run(
        ["find", ".", "-name", "*.dart", "-type", "f"],
        capture_output=True, text=True, cwd="."
    )
    return [f for f in result.stdout.strip().split('\n') if f and not 'build' in f]

def parse_directives(content):
    """Parse import/export directives and return (directives, rest_of_code)."""
    lines = content.split('\n')
    directives = []
    other_lines = []
    in_directives = True
    
    for line in lines:
        if in_directives:
            # Check if line is a directive
            if re.match(r'^\s*(import|export|library|part)\s', line):
                directives.append(line)
            elif line.strip() == '' or line.strip().startswith('//'):
                # Skip empty lines and comments at the top
                if other_lines or not directives:
                    other_lines.append(line)
            else:
                in_directives = False
                other_lines.append(line)
        else:
            other_lines.append(line)
    
    return directives, other_lines

def sort_directives(directives):
    """Sort directives: dart: first, then package:, then relative."""
    dart_imports = []
    package_imports = []
    relative_imports = []
    
    for d in directives:
        if "import 'dart:" in d or 'import "dart:' in d:
            dart_imports.append(d)
        elif "import 'package:" in d or 'import "package:' in d:
            package_imports.append(d)
        elif "export 'dart:" in d or 'export "dart:' in d:
            dart_imports.append(d)
        elif "export 'package:" in d or 'export "package:' in d:
            package_imports.append(d)
        else:
            relative_imports.append(d)
    
    # Sort each section alphabetically
    dart_imports.sort()
    package_imports.sort()
    relative_imports.sort()
    
    return dart_imports + package_imports + relative_imports

def fix_file(filepath):
    """Fix directive ordering in a single file."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
    except:
        return False
    
    directives, other_lines = parse_directives(content)
    if not directives:
        return False
    
    sorted_dirs = sort_directives(directives)
    if sorted_dirs == directives:
        return False
    
    new_content = '\n'.join(sorted_dirs) + '\n' + '\n'.join(other_lines)
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    
    return True

def main():
    files = get_dart_files()
    fixed_count = 0
    
    for filepath in files:
        if fix_file(filepath):
            fixed_count += 1
            print(f"  Fixed {filepath}")
    
    print(f"\nFixed {fixed_count} file(s)")

if __name__ == '__main__':
    main()
