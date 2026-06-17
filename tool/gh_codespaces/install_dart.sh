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

sudo apt-get update
sudo apt-get install -y wget gpg apt-transport-https

sudo mkdir -p /usr/share/keyrings
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/dart.gpg >/dev/null

# Add Dart repository key.

echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" \
  | sudo tee /etc/apt/sources.list.d/dart_stable.list

# Install Dart.

sudo apt-get update
sudo apt-get install -y dart
