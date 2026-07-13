#!/bin/bash

# Copyright (C) 2023 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# check_markdown_links.sh
# Check Markdown links.
#
# 2023 February 23
# Author: Chykon

set -euo pipefail

config_file='.github/configs/mlc_config.json'
markdown_files=$(find . -path './doc/api' -prune -false -or -type f -name '*.md')

echo "${markdown_files}" | xargs npx markdown-link-check --quiet --config ${config_file}
