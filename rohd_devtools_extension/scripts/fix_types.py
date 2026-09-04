#!/usr/bin/env python3
"""Remove obvious local variable type annotations in Dart files."""

import re
import subprocess
from pathlib import Path

def get_dart_files():
    """Get all Dart files."""
    result = subprocess.run(
        ["find", "lib", "test", "-name", "*.dart", "-type", "f"],
        capture_output=True, text=True, cwd="."
    )
    return [f for f in result.stdout.strip().split('\n') if f]

def remove_obvious_types(content):
    """Remove type annotations from local variables where type is obvious from RHS."""
    # Pattern: final Type varName = ...; or var Type varName = ...;
    # Common obvious patterns:
    #  - final String x = "..."; → final x = "...";
    #  - final int x = 123; → final x = 123;
    #  - final bool x = true; → final x = true;
    #  - final List<X> x = [...]; → final x = [...];
    #  - final Map<K,V> x = {...}; → final x = {...};
    #  - final SomeClass x = SomeClass(...); → final x = SomeClass(...);
    
    # Patterns to match obvious assignments
    patterns = [
        # String literal
        (r'\bfinal\s+String\s+(\w+)\s*=\s*["\']', r'final \1 = "'),
        # Boolean
        (r'\bfinal\s+bool\s+(\w+)\s*=\s*(true|false)', r'final \1 = \2'),
        # Integer
        (r'\bfinal\s+int\s+(\w+)\s*=\s*(-?\d+)', r'final \1 = \2'),
        # Double
        (r'\bfinal\s+double\s+(\w+)\s*=\s*(-?\d+\.\d+)', r'final \1 = \2'),
        # List literal
        (r'\bfinal\s+List<[^>]+>\s+(\w+)\s*=\s*\[', r'final \1 = ['),
        # Map literal
        (r'\bfinal\s+Map<[^>]+>\s+(\w+)\s*=\s*\{', r'final \1 = {'),
        # Method call on obvious type
        (r'\bvar\s+(\w+)\s*=\s*(\w+)\.(\w+)\(', r'var \1 = \2.\3('),
    ]
    
    modified = content
    for pattern, replacement in patterns:
        modified = re.sub(pattern, replacement, modified)
    
    return modified

def fix_file(filepath):
    """Fix obvious type annotations in a single file."""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
    except:
        return False
    
    new_content = remove_obvious_types(content)
    if new_content == content:
        return False
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    return True

def main():
    files = get_dart_files()
    fixed_count = 0
    
    for filepath in files:
        if fix_file(filepath):
            fixed_count += 1
            print(f"  {filepath}")
    
    print(f"\nFixed {fixed_count} file(s)")

if __name__ == '__main__':
    main()
