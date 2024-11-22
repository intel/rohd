#!/bin/bash

# Copyright (C) 2023 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# lint_markdown_files.sh
# Lint Markdown files.
#
# 2023 February 23
# Author: Chykon

set -euo pipefail

npx markdownlint-cli2
