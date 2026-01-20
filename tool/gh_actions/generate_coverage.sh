#!/bin/bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# generate_coverage.sh
# Generate code coverage and SVG badge
#
# 2026 January 20
# Author: Maifee Ul Asad<maifeeulasad@gmail.com>

set -euo pipefail

# Remove old coverage data
rm -rf coverage

# Run tests with coverage
dart test --coverage=coverage || true

# Check if coverage was generated
if [ ! -d "coverage" ]; then
    echo "Error: Coverage directory not created"
    exit 1
fi

# Format to LCOV
dart run coverage:format_coverage \
    --lcov \
    --in=coverage \
    --out=coverage/lcov.info \
    --packages=.dart_tool/package_config.json \
    --report-on=lib

# Install lcov if needed
if ! command -v lcov &> /dev/null; then
    if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
        sudo apt update -y
        sudo apt install -y lcov
    fi
fi

# Extract coverage percentage
if command -v lcov &> /dev/null; then
    SUMMARY=$(lcov --summary coverage/lcov.info 2>&1 | grep -E "lines\.*:")
    PERCENT=$(echo "$SUMMARY" | grep -oP '\d+\.\d+' | head -1)
    echo "Coverage: ${PERCENT}%"
else
    PERCENT="0.0"
    echo "Coverage: 0.0%"
fi

# Determine color
if (( $(echo "$PERCENT >= 90" | bc -l) )); then
    COLOR="#4c1"      # bright green
elif (( $(echo "$PERCENT >= 80" | bc -l) )); then
    COLOR="#97ca00"   # green
elif (( $(echo "$PERCENT >= 70" | bc -l) )); then
    COLOR="#dfb317"   # yellow
elif (( $(echo "$PERCENT >= 60" | bc -l) )); then
    COLOR="#fe7d37"   # orange
else
    COLOR="#e05d44"   # red
fi

# Calculate dimensions
TEXT="${PERCENT}%"
TEXT_LEN=${#TEXT}
TEXT_WIDTH=$((TEXT_LEN * 63))
LABEL_WIDTH=63
VALUE_WIDTH=$((TEXT_WIDTH / 10 + 10))
TOTAL_WIDTH=$((LABEL_WIDTH + VALUE_WIDTH))

# Generate SVG badge
# Style credit goes to shields.io
cat > /tmp/coverage-badge.svg << EOFSVG
<svg xmlns="http://www.w3.org/2000/svg" width="${TOTAL_WIDTH}" height="20" role="img" aria-label="coverage: ${TEXT}">
    <title>coverage: ${TEXT}</title>
    <linearGradient id="s" x2="0" y2="100%">
        <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
        <stop offset="1" stop-opacity=".1"/>
    </linearGradient>
    <clipPath id="r">
        <rect width="${TOTAL_WIDTH}" height="20" rx="3" fill="#fff"/>
    </clipPath>
    <g clip-path="url(#r)">
        <rect width="${LABEL_WIDTH}" height="20" fill="#555"/>
        <rect x="${LABEL_WIDTH}" width="${VALUE_WIDTH}" height="20" fill="${COLOR}"/>
        <rect width="${TOTAL_WIDTH}" height="20" fill="url(#s)"/>
    </g>
    <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
        <text aria-hidden="true" x="325" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="530">coverage</text>
        <text x="325" y="140" transform="scale(.1)" fill="#fff" textLength="530">coverage</text>
        <text aria-hidden="true" x="$((LABEL_WIDTH * 10 + VALUE_WIDTH * 5))" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="${TEXT_WIDTH}">${TEXT}</text>
        <text x="$((LABEL_WIDTH * 10 + VALUE_WIDTH * 5))" y="140" transform="scale(.1)" fill="#fff" textLength="${TEXT_WIDTH}">${TEXT}</text>
    </g>
</svg>
EOFSVG

echo "Generated SVG badge at /tmp/coverage-badge.svg"
