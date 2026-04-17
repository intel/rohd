#!/bin/bash

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# analyze_source.sh
# GitHub Actions step: Analyze project source.
#
# 2022 October 9
# Author: Chykon

set -euo pipefail

dart analyze --fatal-infos

# Analyze sub-packages that have their own pubspec.yaml and are excluded
# from the root analysis_options.yaml.
for pkg in packages/rohd_hierarchy; do
  if [ -f "$pkg/pubspec.yaml" ]; then
    echo "Analyzing sub-package: $pkg"
    pushd "$pkg" > /dev/null
    dart pub get
    dart analyze --fatal-infos
    popd > /dev/null
  fi
done
