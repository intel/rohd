#!/bin/bash

# Copyright (C) 2023 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_dart.sh
# GitHub Codespaces setup: Install Dart SDK according to the instructions from https://dart.dev/get-dart#install-using-apt-get.
#
# 2023 February 5
# Author: Chykon

set -euo pipefail

# Add Dart repository key.

declare -r input_pubkey_file='tool/gh_codespaces/pubkeys/dart.pub'
declare -r output_pubkey_file='/usr/share/keyrings/dart.gpg'

sudo gpg --output ${output_pubkey_file} --dearmor ${input_pubkey_file}

# Add Dart repository.

declare -r dart_repository_url='https://storage.googleapis.com/download.dartlang.org/linux/debian'
declare -r dart_repository_file='/etc/apt/sources.list.d/dart.list'

echo "deb [signed-by=${output_pubkey_file}] ${dart_repository_url} stable main" | sudo tee ${dart_repository_file}

# Install Dart.

sudo apt-get update
sudo apt-get install dart
