#!/bin/bash

# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# pana_source.sh
# GitHub Actions step: execute pana analysis on project source.
#
# 2025 September 26
# Author: Desmond A. Kirkpatrick

PATH="$PATH":"$HOME/.pub-cache/bin"

pana --exit-code-threshold 0 .
