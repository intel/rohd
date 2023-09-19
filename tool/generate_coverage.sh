#!/bin/bash

# Copyright (C) 2022-2023 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# generate_coverage.sh
# Determines code coverage by tests and generates an HTML representation.
#
# 2022 May 5
# Author: Max Korbel <max.korbel@intel.com>

### WARNING ###
# The "x" option outputs all script commands. This allows you to track
# the progress of the execution, but MAY REVEAL ANY SECRETS PASSED TO THE SCRIPT!
set -euxo pipefail

#=============#

declare -r coverage_dir='build/coverage'
declare -r html_dir="${coverage_dir}/genhtml"

# requires enabling "coverage":
# > dart pub global activate coverage
dart pub global run coverage:test_with_coverage --branch-coverage --out=${coverage_dir}

# requires installing "lcov":
# > sudo apt install lcov
genhtml --output-directory=${html_dir} --rc lcov_branch_coverage=1 ${coverage_dir}/lcov.info

printf '\n%s\n\n' "Open ${html_dir}/index.html to review code coverage results."
